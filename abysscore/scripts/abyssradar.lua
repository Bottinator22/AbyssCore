require "/scripts/terra_vec2ref.lua"
require "/scripts/terra_vec3.lua"
require "/scripts/terra_renderutil.lua"
require "/scripts/abyssrenderutil.lua"
require "/scripts/terra_proxy.lua"
require "/scripts/rect.lua"
require "/scripts/poly.lua"

require "/scripts/abyssradar_interests.lua"
require "/scripts/abyssradar_portals.lua"
require "/scripts/abyssradar_recog.lua"

-- note: world time is used for 'last seen' numbers. this is somewhat inaccurate.
-- TODO: check for serverside player blips, in case a server spawns server master player entities

local font
local playerPositionPromises = {}
local serverPlayerPositions = {}
local unknownCharSet = {}

local fUENotWorking = false

local promiseTimeout = 30

local blipLoaderId

local function ensureLoader()
    if not blipLoaderId or not world.entityExists(blipLoaderId) then
        blipLoaderId = world.spawnStagehand(mcontroller.position(),"abyss_radarLoader")
    end
    world.callScriptedEntity(blipLoaderId,"keepAlive")
end

local function isPuppet()
    return entity.entityType() ~= "player"
end

local doGTWarn = true
local function getGenericTime()
    if threads then
        local t = world.sendEntityMessage(entity.id(),"abyss_getGenericTime"):result()
        if not t then
            if doGTWarn then
                doGTWarn = false
                sb.logWarn("abyss_getGenericTime message handler not responding?")
            end
            return 0
        end
        return t
    else
        return os.clock() -- less accurate but works
    end
end
local excludeSameMaster = true
local function isSameMaster(id1, id2)
  if (id1 >= 0) == (id2 >= 0) then
    if id1 >= 0 and id2 >= 0 then
      return true
    elseif math.floor(id1 / 65536) == math.floor(id2 / 65536) then
      return true
    else
      return false
    end
  end
  return false
end
local includeOther = false
local includeObjects = false
local includeProjectiles = false
local includeOld = false
local function excludeEntity(e)
    if excludeSameMaster and isSameMaster(e, entity.id()) then
        return true
    end
    if e == entity.id() then
        return true
    end
    return false
end
local function ensureLocalAnimator()
    if not localAnimator then
        localAnimator = terra_proxy.setupProxy("localAnimator",entity.id())
    end
    return localAnimator
end
radarColours = {
    {255,0,0},
    {0,0,255},
    {0,255,0},
    {255,127,0},
    {255,255,0},
    {0,255,255},
    {0,127,255},
    {127,0,255},
    {255,0,255},
    {0,255,127},
    {127,255,0}
}
local colours = radarColours
local pingTimescale = 1
local lastPing = 0
local commonUniqueEntities={
    mechbeacon={
        name="Mech Beacon",
        colour={0,255,0}
    }
}
function newUniqueEColour()
    local interestN = 0
    for k,v in next, commonUniqueEntities do
        interestN = interestN + 1
    end
    local n = #colours
    local i = ((interestN-1)%n)+1
    return colours[i]
end
local queryLimitMin = 1
local queryLimitMax = 10
local queryLimit = queryLimitMax
local playerPositionsToRender = {}
local passiveProcessed = 0
local queriesSent = 0
local queriesSentTotal = 0
local myCid
local connectionNames = {}
local connectionPlayers = {}
local function connectionId(eid)
    if eid >= 0 then
        return 0 -- server
    else
        return -math.floor(eid/65536) -- client
    end
end
local function connectionKey(cid)
    return string.format("c_%d",cid)
end
local minCID = 1
local minSWCID = 16384
local function connectionName(cid)
    if cid == 0 then
        return "Server"
    elseif cid >= minSWCID and universe and universe.serverOpenProtocolVersion and universe.serverOpenProtocolVersion() >= 16 then
        return connectionName(cid-minSWCID+minCID).." (Subworld)"
    else
        return connectionNames[connectionKey(cid)] or "Unknown"
    end
end
local referenceType
local reference
local function distanceReferencePosition()
    if referenceType == "camera" then
        return camera.position()
    elseif referenceType == "interest" then
        return reference
    elseif referenceType == "player" then
        return reference.pos
    else
        return mcontroller.position()
    end
end
local lastHadPlayer = 0
local lastHadNearbyPlayer = 0
local function playerDetected(pos)
    if not root.getConfiguration then
        return
    end
    if isPuppet() then
        return
    end
    local minSpacing = (root.getConfiguration("abyss_radarPingSoundMinSpacing") or 10)
    if getGenericTime()-lastHadPlayer > minSpacing then
        if fUENotWorking and root.getConfiguration("abyss_radarLoadingEnabled") then
            return -- avoid spamming ears
        end
        if not localAnimator then
            return
        end
        localAnimator.playAudio(root.getConfiguration("abyss_radarPingSound") or "/sfx/interface/ship_confirm2.ogg", 0, root.getConfiguration("abyss_radarPingSoundVol") or 2)
    end
    lastHadPlayer = getGenericTime()
    if world.magnitude(pos,distanceReferencePosition()) < (root.getConfiguration("abyss_radarPingNearbyDistance") or 300) then
        if getGenericTime()-lastHadNearbyPlayer > (root.getConfiguration("abyss_radarPingSoundMinSpacing") or 10) then
            if fUENotWorking and root.getConfiguration("abyss_radarLoadingEnabled") then
                return -- avoid spamming ears
            end
            if not localAnimator then
                return
            end
            localAnimator.playAudio(root.getConfiguration("abyss_radarPingNearbySound") or "/sfx/interface/rocket_lockon.ogg", 0, root.getConfiguration("abyss_radarPingNearbySoundVol") or (root.getConfiguration("abyss_radarPingSoundVol") or 2)*0.75)
        end
        lastHadNearbyPlayer = getGenericTime()
    end
