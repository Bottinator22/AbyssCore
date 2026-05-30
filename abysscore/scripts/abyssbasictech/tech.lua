require "/scripts/terra_vec2ref.lua"
require "/scripts/util.lua"
require "/scripts/poly.lua"
require "/scripts/rect.lua"
require "/scripts/abysscommand.lua"
require "/scripts/abyssradar.lua"
require "/scripts/terra_proxy.lua"

player = nil
local workVec21 = {0,0}
local workVec22 = {0,0}
local workVec23 = {0,0}
local workVec24 = {0,0}
local workVec25 = {0,0}
localAnimator = nil
local radarMode = 1
local commandMode = false

local parentState

local lockedPosition
local lockedPositionEntity

local layMode = false
local layTogglesSit = false
local sitMode = false
local duckMode = false
local walkMode = false
local lastCommand = false
local ignoreSpecial = false
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
local explodeTimer
local function imagePath(i)
    return string.match(i,"([^?]*)")
end
local function pathFName(p)
    local out = ""
    for v in string.gmatch(p,"([^/]*)") do
        out = v
    end
    return out
end
function getActiveEmote()
    local portrait = world.entityPortrait(entity.id(),"head")
    for k,v in next, portrait do
        local fname = pathFName(imagePath(v.image))
        if string.match(fname,"([^:]*)") == "emote.png" then
            return string.sub(fname,string.find(fname,":")+1,#fname)
        end
    end
end

function setParentState(n)
    parentState = n
    tech.setParentState(n)
end
function setLockedPosition(p)
    if lockedPositionEntity and lockedPositionEntity:exists() then
        lockedPosition = world.distance(p,lockedPositionEntity:position())
    else
        lockedPosition = p
    end
end
local spawnableMinionTypes = {
    ranged="^#ff0000;",
    melee="^#7f00ff;",
    heal="^#00ff00;",
    bomb="^#ffff00;",
    ranged2="^#007fff;",
    analysis="^#00ffff;",
    shield="^#ff00ff;",
}
function playSound(pool)
    world.spawnProjectile("invisibleprojectile",mcontroller.position(),entity.id(),{1,0},true,{
        timeToLive=0.1,
        power=0,
        damageTeam = { type = "ghostly" },
        damageKind = NoDamage,
        periodicActions = {
            {
                time=0,
                ["repeat"]=false,
                action = "sound",
                options = pool
            }
        }
    })
end

function init()
    if not input then
        return
    end
    storage.abyssSpawns = storage.abyssSpawns or {}
    message.setHandler("abyss_parentState",function(_,l)
        if not l then return "nuh uh" end
        return parentState
    end)
    message.setHandler("abyss_updateFlip",function(_,l)
        if not l then return "nuh uh" end
        updateConfigAndFlip()
    end)
    message.setHandler("/minion", function(_,l,c) 
        if not l then
            return "Unauthorized"
        end
        if #c <= 0 then
            return "Usage: /minion <type>"
        end
        local n = string.lower(c)
        if spawnableMinionTypes[n] then
            local params = sb.jsonMerge(root.assetJson("/scripts/abyssBasicParams.json"), root.assetJson("/scripts/abyssminion/abyssMinionParams.json"))
            params = sb.jsonMerge(params, {ownerId=entity.id(), coreId=entity.id(), minionType=n, incMaxOnKill=false,enableRedirect=false})
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
    message.setHandler("/deploy", function(_,l) 
        if not l then
            return "Unauthorized"
        end
        world.sendEntityMessage(entity.id(), "deployMech")
    end)
    message.setHandler("/antinude",function(_,l)
        if not l then return "no" end
        if #status.getPersistentEffects("noNude") > 0 then
            status.clearPersistentEffects("noNude")
            return "No longer blocking nude."
        else
            status.setPersistentEffects("noNude",{{stat="nude",effectiveMultiplier=0}})
            return "Now blocking nude."
        end
    end)
    message.setHandler("/antifalldamage",function(_,l)
        if not l then return "no" end
        if #status.getPersistentEffects("noFallDamage") > 0 then
            status.clearPersistentEffects("noFallDamage")
            return "No longer blocking fall damage."
        else
            status.setPersistentEffects("noFallDamage",{{stat="fallDamageMultiplier",effectiveMultiplier=0}})
            return "Now blocking fall damage."
        end
    end)
    message.setHandler("/antilava",function(_,l)
        if not l then return "no" end
        if #status.getPersistentEffects("noLava") > 0 then
            status.clearPersistentEffects("noLava")
            return "No longer blocking lava."
        else
            status.setPersistentEffects("noLava",{{stat="lavaImmunity",amount=1}})
            return "Now blocking lava."
        end
    end)
    message.setHandler("/antistatus",function(_,l)
        if not l then return "no" end
        if #status.getPersistentEffects("noStatus") > 0 then
            status.clearPersistentEffects("noStatus")
            return "No longer blocking all status effects."
        else
            status.setPersistentEffects("noStatus",{{stat="statusImmunity",amount=1}})
            return "Now blocking all status effects."
        end
    end)
    message.setHandler("/sit",function(_,l)
        if not l then return "no" end
        sitMode = not sitMode
        layMode = false
        if sitMode then
            setParentState("sit")
        else
            setParentState()
        end
    end)
    message.setHandler("/lay",function(_,l)
        if not l then return "no" end
        layMode = not layMode
        sitMode = layMode
        if layMode then
            setParentState("lay")
        else
            setParentState()
        end
    end)
    message.setHandler("/lockPos",function(_,l)
        if not l then return "no" end
        if lockedPosition then
            lockedPosition = nil
            lockedPositionEntity = nil
            return "Position no longer locked."
        else
            lockedPosition = mcontroller.position()
            return "Position now locked."
        end
    end)
    message.setHandler("/attach",function(_,l)
        if not l then return "no" end
        if lockedPositionEntity then
            lockedPosition = nil
            lockedPositionEntity = nil
            return "Position no longer locked to entity."
        else
            local e = world.entityQuery(tech.aimPosition(),1,{order="nearest"})[1]
            if e then
                lockedPositionEntity = world.entity(e)
            else
                return "Can't find an entity to lock to."
            end
            setLockedPosition(mcontroller.position())
            return "Position now locked to entity."
        end
    end)
    message.setHandler("/rot",function(_,l,c)
        if not l then return "no" end
        if #c <= 0 or not tonumber(c) then
            mcontroller.setRotation(0)
            return "Reset rotation."
        else
            local a = tonumber(c)/180*math.pi
            mcontroller.setRotation(a)
        end
    end)
    message.setHandler("/duck",function(_,l)
        if not l then return "no" end
        duckMode = not duckMode
    end)
    message.setHandler("/walk",function(_,l)
        if not l then return "no" end
        walkMode = not walkMode
    end)
    message.setHandler("/bossbar", function(_,isLocal)
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
    message.setHandler("/emote", function(_,l,c) 
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
    message.setHandler("/personality", function(_,l,c) 
        if not l then
            return "Unauthorized"
        end
        if #c <= 0 or not tonumber(c) then
            return "Usage: /personality <personality index>."
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
    message.setHandler("/setGlow", function(_,l,c) 
        if not l then
            return "Unauthorized"
        end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            local n = tonumber(v)
            if not n then
                return string.format("'%s' is not a number",v)
            end
            table.insert(split, n)
        end
        local k = player.getProperty("abyss_configKey")
        if k then
            local cfg = player.getProperty(k) or {}
            if #split < 3 then
                cfg.lightColour = nil
                animator.setLightColor("glow",player.getProperty("abyss_lightColour",{0,0,0}))
                return "Reset glow. (Using base light colour as default!)"
            end
            cfg.lightColour = split
            player.setProperty(k,cfg)
            animator.setLightColor("glow",split)
            return "Set glow."
        else
            if #split < 3 then
                player.setProperty("abyss_lightColour",{0,0,0})
                animator.setLightColor("glow",{0,0,0})
                return "Reset glow."
            end
            player.setProperty("abyss_lightColour",split)
            animator.setLightColor("glow",split)
            return "Set glow."
        end
    end)
    message.setHandler("/configKey", function(_,l,c) 
        if not l then
            return "Unauthorized"
        end
        if player.getProperty("abyss_configKey") and player.getProperty("abyss_origIdentity") then
            player.setHumanoidIdentity(sb.jsonMerge(player.humanoidIdentity(),player.getProperty("abyss_origIdentity")))
        end
        if #c <= 0 then
            player.setProperty("abyss_configKey",nil)
            animator.setLightColor("glow",player.getProperty("abyss_lightColour",{0,0,0}))
            return "Reset config key."
        end
        if not player.getProperty("abyss_configKey") then
            player.setProperty("abyss_origIdentity",player.humanoidIdentity())
        end
        player.setProperty("abyss_configKey",c)
        animator.setLightColor("glow",player.getProperty(c,{}).lightColour or player.getProperty("abyss_lightColour",{0,0,0}))
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
    message.setHandler("/explode",function(_,l)
        if not l then return "no" end
        if explodeTimer then
            explodeTimer = nil
            tech.setParentDirectives()
            return "Un-exploding."
        else
            playSound({"/sfx/tech/mech_explosion_windup.ogg"})
            explodeTimer = 0.5
            return "Exploding."
        end
    end)
    -- TODO: clothing 'covered region' checks, to dynamically dim the light based on visible clothing
    animator.setParticleEmitterActive("sparkles",false)
    local k = player.getProperty("abyss_configKey")
    if k then
        local cfg = player.getProperty(k,{})
        animator.setLightColor("glow",cfg.lightColour or player.getProperty("abyss_lightColour",{0,0,0}))
    else
        animator.setLightColor("glow",player.getProperty("abyss_lightColour",{0,0,0}))
    end
    ignoreSpecial = config.getParameter("ignoreSpecial",false)
    if not player then
        player = terra_proxy.setupProxy("player",entity.id())
    end
    status.setPersistentEffects("abyssSimpleStats", {})
    radarInit()
    mcontroller.setAutoClearControls(true)
end

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
local lastSpecial3 = false
local lastTele = false

function update(args)
    if not localAnimator then
        localAnimator = terra_proxy.setupProxy("localAnimator",entity.id())
    end
    if not localAnimator then
        return
    end
    if not player then
        player = terra_proxy.setupProxy("player",entity.id())
    end
    if not player then
        return
    end
    if duckMode then
        mcontroller.controlCrouch()
    end
    if walkMode then
        mcontroller.controlModifiers({
            runningSuppressed=true
        })
    end
    if heldEmote then
        player.emote(heldEmote)
    end
    updateConfigAndFlip()
    if input then
        if input.bindHeld("abysscore","blink") and not lastTele then
            if lockedPosition then
                setLockedPosition(tech.aimPosition())
            end
            mcontroller.setPosition(tech.aimPosition())
            mcontroller.setVelocity({0,0})
        end
        lastTele = input.bindHeld("abysscore","blink")
        if input.bindHeld("abysscore","face") then
            local dis = world.distance(mcontroller.position(),tech.aimPosition())
            if dis[1] > 0 then
                mcontroller.controlFace(-1)
            else
                mcontroller.controlFace(1)
            end
        end
    end
    if ignoreSpecial then
        args.moves.special1 = false
        args.moves.special3 = false
    end
    local commandBind = args.moves.special1 or (input and input.bindHeld("abysscore","toggleCommand"))
    local radarBind = args.moves.special3 or (input and input.bindHeld("abysscore","toggleRadar"))
    if commandBind ~= lastCommand then
        lastCommand = commandBind
        if commandBind then
            if args.moves.run then
                commandMode = not commandMode
                if commandMode then
                    command.init()
                else
                    command.uninit()
                end
            else
                command.togglePause()
            end
        end
    end
    tech.setToolUsageSuppressed(commandMode)
    if commandMode then
        command.update(args)
    else
        if radarBind and not lastRadarBind then
            radarMode = radarMode + 1
            if radarMode > 2 then
                radarMode = 0
            end
        end
    end
    lastRadarBind = radarBind
    radarSetVerbose(not args.moves.run)
    radar(radarMode)
    
    if sitMode then
        mcontroller.controlParameters({
            gravityEnabled=false,
            collisionEnabled=false
        })
        
        local flyVelocity = {0, 0}
        local s = 1
        if args.moves.run then s = 5 end
        if args.moves["right"] then flyVelocity[1] = s end
        if args.moves["left"] then flyVelocity[1] = -s end
        if args.moves["up"] then flyVelocity[2] = s end
        if args.moves["down"] then flyVelocity[2] = -s end
        
        mcontroller.setVelocity(flyVelocity)
        if lockedPosition then
            vec2.addToRef(lockedPosition,vec2.mul(flyVelocity,args.dt),lockedPosition)
        end
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
    if storage.bossbarId and world.entityExists(storage.bossbarId) then
        world.callScriptedEntity(storage.bossbarId,"keepAlive")
    end
    if lockedPositionEntity and not lockedPositionEntity:exists() then
        lockedPosition = nil
        lockedPositionEntity = nil
    end
    if lockedPosition then
        if lockedPositionEntity then
            mcontroller.setPosition(vec2.add(lockedPositionEntity:position(),lockedPosition))
            world.debugLine(mcontroller.position(),lockedPositionEntity:position(),"white")
        else
            mcontroller.setPosition(lockedPosition)
        end
        mcontroller.setVelocity({0,0})
    end
    
    if explodeTimer then
        local explodeDirectives = ""
        if explodeTimer > 0 then
            explodeTimer = explodeTimer - args.dt
            if explodeTimer <= 0 then
                local params = {
                    --[[damageTeam = {
                    type = "enemy",
                    team = 9001
                    }]]
                }
                world.spawnProjectile("mechexplosion", mcontroller.position(), nil, nil, false, params)
                playSound({"/sfx/tech/mech_explosion.ogg"})
                explodeDirectives = "?multiply=00000000"
                explodeTimer = -1
            else
                local fade = 1 - (explodeTimer / 0.5)
                explodeDirectives = string.format("?fade=fcc93c;%.1f", fade)
            end
        else
            explodeDirectives = "?multiply=00000000"
        end
        tech.setParentDirectives(explodeDirectives)
    end
end
function uninit()
    tech.setParentState()
    status.clearPersistentEffects("abyssSimpleStats")
    tech.setParentDirectives()
end
 
