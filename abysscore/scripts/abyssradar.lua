require "/scripts/terra_vec2ref.lua"
require "/scripts/terra_renderutil.lua"
require "/scripts/abyssrenderutil.lua"
require "/scripts/terra_proxy.lua"
require "/scripts/rect.lua"

local interests = {}
local font
local playerPositionPromises = {}
local serverPlayerPositions = {}

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
function radarPlayerPositions(positions)
    for k,v in next, positions do
        if type(v) ~= "table" then
            sb.logWarn("Broken player position detected!")
            return
        end
        v[3] = 255
        table.insert(serverPlayerPositions, v)
    end
end
local function getLocalAnimator()
    if not localAnimator then
        localAnimator = terra_proxy.setupProxy("localAnimator",entity.id())
    end
    return localAnimator or getmetatable''.localAnimator
end
local lastHadPlayer = os.clock()
local function playerDetected()
    if os.clock()-lastHadPlayer > 2 then
        local localAnimator = getLocalAnimator()
        if not localAnimator then
            return
        end
        localAnimator.playAudio(root.getConfiguration("abyss_radarPingSound") or "/sfx/interface/ship_confirm2.ogg", 0, root.getConfiguration("abyss_radarPingSoundVol") or 2)
    end
    lastHadPlayer = os.clock()
