require "/scripts/abyssmodules/modules.lua"

-- does nothing, but forces other modules to yield to vehicle controls
local module = {
    moduleSlots={
        fire=true,
        special=true,
        movement=true
    }
}
--[[
function module.shouldEnable(args)
    return module.isActive()
end]]
function module.suppressMovement()
    return false
end
function module.suppressToolUsage()
    return false
end
function module.isActive()
    return player.isLounging() and world.entityType(player.loungingIn()) == "vehicle"
end
module.shouldEnable = module.isActive
function module.update(args)
    if module.shouldEnable(args) and not module.enabled then
        -- force enable.
        modules.enableModule(module)
    end
end
presentModules.vehicle = module
