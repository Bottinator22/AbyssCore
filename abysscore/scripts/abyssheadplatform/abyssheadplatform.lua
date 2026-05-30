require "/scripts/terra_vec2ref.lua"

local ownerId
local deleteTimer = 2
function init()
    vehicle.setInteractive(false)
    ownerId = config.getParameter("ownerId")
end
function update(dt)
    if not world.entityExists(ownerId) or deleteTimer <= 0 then
        vehicle.destroy()
        return
    end
    deleteTimer = deleteTimer - 1
    mcontroller.setVelocity({0,0})
end
function updatePos(r,c)
    if not world.entityExists(ownerId) or deleteTimer <= 0 then
        return
    end
    mcontroller.setPosition(world.entityPosition(ownerId))
    animator.resetTransformationGroup("body")
    animator.rotateTransformationGroup("body",r)
    mcontroller.setVelocity({0,0})
    vehicle.setMovingCollisionEnabled("platform",not c)
    vehicle.setMovingCollisionEnabled("platform_duck",c)
end
function keepAlive()
    deleteTimer = 2
end
function applyDamage(damageRequest)
    return {}
end
function isAbyssHeadplatform()
    return true
end
