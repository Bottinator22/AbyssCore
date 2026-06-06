local pingTestPlayers
local utilThread
local genericTimer = 0
local genericTimerPromise
local heldEmote = nil
local validEmotes = {
    idle=true,
    blabbering=true,
    shouting=true,
    happy=true,
    sad=true,
    neutral=true,
    laugh=true,
    annoyed=true,
    oh=true,
    oooh=true,
    blink=true,
    wink=true,
    eat=true,
    sleep=true
}

local spawnableMinionTypes = {
    ranged="^#ff0000;",
    melee="^#7f00ff;",
    heal="^#00ff00;",
    bomb="^#ffff00;",
    ranged2="^#007fff;",
    analysis="^#00ffff;",
    shield="^#ff00ff;",
}

local lastFacing
local lastConfigKey
function updateConfigAndFlip()
    local configKey = player.getProperty("abyss_configKey")
    local facing = (player.facingDirection or mcontroller.facingDirection)()
    if configKey and (configKey ~= lastConfigKey or lastFacing ~= facing) then
        local cfg = player.getProperty(configKey)
        local identityOverride = nil
        if cfg then
            if facing < 0 then
                identityOverride = cfg.flip
            else
                identityOverride = cfg.base
            end
            if cfg.both then
                if identityOverride then
                    identityOverride = sb.jsonMerge(cfg.both,identityOverride)
                else
                    identityOverride = cfg.both
                end
            end
        end
        if identityOverride then
            player.setHumanoidIdentity(sb.jsonMerge(player.humanoidIdentity(),identityOverride))
        end
    end
    lastConfigKey = configKey
    lastFacing = facing
end

