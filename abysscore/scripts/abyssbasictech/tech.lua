require "/scripts/terra_vec2ref.lua"
require "/scripts/abyssmodules/command.lua"
require "/scripts/abyssmodules/radar.lua"
require "/scripts/abyssmodules/freecam.lua"
require "/scripts/abyssmodules/explode.lua"
require "/scripts/abyssmodules/faceandteleport.lua"
require "/scripts/abyssmodules/sitandlock.lua"
require "/scripts/abyssmodules/misccommands.lua"
require "/scripts/abyssutil.lua"
require "/scripts/abysshumanoidconfig.lua"

function init()
    if not input then
        return
    end
    ensureBasicProxies()
    message.setHandler("abyss_parentState",function(_,l)
        if not l then return "nuh uh" end
        return modules.parentState
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
        local cfg = getAbyssConfig()
        if cfg and cfg.lightColour then
            return "Cannot override glow; a config is setting glow already"
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
    message.setHandler("abyssbasic_updateConfig",function(_,l)
        if not l then return "no" end
        local cfg = getAbyssConfig() or {}
        animator.setLightColor("glow",cfg.lightColour or player.getProperty("abyss_lightColour",{0,0,0}))
    end)
    -- TODO: optional clothing 'covered region' checks, to dynamically dim the light based on visible clothing
    animator.setParticleEmitterActive("sparkles",false)
    local cfg = getAbyssConfig() or {}
    animator.setLightColor("glow",cfg.lightColour or player.getProperty("abyss_lightColour",{0,0,0}))
    local ignoreSpecial = config.getParameter("ignoreSpecial",false)
    mcontroller.setAutoClearControls(true)
    if not ignoreSpecial then
        commandModule.enableMoveKey = "special1"
        radarModule.enableMoveKey = "special3"
    end
    modules.init()
end

local moduleParentState
function update(args)
    if not ensureBasicProxies() then
        return
    end
    modules.update(args)
    local toolSuppressed = modules.suppressToolUsage()
    local moveSuppressed = modules.suppressMovement()
    local moveSuppressed2 = modules.suppressCustomMovement()
    local specialSuppressed = modules.suppressSpecial()
    if moduleParentState ~= modules.parentState then
        moduleParentState = modules.parentState
        tech.setParentState(modules.parentState)
    end
    tech.setToolUsageSuppressed(toolSuppressed)
    
    if moveSuppressed then
        mcontroller.controlModifiers({
            movementSuppressed=true
        })
    end
    
    tech.setParentDirectives(modules.directives)
end
function uninit()
    modules.uninit()
    tech.setToolUsageSuppressed(false)
    tech.setParentState()
    tech.setParentDirectives()
end
 