end
radarDistanceReferencePosition = distanceReferencePosition
local lastTimedOut = 0
local lastNotTimedOut = 0
local function updatePlayerPosPromise(k,v,isLive)
    local promise = playerPositionPromises[k]
    local sameWorld = v.worldId == player.worldId()
    local delay = 5
    if sameWorld then
        delay = 1
    end
    if v.lastChecked > world.time()+5 then
        -- world time went backwards.
        v.lastChecked = 0
    end
    if promise then
        if promise:finished() or world.time()-v.lastChecked > promiseTimeout then
            if world.time()-v.lastChecked > promiseTimeout then
                --chat.addMessage(string.format("Radar query for %s timed out",v.name))
                lastTimedOut = getGenericTime()
                fUENotWorking = lastTimedOut > lastNotTimedOut+10
            else
                lastNotTimedOut = getGenericTime()
                fUENotWorking = false
            end
            if promise:succeeded() then
                local npos = promise:result()
                v.pos[1] = npos[1]
                v.pos[2] = npos[2]
                v.exists = true
                v.worldId = player.worldId()
                v.old = false
                v.lastSeen = os.time()
            elseif v.worldId == player.worldId() then
                v.exists = false
            end
            playerPositionPromises[k] = nil
        end
    elseif (isLive or queriesSent < queryLimit) and (v.exists or v.lastCheckedWorld ~= player.worldId() or world.time()-v.lastChecked > delay) then
        if isLive then
            queryLimit = math.max(queryLimit - 1,queryLimitMin)
        else
            queriesSent = queriesSent + 1
        end
        queriesSentTotal = queriesSentTotal + 1
        v.lastChecked = world.time()
        v.lastCheckedWorld = player.worldId()
        playerPositionPromises[k] = world.findUniqueEntity(v.uuid)
    end
    return queriesSent >= queryLimit
end
local playerPositionUpdater
local initialized = false
local radarFinding
local radarFindingType
function radarPlayerPositions(positions)
    if #positions % 1 == 1 then
        sb.logWarn("Player position list is incorrect!")
        return
    end
    if #positions/2 < #serverPlayerPositions then
        -- just clear it all out
        serverPlayerPositions = {}
    end
    for i=0,#positions/2-1 do
        local id = positions[i*2+1] -- entity id, may not exist
        local v = positions[i*2+2]
        if type(v) ~= "table" or type(v[1]) ~= "number" or type(v[2]) ~= "number" or type(id) ~= "number" then
            sb.logWarn("Broken player position detected!")
            return
        end
        v[3] = 255
        v[4] = connectionId(id)
        serverPlayerPositions[i+1] = v
    end
end
local function removeDirectives(n)
    local nn = ""
    local iD = false
    for i=1,#n do
        local c = string.sub(n,i,i)
        if c == "^" then
            iD = true
        end
        if not iD then
            nn = nn..c
        end
        if c == ";" then
            iD = false
        end
    end
    return nn