function init()
    utilThread = threads.create({
        name="abyss_utilThread",
        scripts={
            timer={"/scripts/terra_threads/timer.lua"}
        },
        tickRate=240,
        logMapped=false,
        instructionLimit=1000000000,
    })
    storage.abyssSpawns = storage.abyssSpawns or {}
    -- some utility commands
    message.setHandler("/abyssplush", function(_,isLocal)
        if not isLocal then return end
        player.giveItem(root.assetJson("/abyssplush.json"))
    end)
    
    message.setHandler("/nickfromname", function(_,isLocal)
        if not isLocal then return end
        chat.command(string.format("/nick %s",player.name()))
    end)
    
    message.setHandler("/back", function(_,isLocal)
        if not isLocal then return end
        player.warp("Return")
        return "Warping back."
    end)
    
    message.setHandler("abyss_getGenericTime", function(_,isLocal)
        if not isLocal then return end
        if not genericTimerPromise then return 0 end
        return genericTimerPromise:result() or genericTimer
    end)
    
    message.setHandler("/warpship", function(_,isLocal)
        if not isLocal then return end
        player.warp("OwnShip")
        return "Warping to ship."
    end)
    message.setHandler("/warporbited", function(_,isLocal)
        if not isLocal then return end
        player.warp("OrbitedWorld")
        return "Warping to orbited world."
    end)
    message.setHandler("/testping", function(_,isLocal)
        if not isLocal then return end
        pingTestPlayers = {}
        for _,v in next, world.entityQuery({0,0},world.size(),{sort="random"}) do
            if v > 0 then
                table.insert(pingTestPlayers,{
                    name="Server",
                    promise=world.sendEntityMessage(v,"abyss_pingTest"),
                    timerPromise=nil,
                    timer=0
                })
                break
            end
        end
        for k,v in next, world.players() do
            if v ~= player.id() then
                table.insert(pingTestPlayers,{
                    name=world.entityName(v),
                    promise=world.sendEntityMessage(v,"abyss_pingTest"),
                    timerPromise=nil,
                    timer=0
                })
            end
        end
        threads.sendMessage(utilThread,"resetTimer","ping")
    end)
    
    message.setHandler("/abyssBossbar", function(_,isLocal)
        if not isLocal then return "no" end
        if not storage.bossbarId or not world.entityExists(storage.bossbarId) then
            local params = sb.jsonMerge(root.assetJson("/scripts/abyssBasicParams.json"), root.assetJson("/scripts/abyssBossbarParams.json"))
            params = sb.jsonMerge(params, {ownerId=entity.id(),noKeepAlive=false,slavePerc=false,uuid=entity.uniqueId()})
            storage.bossbarId = world.spawnMonster("mechmultidrone", mcontroller.position(), params)
        end
        local bar = world.callScriptedEntity(storage.bossbarId,"toggleDamageBar")
        if bar == "Special" then
            return "Enabled damage bar."
        elseif bar == "None" then
            world.callScriptedEntity(storage.bossbarId,"kill")
            return "Disabled damage bar."
        else
            storage.bossbarId = nil
            return "Bossbar likely invalid! Resetting."
        end
    end)
    message.setHandler("/abyssEmote", function(_,l,c) 
        if not l then
            return "Unauthorized"
        end
        if #c <= 0 then
            heldEmote = nil
            return "Reset emote."
        end
        if validEmotes[string.lower(c)] then
            heldEmote = string.lower(c)
            return string.format("Now holding emote %s.",heldEmote)
        else
            return "Invalid emote. Valid emotes are...\nidle, blabbering, shouting, happy, sad, neutral, laugh, annoyed, oh, oooh, blink, wink, eat, sleep"
        end
    end)
    message.setHandler("/abyssMinion", function(_,l,c) 
        if not l then
            return "Unauthorized"
        end
        if #c <= 0 then
            return "Usage: /abyssMinion <type>"
        end
        local n = string.lower(c)
        if spawnableMinionTypes[n] then
            local params = sb.jsonMerge(root.assetJson("/scripts/abyssBasicParams.json"), root.assetJson("/scripts/abyssminion/abyssMinionParams.json"))
            params = sb.jsonMerge(params, {ownerId=player.id(), coreId=player.id(), minionType=n, incMaxOnKill=false,enableRedirect=false})
            local minionId = world.spawnMonster("mechmultidrone", mcontroller.position(), params)
            table.insert(storage.abyssSpawns, minionId)
            return string.format("Spawned a minion of type %s%s^reset;.",spawnableMinionTypes[n],n)
        else
            local str = "Invalid minion type. Valid minion types to spawn are "
            for k,v in next, spawnableMinionTypes do
                str = str..v..k.."^reset;, "
            end
            return string.sub(str,0,-3).."."
        end
    end)
    message.setHandler("/abyssPersonality", function(_,l,c) 
        if not l then
            return "Unauthorized"
        end
        if #c <= 0 or not tonumber(c) then
            return "Usage: /abyssPersonality <personality index>."
        end
        local personalities = root.assetJson("/humanoid.config:personalities")
        local n = tonumber(c)
        local p = personalities[n]
        if p then
            player.setPersonality({
                idle=p[1],
                armIdle=p[2],
                headOffset=p[3],
                armOffset=p[4]
            })
            return "Set personality."
        else
            return "Invalid personality index"
        end
    end)
    message.setHandler("/abyssConfigKey", function(_,l,c) 
        if not l then
            return "Unauthorized"
        end
        if player.getProperty("abyss_configKey") and player.getProperty("abyss_origIdentity") then
            player.setHumanoidIdentity(sb.jsonMerge(player.humanoidIdentity(),player.getProperty("abyss_origIdentity")))
        end
        if #c <= 0 then
            player.setProperty("abyss_configKey",nil)
            world.sendEntityMessage(player.id(),"abyssbasic_updateLight")
            return "Reset config key."
        end
        if not player.getProperty("abyss_configKey") then
            player.setProperty("abyss_origIdentity",player.humanoidIdentity())
        end
        player.setProperty("abyss_configKey",c)
        world.sendEntityMessage(player.id(),"abyssbasic_updateLight")
        local newName = player.getProperty(c,{}).name
        if newName then
            player.setName(newName)
        end
        if player.getProperty(c) then
            return string.format("Set config key to '%s'.",c)
        else
            return string.format("Set config key to '%s'. Nothing defined at this key.",c)
        end
    end)
    
    local function validateUuid(uid)
        local n = 0
        for c in string.gmatch(uid,".") do
            local cn = tonumber(c,16)
            if cn then
                n = n + 1
            end
        end
        return n == 32 or n == 33
    end
    local function parameterlessWarp(split)
        return true
    end
    local function uidWarp(split)
        return validateUuid(split[2])
    end
    local function isInt(n)
        return math.floor(n) ~= n
    end
    local function validateIntStr(nstr)
        -- TODO: lexical casts throw on certain weird cases
        local n = tonumber(nstr)
        if not n then return false end
        if isInt(n) then return false end
        return true
    end
    local warpTypes = {
        ["return"]=parameterlessWarp,
        nowhere=parameterlessWarp,
        ownship=parameterlessWarp,
        orbitedworld=parameterlessWarp,
        player=uidWarp,
        clientshipworld=uidWarp,
        celestialworld=function(split)
            if #split < 5 then
                return false
            end
            for k,v in next, split do
                if k > 1 then
                    if not validateIntStr(v) then
                        return false
                    end
                    if k > 4 then
                        local n = tonumber(v)
                        if n < 1 then
                            return false
                        end
                    end
                end
            end
            return true
        end,
        instanceworld=function(split)
            if split[3] and #split[3] > 0 and split[3] ~= "-" then
                if not validateUuid(split[3]) then
                    return false
                end
            end
            if split[4] and #split[4] > 0 and split[4] ~= "-" then
                local n = tonumber(split[4])
                if not n or n < 0 then
                    return false
                end
            end
            if split[5] then
                return false
            end
            return true
        end
    }
    message.setHandler("/abysswarp", function(_,isLocal,c)
        if not isLocal then return end
        -- validates anything that would normally result in a kick
        local main
        local coordsStr
        -- separate and validate coordinates
        for v in string.gmatch(c,"([^=]*)") do
            if not main then
                main = v
            elseif not coordsStr then
                coordsStr = v
                break;
            end
        end
        if coordsStr then
            local split = {}
            for v in string.gmatch(coordsStr,"([^.]*)") do
                table.insert(split,v)
            end
            if split[2] then
                if not validateIntStr(split[1]) or not validateIntStr(split[2]) then
                    return "Malformed warp coordinates."
                else -- TODO: accurately check if the game will try to parse this as an int.
                end
            end
        end
        local split = {}
        for v in string.gmatch(main,"([^:]*)") do
            table.insert(split, v)
        end
        local wt = string.lower(split[1])
        if warpTypes[wt] then
            if warpTypes[wt](split) then
                player.warp(c)
                return "Warping."
            else
                return "Warp is malformed."
            end
        else
            return "Invalid warp type."
        end
    end)
    local function buildHeadPlatform()
        local params = root.assetJson("/scripts/abyssheadplatform/abyssHeadPlatformParams.json")
        params.physicsCollisions.platform.collision = mcontroller.baseParameters().standingPoly
        params.physicsCollisions.platform_duck.collision = mcontroller.baseParameters().crouchingPoly
        params.ownerId = player.id()
        return world.spawnVehicle("compositerailplatform",mcontroller.position(),params)
    end
    message.setHandler("/headplatform", function(_,isLocal)
        if not isLocal then return end
        if storage.headPlatform and world.entityExists(storage.headPlatform) then
            world.callScriptedEntity(storage.headPlatform,"vehicle.destroy")
            return "Destroying head platform."
        else
            storage.headPlatform = buildHeadPlatform()
            return "Creating head platform."
        end
    end)
    message.setHandler("/camfocus",function(_,l)
        if not l then return end
        player.setCameraFocusEntity(world.entityQuery(player.aimPosition(),1)[1])
    end)
    local ouchOverride = player.getProperty("abyss_ouchOverride")
    if ouchOverride then
        if ouchOverride == "null" then
            status.setStatusProperty("ouchNoise",nil)
        else
            status.setStatusProperty("ouchNoise",ouchOverride)
        end
    end
    if storage.headPlatform and (not world.entityExists(storage.headPlatform) or not world.callScriptedEntity(storage.headPlatform,"isAbyssHeadplatform")) then
        -- replace it
        storage.headPlatform = buildHeadPlatform()
    end
