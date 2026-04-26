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

local layMode = false
local layTogglesSit = false
local sitMode = false
local duckMode = false
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
function setParentState(n)
    parentState = n
    tech.setParentState(n)
end
function init()
    if not input then
        return
    end
    message.setHandler("abyss_parentState",function(_,l)
        if not l then return "nuh uh" end
        return parentState
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
    message.setHandler("/bossbar", function(_,isLocal)
        if not isLocal then return "no" end
        if not storage.bossbarId or not world.entityExists(storage.bossbarId) then
            local params = sb.jsonMerge(root.assetJson("/scripts/abyssBasicParams.json"), root.assetJson("/scripts/abyssBossbarParams.json"))
            params = sb.jsonMerge(params, {ownerId=entity.id(),noKeepAlive=true,slavePerc=false,uuid=entity.uniqueId()})
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
        if #split < 3 then
            player.setProperty("abyss_lightColour",{0,0,0})
            animator.setLightColor("glow",{0,0,0})
            return "Reset glow."
        end
        player.setProperty("abyss_lightColour",split)
        animator.setLightColor("glow",split)
        return "Set glow."
    end)
    -- TODO: clothing 'covered region' checks, to dynamically dim the light based on visible clothing
    animator.setParticleEmitterActive("sparkles",false)
    animator.setLightColor("glow",player.getProperty("abyss_lightColour",{0,0,0}))
    ignoreSpecial = config.getParameter("ignoreSpecial",false)
    if not player then
        player = terra_proxy.setupProxy("player",entity.id())
    end
    status.setPersistentEffects("abyssSimpleStats", {
        {stat = "fallDamageMultiplier", effectiveMultiplier = 0.0},
        {stat = "lavaImmunity", amount = 1.0}
    })
    radarInit()
    mcontroller.setAutoClearControls(true)
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
    if heldEmote then
        player.emote(heldEmote)
    end
    if input then
        if input.bindHeld("abysscore","blink") and not lastTele then
            mcontroller.setPosition(tech.aimPosition())
            mcontroller.setVelocity({0,0})
        end
        lastTele = input.bindHeld("abysscore","blink")
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
    end
end
function uninit()
    status.clearPersistentEffects("abyssSimpleStats")
end
 
