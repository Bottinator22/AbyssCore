require "/scripts/abyssmodules/modules.lua"

-- extremely simplistic passive module, barely needs to be a module
-- but it's there so teleport can be implemented very easily in one require line
-- also includes facing control

function onTeleport(p)
end
function onFace(f)
end

local module = {
    moduleSlots={},
    passive=true
}
function module.isBindHeld(args)
    return input.bindHeld("abysscore","blink")
end
function module.init()
    radarInit()
end
function module.isActive()
    return false
end
function module.bindPressed()
    mcontroller.setPosition(tech.aimPosition())
    mcontroller.setVelocity({0,0})
    onTeleport(tech.aimPosition())
end
function module.update(args)
    if input.bindHeld("abysscore","face") then
        local dis = world.distance(tech.aimPosition(),mcontroller.position())
        local f = 1
        if dis[1] < 0 then
            f = -1
        end
        mcontroller.controlFace(f)
        onFace(f)
    end
end
presentModules.teleport = module