end
function update(dt)
    if storage.headPlatform and world.entityExists(storage.headPlatform) then -- player.headRotation was added in same commit as postUpdate
        if not player.headRotation then
            world.callScriptedEntity(storage.headPlatform,"updatePos")
        end
        world.callScriptedEntity(storage.headPlatform,"keepAlive")
    end
    if genericTimerPromise then
        genericTimer = genericTimerPromise:result() or genericTimer
    end
    genericTimerPromise = threads.sendMessage(utilThread,"getTimer","generic")
    if pingTestPlayers then
        local done = true
        local timerPromisePresent = false
        for k,v in next, pingTestPlayers do
            if not v.promise:finished() then
                v.timer = v.timer + 1
                done = false
            elseif not v.timerPromise then
                v.timerPromise = threads.sendMessage(utilThread,"getTimer","ping")
                timerPromisePresent = true
            end
        end
        -- wait for timer thread to output; this promise can resolve within a frame's time
        if timerPromisePresent then
            while timerPromisePresent do
                timerPromisePresent = false
                for k,v in next, pingTestPlayers do
                    if v.timerPromise and not v.timerPromise:finished() then
                        timerPromisePresent = true
                        break
                    end
                end
            end
        end
        if done then
            local str = "Ping test results (ping of others to you):"
            for k,v in next, pingTestPlayers do
                str = string.format("%s\n%s: %dt, ~%.0fms",str,v.name,v.timer,v.timerPromise:result()*1000)
            end
            chat.addMessage(str)
            pingTestPlayers = nil
        end
    end
    if heldEmote then
        player.emote(heldEmote)
    end
    if #storage.abyssSpawns > 0 then
        local new = {}
        for k,v in next, storage.abyssSpawns do
            if world.entityExists(v) then
                world.callScriptedEntity(v, "equips")
                table.insert(new, v)
            end
        end
        storage.abyssSpawns = new
    end
    if not player.facingDirection then
        updateConfigAndFlip()
    end
    if storage.bossbarId and world.entityExists(storage.bossbarId) then
        world.callScriptedEntity(storage.bossbarId,"keepAlive")
    end
end
function postUpdate()
    if storage.headPlatform and world.entityExists(storage.headPlatform) then
        world.callScriptedEntity(storage.headPlatform,"updatePos",mcontroller.rotation(),mcontroller.crouching())
    end
    updateConfigAndFlip()
    local invulnMode = player.getProperty("abyss_invulnerable")
    if invulnMode then
        if invulnMode == "god" then
            status.setResourcePercentage("health",1)
        elseif status.resource("health") <= 0 then
            -- set health to a really small number that's still greater than 0
            status.setResource("health",(1/2)^126)
        end
    end
    if status.resource("health") <= 0 then
        world.sendEntityMessage(player.id(),"abyss_dead")
    end
end