end
local function playerByPartialName(n)
    local sn = string.lower(removeDirectives(n))
    local num = 0
    local out
    for k,v in next, storage.radarPlayerPositions do
        if v.worldId == player.worldId() and v.exists and string.sub(string.lower(removeDirectives(v.name)),1,#sn) == sn then
            out = v
            num = num + 1
        end
    end
    if num > 1 then
        -- try again with case sensitivity
        out = nil
        num = 0
        sn = removeDirectives(n)
        
        for k,v in next, storage.radarPlayerPositions do
            if v.worldId == player.worldId() and v.exists and string.sub(removeDirectives(v.name),1,#sn) == sn then
                out = v
                num = num + 1
            end
        end
        
        if num > 1 then
            return num
        else
            return out
        end
    end
    return out
end
radarFindPlayer = playerByPartialName
local scannerPunchyParams
function radarInit()
    if not player then
        return
    end
    if isPuppet() then
        return
    end
    scannerPunchyParams = sb.jsonMerge(root.assetJson("/scripts/abyssScannerParams.json"), {ownerId=entity.id()})
    if root.getConfiguration then
        for k,v in next, root.assetJson("/scripts/abyssUniqueObjects.json") do
            if not commonUniqueEntities[k] then
                commonUniqueEntities[k] = {name=v,colour=newUniqueEColour(),uuid=k}
            end
        end
    end
    message.setHandler("abyssPlayerPositions", function (_,l,...)
        -- note: could theoretically be jammed or broken
        local positions = {...}
        radarPlayerPositions(positions)
    end)
    radarInterestInit()
    radarPortalInit()
    message.setHandler("/radarSameMaster",function(_,l)
        if not l then return "no" end
        excludeSameMaster = not excludeSameMaster
        if excludeSameMaster then
            return "Now excluding same master entities."
        else
            return "No longer excluding same master entities."
        end
    end)
    message.setHandler("/radarFind",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #c == 0 then
            radarFindingType = nil
            return "No longer finding."
        end
        if #split < 2 then
            return "Usage: /radarFind <entity type> <entity typename>"
        end
        radarFinding = split[2]
        radarFindingType = split[1]
    end)
    message.setHandler("/radarObjects",function(_,l)
        if not l then return "no" end
        includeObjects = not includeObjects
        if includeObjects then
            return "Now including object-likes."
        else
            return "No longer including object-likes."
        end
    end)
    message.setHandler("/radarProjectiles",function(_,l)
        if not l then return "no" end
        includeProjectiles = not includeProjectiles
        if includeProjectiles then
            return "Now including projectiles."
        else
            return "No longer including projectiles."
        end
    end)
    message.setHandler("/radarOther",function(_,l)
        if not l then return "no" end
        includeOther = not includeOther
        if includeOther then
            return "Now including item drops."
        else
            return "No longer including item drops."
        end
    end)
    message.setHandler("/radarOld",function(_,l)
        if not l then return "no" end
        includeOld = not includeOld
        if includeOld then
            return "Now including old player positions."
        else
            return "No longer including old player positions."
        end
    end)
    message.setHandler("/radarClearOld",function(_,l)
        if not l then return "no" end
        -- clears old player positions from storage
        -- only affects this world
        local newPlayerPositions = {}
        for k,v in next, storage.radarPlayerPositions do
            if v.world ~= player.worldId() or not v.old then
                newPlayerPositions[k] = v
            end
        end
        storage.radarPlayerPositions = newPlayerPositions
    end)
    message.setHandler("/radarClearAll",function(_,l)
        if not l then return "no" end
        -- clears ALL player positions from storage
        storage.radarPlayerPositions = {}
    end)
    message.setHandler("/radarStatus",function(_,l)
        if not l then return "no" end
        local numTracked = 0
        local numTrackedWorld = 0
        local numTrackedRecent = 0
        local numTrackedActive = 0
        local numTrackedKnown = 0
        for k,v in next, storage.radarPlayerPositions do
            numTracked = numTracked + 1
            if v.worldId == player.worldId() then
                numTrackedWorld = numTrackedWorld + 1
                if not v.old then
                    numTrackedRecent = numTrackedRecent + 1
                end
                if v.exists then
                    numTrackedActive = numTrackedActive + 1
                    if v.known then
                        numTrackedKnown = numTrackedKnown + 1
                    end
                end
            end
        end
        local unknown = 0
        for k,v in next, serverPlayerPositions do
            local cid = v[4]
            if cid ~= myCid and not connectionPlayers[connectionKey(cid)] then
                unknown = unknown + 1
            end
        end
        local out = string.format("Tracked unique entities: %d (%d on world, %d recent, %d active, %d active&known)\
Serverside player blips: %d (%d unidentified)",
                                  numTracked,numTrackedWorld,numTrackedRecent,numTrackedActive,numTrackedKnown,
                                  #serverPlayerPositions,unknown)
        return out
    end)
    message.setHandler("/radarUnknownChars",function(_,l)
        if not l then return "no" end
            --[[
        local out = "Unknown characters: "
        local any = false
        for k,_ in next, unknownCharSet do
            if not any then
                any = true
            else
                out = out..", "
            end
            out = out..k
        end
        if any then
            return out
        else
            return "Haven't attempted to draw any unknown characters yet."
        end]]
        return "TODO: this crashes the game."
    end)
    message.setHandler("/radarAutoLoad",function(_,l)
        if not l then return "no" end
        if not world.entity then
            return "Cannot auto-load, necessary features may not be implemented."
        end
        local en = not root.getConfiguration("abyss_radarLoadingEnabled")
        root.setConfiguration("abyss_radarLoadingEnabled",en)
        if en then
            return "Auto-loading unidentified blips."
        else
            return "No longer auto-loading blips."
        end
    end)
    message.setHandler("/radarReference",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #split <= 0 then
            referenceType = nil
            return
        end
        local i = split[2]
        if split[1] == "self" then
            referenceType = nil
        elseif split[1] == "camera" then
            referenceType = "camera"
        elseif split[1] == "interest" then
            if not i then
                return "Need an interest."
            end
            local interest = radarInterests[i]
            if not interest then
                return "Can't find an interest of that name."
            end
            if interest[3] ~= player.worldId() then
                return "That interest isn't on-world."
            end
            referenceType = "interest"
            reference = interest
        elseif split[1] == "player" then
            if not i then
                return "Need a player."
            end
            local p = playerByPartialName(i)
            if not p then
                return "Couldn't find any players of that name."
            end
            if type(p) == "number" then
                return string.format("There are %d players that fit that name.",p)
            end
            referenceType = "player"
            reference = p
        else
            return "Not a valid reference type."
        end
    end)
    
    storage.radarPlayerPositions = storage.radarPlayerPositions or {}
    for k,v in next, storage.radarPlayerPositions do
        if v.worldId == player.worldId() then
            v.old = true
            v.exists = false
        end
    end
    font = root.assetJson("/ab_font/font.json")
    playerPositionUpdater = coroutine.create(function()
        local lastYielded
        local lastProcessed
        while true do
            local ignoreKnown = root.getConfiguration("abyss_ignoreKnown")
            for k,v in next, storage.radarPlayerPositions do
                passiveProcessed = passiveProcessed + 1
                if world.entityExists(v.id) and world.entityUniqueId(v.id) == v.uuid then
                    playerPositionPromises[k] = nil
                else
                    local hitLimit = updatePlayerPosPromise(k,v)
                    if (v.known or ignoreKnown) and v.worldId == player.worldId() and (includeOld or not v.old) and not player.getProperty("abyss_radarHideLongRange") then
                        playerPositionsToRender[k] = v
                    end
                    if hitLimit then
                        coroutine.yield()
                        lastYielded = k
                    end
                end
                if k == lastYielded then
                    coroutine.yield()
                    lastYielded = k -- note: these are almost never deleted.
                end
                lastProcessed = k
            end
            if not lastYielded or not storage.radarPlayerPositions[lastYielded] then
                coroutine.yield()
                lastYielded = lastProcessed
            end
        end
    end)
    myCid = connectionId(player.id())
    connectionNames[connectionKey(myCid)] = "Self"
    initialized = true
end
local function playerPosKey(v)
    return string.format("p_%s",world.entityUniqueId(v))
end
local function entityPosKey(v)
    return string.format("e_%s",world.entityUniqueId(v))
end
local function maybePlayerAlias(v)
    return playerAlias(world.entityUniqueId(v)) or world.entityName(v)
end
local friendlyColour = {0,255,0}
local enemyColour = {255,0,0}
local playerColour = {0,255,255}
local gonePlayerColour = {0,127,127,127}
local enemyPlayerColour = {255,255,0}
local goneEnemyPlayerColour = {127,127,0,127}
local function updatePlayer(v)
    local k = playerPosKey(v)
    local dat = storage.radarPlayerPositions[k] or {id=v,name=nil,lastChecked=0,uuid=nil,exists=true,type="player",old=false,pos={0,0},worldId=nil}
    dat.pos = world.entityPosition(v)
    dat.uuid = world.entityUniqueId(v)
    dat.enemy = entity.isValidTarget(v)
    dat.name = playerAlias(dat.uuid) or world.entityName(v)
    dat.known = playerKnown(dat.uuid)
    dat.exists = true
    dat.old = false
    dat.id = v
    dat.worldId = player.worldId()
    dat.lastChecked = world.time()
    dat.lastSeen = os.time()
    if v < 0 and v ~= player.id() then
        local key = connectionKey(connectionId(v))
        connectionNames[key] = playerAlias(dat.uuid) or world.entityName(v)
        connectionPlayers[key] = dat
    end
    storage.radarPlayerPositions[k] = dat
    return dat
end
local namelessTypes = {
    projectile=true,
    vehicle=true,
    stagehand=true,
    object=true,
    plant=true,
    plantDrop=true,
    itemDrop=true
}
local nameKindTypes = {
    projectile=true,
    vehicle=true,
    stagehand=true,
    --object=true,
    --plant=true,
    --plantDrop=true
}
local kindlessTypes = {
    player=true,
    plant=true,
    plantDrop=true,
    itemDrop=true
}
local humanoidTypes = {
    player=true,
    npc=true
}
local actorTypes = {
    player=true,
    npc=true,
    monster=true
}
local collisionTypes = {
    -- all PhysicsEntity types, excluding players/npcs/monsters since they can't have moving collisions
    --player=true,
    --npc=true,
    --monster=true,
    vehicle=true,
    projectile=true,
    object=true
}
local selfNoteDistance = 20
local cameraNoNoteDistance = 100
local function noteCheck(p)
    local cpos = (camera.position or mcontroller.position)()
    local mpos = mcontroller.position()
    local cdis = world.magnitude(p,cpos)
    local mdis = world.magnitude(p,mpos)
    if mdis < selfNoteDistance and cdis > cameraNoNoteDistance then
        return true
    end
    for k,v in next, radarInterests do
        if v[3] == player.worldId() then
            if v[4].box then
                if rect.contains(rect.translate(v[4].box,v),p) then
                    return true
                end
            else
                if world.magnitude(p,v) < (v[4].radius or radarInterestDefaultNoteDistance) then
                    return true
                end
            end
        end
    end
    return false
end
local verbose = false
function radarSetVerbose(v)
    verbose = v
end

local window = {0,0,1,1}
local cameraPos = nil
local cameraOffset = {0,0}
local relWindow1 = {0,0}
local relWindow2 = {0,0}
local relWindow = {0,0,1,1}
local relAim = {0,0}
local scale = 1
local radarDisMult = 1
local renderData = {}
function radarRenderData()
    renderData.window = window
    renderData.cameraPos = cameraPos
    renderData.cameraOffset = cameraOffset
    renderData.relWindow1 = relWindow1
    renderData.relWindow2 = relWindow2
    renderData.relWindow = relWindow
    renderData.scale = scale
    renderData.radarDisMult = radarDisMult
    renderData.relAim = relAim
    return renderData
end
local function drawBox(r,c,t,layer)
    local ls = {
        generateLineDrawable({r[1],r[2]},{r[1],r[4]}),
        generateLineDrawable({r[1],r[4]},{r[3],r[4]}),
        generateLineDrawable({r[3],r[4]},{r[3],r[2]}),
        generateLineDrawable({r[3],r[2]},{r[1],r[2]})
    }
    for _,l in next, ls do
        l.color = c
        l.width = t
        l.fullbright = true
        localAnimator.addDrawable(l,layer)
    end
end
local function strokePoly(p,c,t,layer)
    for k,v in next, p do
        local n = p[k + 1] or p[1]
        local l = generateLineDrawable(v,n)
        l.color = c
        l.width = t
        l.fullbright = true
        localAnimator.addDrawable(l,layer)
    end
end
local function lineTowardsPos(p, c, d)
    if radarVisibleLevel < 0 then return end
    local dis = world.distance(p, distanceReferencePosition())
    local angle = vec2.angle(dis)
    if vec2.mag(dis) < 0.1 then
        return
    end
    local o = world.distance(distanceReferencePosition(),mcontroller.position())
    local s = vec2.add(vec2.withAngle(angle, (3*d*radarDisMult  )*scale),o)
    local t = vec2.add(vec2.withAngle(angle, (3*d*radarDisMult+d)*scale),o)
    local l = generateLineDrawable(s,t)
    l.color = c
    l.width = scale*d
    l.fullbright = true
    localAnimator.addDrawable(l, "Overlay+32002")
end
local function lineTowards(e, c)
    return lineTowardsPos(world.entityPosition(e),c, 1)
end

local function printTime(t)
    if t > 24*60*60 then -- 1 day
        return string.format("%.0fd",t/60/60/24)
    elseif t > 75*60 then -- 75 minutes, 1.25 hours
        return string.format("%.0fh",t/60/60)
    elseif t > 75 then -- 1.25 minutes
        return string.format("%.0fm",t/60)
    else
        return string.format("%.0fs",t)
    end
end
local hoveredIndications = {}
local hoveredDis = 2
local function indicatePosition_onlyOnscreen(p, c, d, o, ptype, priority)
    if radarVisibleLevel < 1 then
        return
    end
    local rel = world.distance(p, cameraPos())
    if not rect.contains(relWindow, rel) then
        return
    end
    local tm = world.magnitude(rel,relAim) 
    local m = tm+(priority or 0)
    if tm < hoveredDis then
        table.insert(hoveredIndications,{
            dis=tm,
            disval=m,
            colour={c[1],c[2],c[3],255},
            size=d,
            pos=p,
            relPos=rel,
            other=o,
            othertype=ptype
        })
    end
    local drawable = {
        position=vec2.add(rel,cameraOffset),
        color=c,
        fullbright=true,
        poly={
            {d,0},{0,d},{-d,0},{0,-d}
        }
    }
    localAnimator.addDrawable(drawable, "Overlay+32002")
end
local function indicatePosition(p, c, d, o, ptype, priority)
    if radarVisibleLevel < 1 then
        return
    end
    local rel = world.distance(p, cameraPos())
    if rel[1] < relWindow[1]+2 then
        rel[1] = relWindow[1]+2
    elseif rel[1] > relWindow[3]-2 then
        rel[1] = relWindow[3]-2
    end
    if rel[2] < relWindow[2]+2 then
        rel[2] = relWindow[2]+2
    elseif rel[2] > relWindow[4]-2 then
        rel[2] = relWindow[4]-2
    end
    local tm = world.magnitude(rel,relAim) 
    local m = tm+(priority or 0)
    if tm < hoveredDis then
        table.insert(hoveredIndications,{
            dis=tm,
            disval=m,
            colour={c[1],c[2],c[3],255},
            size=d,
            pos=p,
            relPos=rel,
            other=o,
            othertype=ptype
        })
    end
    local drawable = {
        position=vec2.add(rel,cameraOffset),
        color=c,
        fullbright=true,
        poly={
            {d,0},{0,d},{-d,0},{0,-d}
        }
    }
    localAnimator.addDrawable(drawable, "Overlay+32002")
end
local function indicatePosition_withPortals(p, c, d, o, ptype, priority)
    indicatePosition(p, c, d, o, ptype, priority)
    for _,tp in next, radarPortalsTransfers(p) do
        indicatePosition_onlyOnscreen(tp, c, d*0.5, o, {"portal",ptype}, priority+0.25)
    end
end
local function indicateEntity(e, c, priority)
    return indicatePosition(world.entityPosition(e),c,1,e,"entity",priority or 0)
end
local function indicateEntity_withPortals(e, c, priority)
    return indicatePosition_withPortals(world.entityPosition(e),c,1,e,"entity",priority or 0)
end
local function indicAlpha(c)
    return {c[1],c[2],c[3],(c[4] or 255)/2}
end
radarIndicatePosition = indicatePosition
radarIndicateEntity = indicateEntity
radarLineTowardsPos = lineTowardsPos
radarLineTowardsEntity = lineTowardsEntity
radarDrawBox = drawBox
radarIndicAlpha = indicAlpha

function radarExtra()
end
radarExtraDescribe = {
    interest=radarDescribeInterest,
    portal=radarDescribePortal
}

radarVisibleLevel = 0
function radar(hidden,disMult)
    if isPuppet() then
        return
    end
    if not initialized then
        --sb.logWarn("Radar was not initialized! Initializing late.")
        radarInit()
        return
    end
    radarDisMult = disMult or 1
    queriesSent = 0
    queriesSentTotal = 0
    queryLimit = queryLimitMax
    passiveProcessed = 0
    
    radarVisibleLevel = -1
    -- -1 = hidden
    -- 0 = standard, just draws lines
    -- 1 = draws coloured blobs on entity positions and the closest point on-screen to said positions, also shows information on the closest one under the mouse
    if type(hidden) == "number" then
        radarVisibleLevel = hidden-1
        hidden = hidden == 0
    elseif not hidden then
        radarVisibleLevel = 0
    end
    
    if getGenericTime() < lastPing then
        -- time jumped backwards, likely due to reload
        lastPing = getGenericTime()
    end
    if getGenericTime() > lastPing + 3/pingTimescale then
        lastPing = getGenericTime()
        world.spawnMonster("punchy", mcontroller.position(), scannerPunchyParams)
    end
    -- render lines to show the locations of nearby entities and all players in the world, as well as mech beacons
    local interestNoteColourHSV = {math.cos(world.time()*5)*30+30,1,1}
    local interestNoteColour = renderutil.toRGB(interestNoteColourHSV)
    
    window = camera and camera.worldScreenRect() or world.clientWindow()
    cameraPos = camera and camera.position or mcontroller.position
    cameraOffset = world.distance(cameraPos(),mcontroller.position())
    relWindow1 = world.distance(rect.ll(window),cameraPos())
    relWindow2 = world.distance(rect.ur(window),cameraPos())
    relWindow = {relWindow1[1],relWindow1[2],relWindow2[1],relWindow2[2]}
    relAim = world.distance(tech.aimPosition(),cameraPos())
    scale = (window[4] - window[2])/65
    if not ensureLocalAnimator() then
        return
    end
    -- TODO: replacing this entire list every frame is kinda... bad
    hoveredIndications = {}
    
    lineTowardsPos(mcontroller.position(),{255,255,255},1)
    if verbose then
        indicateEntity_withPortals(entity.id(),{255,255,255,127},0.5)
    else
        indicatePosition_withPortals(mcontroller.position(),{255,255,255,127},1,"Self","generic",0.5)
    end
    if referenceType == "camera" then
        indicatePosition_withPortals(distanceReferencePosition(),{255,255,255,127},1,"Camera","generic",0.5)
    end
    for k,v in next, radarPortalsTransfers(distanceReferencePosition()) do
        lineTowardsPos(v,{255,255,255},1.5)
    end
    for k,v in next, commonUniqueEntities do
        if not v.pos then
            if not v.promise then
                v.promise = world.findUniqueEntity(k)
            elseif not v.failed and v.promise:finished() then
                if v.promise:succeeded() then
                    v.pos = v.promise:result()
                else
                    v.failed = true
                    commonUniqueEntities[k] = nil -- remove it so it isn't iterated anymore
                end
            end
        else
            lineTowardsPos(v.pos,v.colour,2)
            indicatePosition(v.pos,indicAlpha(v.colour),2,v,"commonUniqueEntity")
        end
    end
    radarBlipPortals()
    radarBlipInterests()
    
    local numActive = 0
    for k,v in next, playerPositionsToRender do
        if world.entityExists(v.id) and world.entityUniqueId(v.id) == v.uuid then
            playerPositionPromises[k] = nil
            playerPositionsToRender[k] = nil
        else
            numActive = numActive + 1
            local c = gonePlayerColour
            local priority = 1
            if v.exists and noteCheck(v.pos) or (referenceType == "player" and reference == v) then
                c = interestNoteColour
                priority = -1
            elseif v.enemy then
                if v.exists then
                    c = enemyPlayerColour
                    priority = -1
                else
                    c = goneEnemyPlayerColour
                end
            elseif v.exists then
                playerDetected(v.pos)
                c = playerColour
                priority = -0.5
            end
            if v.old then
                c = {c[1]*0.5,c[2]*0.5,c[3]*0.5,c[4]}
                if not includeOld then
                    playerPositionsToRender[k] = nil
                end
            elseif v.exists then
                if fUENotWorking then
                    local t = math.max(world.time()-v.lastChecked,0)
                    local perc = 0.5+(1-math.min(t/promiseTimeout,1))*0.5
                    c = {c[1]*perc,c[2]*perc,c[3]*perc,(c[4] or 255)*perc}
                end
                updatePlayerPosPromise(k,v,false)
            end
            lineTowardsPos(v.pos, c, 1)
            if v.exists then
                indicatePosition_withPortals(v.pos,indicAlpha(c),1,v,"player",priority)
            else
                indicatePosition(v.pos,indicAlpha(c),1,v,"player",priority)
            end
        end
    end
    coroutine.resume(playerPositionUpdater)
    
    local numPromises = 0
    for k,v in next, playerPositionPromises do
        if v then
            numPromises = numPromises + 1
        end
    end
    sb.setLogMap("abyssradar_player_queries",string.format("%d (%d/%d passive)",queriesSentTotal,queriesSent,queryLimit))
    sb.setLogMap("abyssradar_player_status",string.format("aq: %d, pp: %d, a: %d %s",numPromises, passiveProcessed, numActive, fUENotWorking and "(fUE not working)" or ""))
    sb.setLogMap("abyssradar_players_onWorld",string.format("%d (ls %.1f)",#serverPlayerPositions,getGenericTime()-lastPing))
    
    local types = {"npc","monster", "vehicle","stagehand","plantDrop"}
    if includeProjectiles then
        table.insert(types, "projectile")
    end
    if includeObjects then
        table.insert(types, "object")
        table.insert(types, "plant")
        --table.insert(types, "plantDrop")
    end
    if includeOther then
        table.insert(types, "itemDrop")
    end
    local hadFindingType = true
    if radarFindingType then
        hadFindingType = false
        for _,v in next, types do
            if v == radarFindingType then
                hadFindingType = true
                break
            end
        end
        if not hadFindingType then
            table.insert(types,radarFindingType)
        end
    end
    if hidden then
        -- don't waste time on queries that aren't visible
        types = {}
    end
    if not world.players then
        table.insert(types, "player")
    end
    -- TODO: add world.entities binding to oSB so this isn't necessary
    local ignoreKnown = root.getConfiguration("abyss_ignoreKnown")
    local nearbyEntities = world.entities and world.entities({includedTypes=types}) or world.entityQuery(cameraPos(), 300, {includedTypes=types})
    for k,v in next, nearbyEntities do
        if (not hadFindingType) and world.entityType(v) == radarFindingType and world.entityTypeName(v) ~= radarFinding then
        elseif not excludeEntity(v) then
            local colour = {0,255,0}
            local priority = 0
            local t = world.entityType(v)
            if t == "vehicle" then
                if world.entityCanDamage(v, entity.id()) then
                    colour = {255,0,255}
                else
                    colour = {0,0,255}
                end
            elseif t == "stagehand" then
                colour = {255,255,255}
            elseif t == "itemDrop" or t == "plantDrop" then
                colour = {0,127,0}
            elseif t == "object" or t == "plant" then
                colour = {0,0,0}
            elseif t == "projectile" then
                if world.entityCanDamage(v, entity.id()) then
                    colour = {255,127,0}
                else
                    colour = {0,127,255}
                end
            elseif t == "player" and noteCheck(world.entityPosition(v)) then
                priority = -1
                colour = interestNoteColour
            elseif entity.isValidTarget(v) then
                colour = {255,0,0}
                if world.entityType(v) == "player" then
                    priority = -1
                    colour = {255,255,0}
                end
            elseif t == "player" then
                priority = -0.5
                colour = {0,255,255}
            end
            if t == radarFindingType then
                if world.entityTypeName(v) == radarFinding then
                    priority = 10
                    colour = interestNoteColour
                end
            end
            -- TODO: recog for here, in the... extremely unlikely case that someone makes recognition for non-oSB
            lineTowards(v,colour)
            indicateEntity(v,indicAlpha(colour),priority)
            if t == "player" then
                -- portals can't really exist on non-oSB, so don't bother
                playerDetected(world.entityPosition(v))
                updatePlayer(v)
            end
        end
    end
    if world.players then
        local nearbyPlayers = world.players()
        for k,v in next, nearbyPlayers do
            if not excludeEntity(v) then
                playerDetected(world.entityPosition(v))
                local p = updatePlayer(v)
                local priority = -0.5
                local colour = {0,255,255}
                local pos = world.entityPosition(v)
                if noteCheck(pos) or (referenceType == "player" and reference == p) then
                    priority = -1
                    colour = interestNoteColour
                elseif entity.isValidTarget(v) then
                    priority = -1
                    colour = {255,255,0}
                end
                if ignoreKnown or playerKnown(world.entityUniqueId(v)) then
                    lineTowards(v,colour)
                    indicateEntity_withPortals(v,indicAlpha(colour),priority)
                end
            end
        end
    end
    local toLoad
    --local newServerPlayerPositions = {}
    for k,v in next, serverPlayerPositions do
        local dis = world.magnitude(v, mcontroller.position())
        
        local pl = connectionPlayers[connectionKey(v[4])]
        local unidentified = v[4] ~= myCid and (not pl or not pl.exists)
        if unidentified then
            local crgb
            local size = 0.5
            if noteCheck(v) then
                crgb = interestNoteColour
                size = 0.75
            else
                local relDis = 1-dis/5000 -- a bit more than the farthest you can be from another entity on a large world
                local h = relDis*120
                while h < 0 do
                    h = h + 360
                end
                local c = {h,math.max(1-((dis/50000)%1),0),math.max(1-dis/600000,0),math.floor(v[3])/255}
                crgb = renderutil.toRGB(c)
            end
            lineTowardsPos(v, crgb, 1.5)
            indicatePosition(v,indicAlpha(crgb),size,v[4],"blip",0.5)
        end
        v[3] = math.max(v[3] - pingTimescale,64)
        --[[if v[3] > 0 then
            table.insert(newServerPlayerPositions, v)
        end]]
        if unidentified then
            toLoad = v
        end
    end
    if toLoad and root.getConfiguration("abyss_radarLoadingEnabled") and world.entity then
        ensureLoader()
        world.callScriptedEntity(blipLoaderId,"stagehand.setPosition",toLoad)
    elseif blipLoaderId then
        if world.entityExists(blipLoaderId) then
            -- keep it on self until it dies
            world.callScriptedEntity(blipLoaderId,"stagehand.setPosition",mcontroller.position())
        else
            blipLoaderId = nil
        end
    end
    --serverPlayerPositions = newServerPlayerPositions
    local function noDirectives(n)
        local o = ""
        local inDirective = false
        for c in string.gmatch(n,".") do
            if c == "^" then
                inDirective = true
            elseif c == ";" then
                inDirective = false
            elseif not inDirective then
                o = o..c
            end
        end
        return o
    end
    -- TODO: I don't like this... probably good enough tho, there won't be that many at a time
    table.sort(hoveredIndications,function(a,b)
        return a.disval < b.disval
    end)
    if radarVisibleLevel >= 1 and hoveredIndications[1] then
        local text
        local numOldPlayers = 0
        local numPlayers = 0
        local numInterests = 0
        for k,v in next, hoveredIndications do
            if (v.othertype == "entity" and world.entityType(v.other) == "player") or (v.othertype == "player" and v.other.exists) then
                numPlayers = numPlayers + 1
            elseif v.othertype == "player" and not v.other.exists then
                numOldPlayers = numOldPlayers + 1
            elseif v.othertype == "interest" then
                numInterests = numInterests + 1
            end
        end
        local renderingPlayerList = numPlayers > 1
        local renderingOldPlayerList = numOldPlayers > 1 and hoveredIndications[1].othertype == "player" and not hoveredIndications[1].other.exists
        local renderingInterestList = numInterests > 1 and hoveredIndications[1].othertype == "interest"
        local renderingList = (renderingPlayerList or renderingInterestList or renderingOldPlayerList) and not verbose
        local size
        local closestRelPos
        local colour
        if not renderingList then
            -- elaborate on the closest blip
            local closestIndicated = hoveredIndications[1]
            size = closestIndicated.size
            closestRelPos = closestIndicated.relPos
            colour = closestIndicated.colour
            local other = closestIndicated.other
            local othertype = closestIndicated.othertype or "none"
            if type(othertype) == "table" then
                if othertype[1] == "portal" then
                    othertype = othertype[2]
                end
            end
            local fstr = "%.1f"
            if verbose then
                fstr = "%.3f"
            end
            text = string.format(fstr,world.magnitude(closestIndicated.pos,distanceReferencePosition()))
            if othertype == "entity" and world.entity then
                -- likely an entity, show info about entity
                local e = world.entity(other)
                local etype = e:type()
                text = text..string.format("\nType: %s", etype)
                local rel = world.distance(e:position(),mcontroller.position())
                if not namelessTypes[etype] then
                    if etype == "player" then
                        text = text..string.format("\nName: %s", noDirectives(playerAlias(e:uniqueId()) or e:name()))
                    else
                        text = text..string.format("\nName: %s", noDirectives(e:name()))
                    end
                end
                if not kindlessTypes[etype] then
                    text = text..string.format("\nKind: %s", nameKindTypes[etype] and e:name() or e:typeName())
                end
                if etype == "itemDrop" then
                    text = text..string.format("\nItem: %s", world.itemDropItem(other).name)
                end
                if etype == "stagehand" and e:getParameter("type") then
                    -- print additional data about it
                    local kind = world.entityName(other)
                    if kind == "messenger" then
                        local messageType = e:getParameter("messageType")
                        text = text..string.format("\nMessage: %s", messageType)
                        if messageType == "playAltMusic" then
                            local musicStr = ""
                            local messageArgs = e:getParameter("messageArgs")
                            if messageArgs[1] then
                                for k,v in next, messageArgs[1] do
                                    if k ~= 1 then
                                        musicStr = musicStr..", "
                                    end
                                    if #v <= 0 then
                                        musicStr = musicStr.."<blank string>"
                                    else
                                        musicStr = musicStr..v
                                    end
                                end
                            else
                                musicStr = "nil"
                            end
                            text = text..string.format("\nMusic: %s",musicStr)
                        elseif messageType == "warp" then
                            local targetStr = ""
                            local messageArgs = e:getParameter("messageArgs")
                            if messageArgs[1] then
                                targetStr = messageArgs[1]
                            else
                                targetStr = "nil"
                            end
                            text = text..string.format("\nTarget: %s",targetStr)
                        end
                    elseif kind == "coordinator" then
                        local behavior = e:getParameter("behavior")
                        if behavior then
                            text = text..string.format("\nBehavior: %s", behavior)
                        end
                    end
                end
                if verbose then
                    if humanoidTypes[etype] then
                        text = text..string.format("\nSpecies: %s", e:species())
                        text = text..string.format("\nGender: %s", e:gender())
                    end
                    if etype == "player" then
                        text = text..string.format("\nMoney: %d", e:currency("money"))
                    end
                    if actorTypes[etype] then
                        if e:isResource("health") then
                            text = text..string.format("\nHealth: %.1f/%.1f", e:resource("health"), e:resourceMax("health"))
                        end
                        if e:isResource("energy") then
                            text = text..string.format("\nEnergy: %.1f/%.1f", e:resource("energy"), e:resourceMax("energy"))
                        end
                        text = text..string.format("\nPowMul: %.1f", e:stat("powerMultiplier"))
                        strokePoly(poly.translate(poly.rotate(e:collisionPoly(),e:rotation()),rel),closestIndicated.colour,scale,"Overlay+32001")
                    end
                    if collisionTypes[etype] then
                        for i=e:movingCollisionCount()-1,0,-1 do
                            local coll = e:movingCollision(i)
                            if coll then
                                local relpos = world.distance(coll.position,mcontroller.position())
                                strokePoly(poly.translate(coll.collision,relpos),closestIndicated.colour,scale,"Overlay+32001")
                            end
                        end
                    end
                end
                local cid = connectionId(other)
                text = text..string.format("\nMaster: %s (%d)",noDirectives(connectionName(cid)),cid)
                if etype == "stagehand" or verbose then
                    drawBox(rect.translate(e:metaBoundBox(),rel),closestIndicated.colour,scale,"Overlay+32001")
                end
            elseif othertype == "player" then
                -- likely a tracked player
                text = text..string.format("\nName: %s", noDirectives(other.name))
                if other.old then
                    text = text.."\nOld"
                end
                if verbose and not other.exists then
                    if not other.lastSeen then
                        text = text.."\nLast seen: Unknown"
                    else
                        text = text..string.format("\nLast seen: %s ago",printTime(os.time()-other.lastSeen))
                    end
                end
            elseif othertype == "commonUniqueEntity" then
                text = text.."\n"..other.name
                if verbose then
                    text = text.."\nUUID: "..other.uuid
                end
            elseif othertype == "blip" then
                text = text..string.format("\n %s (%d)",noDirectives(connectionName(other)),other)
            elseif othertype == "generic" then
                text = text.."\n"..other
            elseif radarExtraDescribe[othertype] then
                text = text.."\n"..radarExtraDescribe[othertype](other,colour)
            end
        elseif renderingPlayerList then
            -- TODO: this is too much repeated stuff
            -- multiple players
            text = string.format("%d players",numPlayers)
            local totalPos = {0,0}
            size = 1
            colour = {0,255,255,255}
            for k,v in next, hoveredIndications do
                if (v.othertype == "entity" and world.entityType(v.other) == "player") or (v.othertype == "player" and v.other.exists) then
                    local dis = world.magnitude(v.pos,distanceReferencePosition())
                    totalPos = vec2.add(totalPos,v.relPos)
                    if v.othertype == "entity" then
                        text = text..string.format("\n%s (%.1f)",noDirectives(maybePlayerAlias(v.other)),dis)
                    elseif v.othertype == "player" then
                        text = text..string.format("\n%s (%.1f)",noDirectives(v.other.name),dis)
                    end
                end
            end
            closestRelPos = vec2.div(totalPos,numPlayers)
        elseif renderingOldPlayerList then
            -- multiple players
            text = string.format("%d old players",numOldPlayers)
            local totalPos = {0,0}
            size = 1
            colour = hoveredIndications[1].colour
            for k,v in next, hoveredIndications do
                if v.othertype == "player" and not v.other.exists then
                    local dis = world.magnitude(v.pos,distanceReferencePosition())
                    totalPos = vec2.add(totalPos,v.relPos)
                    text = text..string.format("\n%s (%.1f)",noDirectives(v.other.name),dis)
                end
            end
            closestRelPos = vec2.div(totalPos,numOldPlayers)
        elseif renderingInterestList then
            -- multiple interests
            text = string.format("%d interests",numInterests)
            local totalPos = {0,0}
            local totalColour = {0,0,0}
            size = 2
            for k,v in next, hoveredIndications do
                if v.othertype == "interest" then
                    local dis = world.magnitude(v.pos,distanceReferencePosition())
                    totalPos = vec2.add(totalPos,v.relPos)
                    text = text..string.format("\n%s (%.1f)",v.other,dis)
                    totalColour = vec3.add(totalColour,v.colour)
                end
            end
            local colourMult = math.min(255/math.max(totalColour[1],totalColour[2],totalColour[3]),1)
            closestRelPos = vec2.div(totalPos,numInterests)
            colour = {totalColour[1]*colourMult,totalColour[2]*colourMult,totalColour[3]*colourMult,255}
        end
        text = string.upper(text)
        -- simple text renderer
        local charWidth = 0.875
        local charHeight = 1.125
        
        local textWidth = 0
        local textHeight = 0
        local textByLine = {}
        for v in string.gmatch(text,"([^\n]+)") do
            if #v > textWidth then
                textWidth = #v
            end
            table.insert(textByLine,v)
        end
        textHeight = #textByLine
        local textWorldHeight = textHeight*charHeight
        local textWorldWidth = textWidth*charWidth
        local textPos = {closestRelPos[1]+size,closestRelPos[2]-size}
        if textPos[2]-textWorldHeight < relWindow[2]+2 then
            textPos[2] = closestRelPos[2]+size+textWorldHeight
        end
        if textPos[1] < relWindow[1]+2 then
            textPos[1] = relWindow[1]+2
        elseif textPos[1]+textWorldWidth > relWindow[3]-2 then
            textPos[1] = relWindow[3]-2-textWorldWidth
        end
        textPos = vec2.add(textPos,cameraOffset)
        local yoff = charHeight/-2
        for k,v in next, textByLine do
            local xoff = charWidth/2
            for c in string.gmatch(v,".") do
                -- draw a character
                if font[c] ~= "space" then
                    local image = font[c]
                    if not image then
                        unknownCharSet[c] = true
                        image = "/ab_font/unknown.png"
                    end
                    local drawable = {
                        image=image,
                        fullbright=true,
                        color=colour,
                        position={textPos[1]+xoff,textPos[2]+yoff}
                    }
                    localAnimator.addDrawable(drawable, "Overlay+32002")
                end
                xoff = xoff + charWidth
            end
            yoff = yoff - charHeight
        end
    end
end
