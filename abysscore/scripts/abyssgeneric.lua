local pingTestPlayers
local utilThread
function init()
    utilThread = threads.create({
        name="abyss_utilThread",
        scripts={
            timer={"/scripts/terra_threads/timer.lua"}
        },
        tickRate=240,
        instructionLimit=1000000000,
    })
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
        threads.sendMessage(utilThread,"resetTimer")
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
    if pingTestPlayers then
        local done = true
        local timerPromisePresent = false
        for k,v in next, pingTestPlayers do
            if not v.promise:finished() then
                v.timer = v.timer + 1
                done = false
            elseif not v.timerPromise then
                v.timerPromise = threads.sendMessage(utilThread,"getTimer")
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
end
function postUpdate()
    if storage.headPlatform and world.entityExists(storage.headPlatform) then
        world.callScriptedEntity(storage.headPlatform,"updatePos",mcontroller.rotation(),mcontroller.crouching())
    end
    if player.getProperty("abyss_configKey") then
        world.sendEntityMessage(player.id(),"abyss_updateFlip")
    end
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
