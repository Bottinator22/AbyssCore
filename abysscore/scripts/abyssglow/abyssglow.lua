require "/scripts/abyssutil.lua"
require "/scripts/abysshumanoidconfig.lua"

function init()
    animator.setParticleEmitterActive("sparkles",false)
    animator.setLightColor("glow",{0,0,0})
    script.setUpdateDelta(60)
    if not ensureBasicProxies() then
        return
    end
    message.setHandler("abyssglow_updateConfig",function(_,l)
        if not l then return "no" end
        local cfg = getAbyssConfig() or {}
        animator.setLightColor("glow",cfg.lightColour or player.getProperty("abyss_lightColour",{0,0,0}))
    end)
    -- TODO: optional clothing 'covered region' checks, to dynamically dim the light based on visible clothing
    local cfg = getAbyssConfig() or {}
    animator.setLightColor("glow",cfg.lightColour or player.getProperty("abyss_lightColour",{0,0,0}))
    script.setUpdateDelta(0)
end

function update(dt)
    if ensureBasicProxies() then
        init()
    end
end