end
local colours = {
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
function newInterestColour()
    local interestN = 0
    for k,v in next, interests do
        interestN = interestN + 1
    end
    local n = #colours
    local i = ((interestN-1)%n)+1
    return colours[i]
end
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
local initialized = false
local radarFinding
local radarFindingType
local function saveInterests()
    if root.setConfiguration then
        root.setConfiguration("abyss_radarInterests",interests)
    else
        player.setProperty("radarInterests",interests)
    end
end
function radarInit()
    if not player then
        return
    end
    for k,v in next, root.assetJson("/scripts/abyssUniqueObjects.json") do
        if not commonUniqueEntities[k] then
            commonUniqueEntities[k] = {name=v,colour=newUniqueEColour()}
        end
    end
    initialized = true
    interests = (root.getConfiguration and root.getConfiguration("abyss_radarInterests")) or player.getProperty("radarInterests") or {}
    if root.getConfiguration then
        local pri = player.getProperty("radarInterests")
        if pri then
            for k,v in next, pri do
                interests[k] = v
            end
            player.setProperty("radarInterests",nil)
            saveInterests()
        end
    end
    message.setHandler("abyssPlayerPositions", function (...)
        -- note: could theoretically be jammed or broken
        local positions = {...}
        table.remove(positions,1)
        table.remove(positions,1)
        radarPlayerPositions(positions)
    end)
    message.setHandler("/radarInterestColour",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #split < 4 then
            return "Usage: /radarInterestColour <interest> <R> <G> <B> [A]"
        end
        local interest = interests[split[1]]
        if not interest then
            return "No interest detected with that name."
        end
        interest[4].colour = {tonumber(split[2]),tonumber(split[3]),tonumber(split[4]),split[5] and tonumber(split[5])}
        interests[split[1]] = interest
        saveInterests()
        return string.format("Recoloured interest %s",split[1])
    end)
    message.setHandler("/radarCreateInterest",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #split == 0 or #c == 0 then
            return "Usage: /radarCreateInterest <interest>"
        end
        if #split > 1 then
            return "Interest name cannot have spaces."
        end
        local exists = not not interests[c]
        local interest = mcontroller.position()
        interest[3] = player.worldId()
        interest[4] = {
            colour=newInterestColour()
        }
        interests[c] = interest
        saveInterests()
        return string.format("%s interest %s",exists and "Moved" or "Created",c)
    end)
    message.setHandler("/radarRemoveInterest",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #split == 0 or #c == 0 then
            return "Usage: /radarRemoveInterest <interest>"
        end
        if #split > 1 then
            return "Interest name cannot have spaces."
        end
        if not interests[c] then
            return "No interest detected with that name."
        end
        interests[c] = nil
        saveInterests()
        return string.format("Deleted interest %s",c)
    end)
    message.setHandler("/radarGotoInterest",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #split == 0 or #c == 0 then
            return "Usage: /radarGotoInterest <interest>"
        end
        if #split > 1 then
            return "Interest name cannot have spaces."
        end
        if not interests[c] then
            return "No interest detected with that name."
        end
        local interest = interests[c]
        if interest[3] == player.worldId() then
            mcontroller.setPosition(interest)
            mcontroller.setVelocity({0,0})
            return string.format("Teleported to interest %s",c)
        else
            player.warp(string.format("%s=%d.%d",interest[3],math.floor(interest[1]),math.floor(interest[2])))
            return string.format("Warping to interest %s",c)
        end
    end)
    message.setHandler("/radarInterestRadius",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #split < 1 or #c == 0 then
            return "Usage: /radarInterestRadius <interest> [radius]"
        end
        if #split > 2 then
            return "Interest name cannot have spaces."
        end
        local i = split[1]
        local interest = interests[i]
        if not interest then
            return "No interest detected with that name."
        end
        if split[2] then
            local n = tonumber(split[2])
            interest[4].radius = n
            saveInterests()
            return string.format("Set interest %s radius to %.1f.",i,n)
        else
            interest[4].radius = nil
            saveInterests()
            return string.format("Reset interest %s radius.",i)
        end
    end)
    message.setHandler("/radarListInterests",function(_,l)
        if not l then return "no" end
        local str = ""
        for k,v in next, interests do
            if #str ~= 0 then
                str = str..", "
            end
            str = string.format("%s^#%s;%s^reset;",str,renderutil.toHexColour(v[4].colour),k)
        end
        if #str == 0 then
            return "There are no interests to list."
        else
            return str
        end
    end)
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
        local numTrackedActive = 0
        for k,v in next, storage.radarPlayerPositions do
            numTracked = numTracked + 1
            if v.worldId == player.worldId() then
                numTrackedWorld = numTrackedWorld + 1
                if v.exists then
                    numTrackedActive = numTrackedActive + 1
                end
            end
        end
        local out = string.format("Tracked unique entities: %d (%d on world, %d active)\nServerside player positions (slightly timing dependent): %d",numTracked,numTrackedWorld,numTrackedActive,#serverPlayerPositions)
        return out
    end)
    
    storage.radarPlayerPositions = storage.radarPlayerPositions or {}
    for k,v in next, storage.radarPlayerPositions do
        if v.worldId == player.worldId() then
            v.old = true
            v.exists = false
        end
    end
    font = root.assetJson("/ab_font/font.json")
end
local function playerPosKey(v)
    return string.format("p_%s",world.entityUniqueId(v))
end
local function entityPosKey(v)
    return string.format("e_%s",world.entityUniqueId(v))
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
    dat.name = world.entityName(v)
    dat.old = false
    dat.id = v
    dat.worldId = player.worldId()
    dat.lastChecked = world.time()
    storage.radarPlayerPositions[k] = dat
end
local function updateUniqueEntity(v)
    local k = entityPosKey(v)
    local dat = storage.radarPlayerPositions[k] or {id=v,name=nil,lastChecked=0,uuid=nil,exists=true,old=false,pos={0,0},worldId=nil,type=nil}
    dat.pos = world.entityPosition(v)
    dat.type = world.entityType(v)
    dat.uuid = world.entityUniqueId(v)
    dat.enemy = dat.type ~= "vehicle" and entity.isValidTarget(v)
    dat.old = false
    dat.id = v
    dat.worldId = player.worldId()
    dat.lastChecked = world.time()
    storage.radarPlayerPositions[k] = dat
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
local interestNoteDistance = 5
function interestCheck(p)
    for k,v in next, interests do
        if v[3] == player.worldId() then
            if world.magnitude(p,v) < (v[4].radius or interestNoteDistance) then
                return true
            end
        end
    end
    return false
end
local verbose = false
function radarSetVerbose(v)
    verbose = v
end
local queryLimit = 50
local playerPositionsToRender = {}
function radar(hidden,disMult)
    if not initialized then
        --sb.logWarn("Radar was not initialized! Initializing late.")
        radarInit()
        if not initialized then
            return
        end
    end
    disMult = disMult or 1
    local queriesSent = 0
    
    local visibleLevel = 0
    -- 0 = standard, just draws lines
    -- 1 = draws coloured blobs on entity positions and the closest point on-screen to said positions, also shows information on the closest one under the mouse
    if type(hidden) == "number" then
        visibleLevel = hidden-1
        hidden = hidden == 0
    end
    -- render lines to show the locations of nearby entities and all players in the world, as well as mech beacons
    if os.clock() > lastPing + 3/pingTimescale then
        lastPing = os.clock()
        world.spawnMonster("punchy", mcontroller.position(), sb.jsonMerge(root.assetJson("/scripts/abyssScannerParams.json"), {ownerId=entity.id()}))
    end
    local interestNoteColourHSV = {math.cos(world.time()*5)*30+30,1,1}
    local interestNoteColour = renderutil.toRGB(interestNoteColourHSV)
    
    local window = camera and camera.worldScreenRect() or world.clientWindow()
    local relWindow1 = world.distance(rect.ll(window),mcontroller.position())
    local relWindow2 = world.distance(rect.ur(window),mcontroller.position())
    local relWindow = {relWindow1[1],relWindow1[2],relWindow2[1],relWindow2[2]}
    local scale = (window[4] - window[2])/65
    local localAnimator = getLocalAnimator()
    if not localAnimator then
        return
    end
    local function lineTowardsPos(p, c, d)
        if hidden then return end
        local angle = vec2.angle(world.distance(p, mcontroller.position()))
        local s = vec2.withAngle(angle, (3*d*disMult)*scale)
        local t = vec2.withAngle(angle, (3*d*disMult+d)*scale)
        local l = generateLineDrawable(s,t)
        l.color = c
        l.width = scale*d
        l.fullbright = true
        localAnimator.addDrawable(l, "Overlay+32002")
    end
    local function lineTowards(e, c)
        return lineTowardsPos(world.entityPosition(e),c, 1)
    end
    local raim = world.distance(tech.aimPosition(),mcontroller.position())
    local closestIndicated
    local function indicatePosition(p, c, d, o, priority)
        if visibleLevel < 1 then
            return
        end
        local rel = world.distance(p, mcontroller.position())
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
        local tm = world.magnitude(rel,raim) 
        local m = tm+(priority or 0)
        if not closestIndicated or m < closestIndicated.disval then
            closestIndicated = {
                dis=tm,
                disval=m,
                colour={c[1],c[2],c[3],255},
                size=d,
                pos=p,
                relPos=rel,
                other=o
            }
        end
        local drawable = {
            position=rel,
            color=c,
            fullbright=true,
            poly={
                {d,0},{0,d},{-d,0},{0,-d}
            }
        }
        localAnimator.addDrawable(drawable, "Overlay+32002")
    end
    local function indicateEntity(e, c, priority)
        return indicatePosition(world.entityPosition(e),c,1,e,priority)
    end
    local function indicAlpha(c)
        return {c[1],c[2],c[3],(c[4] or 255)/2}
    end
    indicatePosition(mcontroller.position(),{255,255,255,127},1,"\nSelf")
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
            indicatePosition(v.pos,indicAlpha(v.colour),2,"\n"..v.name)
        end
    end
    for k,v in next, interests do
        if v[3] == player.worldId() then
            lineTowardsPos(v,v[4].colour,2)
            indicatePosition(v,indicAlpha(v[4].colour),2,"\n"..k)
        end
    end
    
    -- TODO: rework this to be... better, really. breaks down with too many players known
    for k,v in next, storage.radarPlayerPositions do
        if world.entityExists(v.id) and world.entityUniqueId(v.id) == v.uuid then
            playerPositionsToRender[k] = nil
        else
            local promise = playerPositionPromises[k]
            if promise then
                if promise:finished() then
                    if promise:succeeded() then
                        local npos = promise:result()
                        v.pos[1] = npos[1]
                        v.pos[2] = npos[2]
                        v.exists = true
                        v.worldId = player.worldId()
                        v.old = false
                    elseif v.worldId == player.worldId() then
                        v.exists = false
                    end
                    playerPositionPromises[k] = nil
                end
            elseif queriesSent < queryLimit and (v.exists or v.lastCheckedWorld ~= player.worldId() or world.time()-v.lastChecked > 10) then
                queriesSent = queriesSent + 1
                v.lastChecked = world.time()
                v.lastCheckedWorld = player.worldId()
                playerPositionPromises[k] = world.findUniqueEntity(v.uuid)
            end
            if v.worldId == player.worldId() and (includeOld or not v.old) then
                playerPositionsToRender[k] = v
            end
        end
    end
    
    for k,v in next, playerPositionsToRender do
        local c = gonePlayerColour
        local priority = 1
        if v.exists and interestCheck(v.pos) then
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
            c = playerColour
            priority = -0.5
        end
        if v.old then
            c = {c[1]*0.5,c[2]*0.5,c[3]*0.5,c[4]}
            if not includeOld then
                playerPositionsToRender[k] = nil
            end
        end
        lineTowardsPos(v.pos, c, 1)
        indicatePosition(v.pos,indicAlpha(c),1,v,priority)
    end
    local types = {"npc","monster", "vehicle","stagehand","plantDrop"}
    if not world.players then
        table.insert(types, "player")
    end
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
    local nearbyEntities = world.entityQuery(mcontroller.position(), 300, {includedTypes=types})
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
            elseif t == "player" and interestCheck(world.entityPosition(v)) then
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
            lineTowards(v,colour)
            indicateEntity(v,indicAlpha(colour),priority)
            if t == "player" then
                playerDetected()
                updatePlayer(v)
            end
        end
    end
    if world.players then
        local nearbyPlayers = world.players()
        for k,v in next, nearbyPlayers do
            if not excludeEntity(v) then
                playerDetected()
                local priority = -0.5
                local colour = {0,255,255}
                if interestCheck(world.entityPosition(v)) then
                    priority = -1
                    colour = interestNoteColour
                elseif entity.isValidTarget(v) then
                    priority = -1
                    colour = {255,255,0}
                end
                lineTowards(v,colour)
                indicateEntity(v,indicAlpha(colour),priority)
                updatePlayer(v)
            end
        end
    end
    local newServerPlayerPositions = {}
    for k,v in next, serverPlayerPositions do
        local dis = world.magnitude(v, mcontroller.position())
        -- TODO: maybe check if offscreen or onscreen instead
        if world.pointCollision(v,{"Null"}) then
            local crgb
            local size = 0.5
            if interestCheck(v) then
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
            indicatePosition(v,indicAlpha(crgb),size,nil,0.5)
        end
        v[3] = v[3] - pingTimescale
        if v[3] > 0 then
            table.insert(newServerPlayerPositions, v)
        end
    end
    serverPlayerPositions = newServerPlayerPositions
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
    if visibleLevel >= 1 and closestIndicated and closestIndicated.dis < 3 then
        local other = closestIndicated.other
        local text = string.format("%.1f",world.magnitude(closestIndicated.pos,mcontroller.position()))
        if type(other) == "number" then
            -- likely an entity, show info about entity
            local e = world.entity(other)
            local etype = e:type()
            text = text..string.format("\nType: %s", etype)
            if not namelessTypes[etype] then
                text = text..string.format("\nName: %s", noDirectives(e:name()))
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
                end
            end
            if other < 0 and etype ~= "player" then
                text = text.."\nClient Master"
            elseif other >= 0 and etype == "player" then
                text = text.."\nServer Master"
            end
        elseif type(other) == "table" then
            -- likely a tracked unique entity
            text = text..string.format("\nName: %s", noDirectives(other.name))
            if other.old then
                text = text.."\nOld"
            end
        elseif type(other) == "string" then
            text = text..other
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
        local closestRelPos = closestIndicated.relPos
        local textPos = {closestRelPos[1]+closestIndicated.size,closestRelPos[2]-closestIndicated.size}
        if textPos[2]-textWorldHeight < relWindow[2]+2 then
            textPos[2] = closestRelPos[2]+closestIndicated.size+textWorldHeight
        end
        if textPos[1] < relWindow[1]+2 then
            textPos[1] = relWindow[1]+2
        elseif textPos[1]+textWorldWidth > relWindow[3]-2 then
            textPos[1] = relWindow[3]-2-textWorldWidth
        end
        local yoff = charHeight/-2
        for k,v in next, textByLine do
            local xoff = charWidth/2
            for c in string.gmatch(v,".") do
                -- draw a character
                if font[c] ~= "space" then
                    local image = font[c] or "/ab_font/unknown.png"
                    local drawable = {
                        image=image,
                        fullbright=true,
                        color=closestIndicated.colour,
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
