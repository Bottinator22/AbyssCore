-- simple client master item drop controllable with Abyss Command
require "/scripts/abysscommandableutil.lua"
require "/scripts/terra_vec2ref.lua"

local targetPos
local maxAccel = 240
local maxSpeed = 60

function init()
    itemDrop.setEternal(true)
end

function update(dt)
    updateOrders()
    if targetPos then
        mcontroller.applyParameters({gravityEnabled=false})
        local dis = world.distance(targetPos,mcontroller.position())
        local targetVel = vec2.mul(vec2.norm(dis),math.min(vec2.mag(dis)*8,maxSpeed))
        
        local velDis = vec2.sub(targetVel,mcontroller.velocity())
        local accel = vec2.mul(vec2.norm(velDis),math.min(vec2.mag(velDis)/dt,maxAccel))
        
        mcontroller.setVelocity(vec2.add(mcontroller.velocity(),vec2.mul(accel,dt)))
    else
        mcontroller.applyParameters({gravityEnabled=true})
    end
end

function orderChanged(new)
end
function updateOrders_reset()
    targetPos = nil
end
function command_enableBars()
  return false
end
function command_category()
  return (entity.id() >= 0) and "abyss_itemdrop_server" or "abyss_itemdrop"
end
function command_radius()
  return 0.5
end

function supportsOrder(t)
  local supportedOrders = {
        move=true,
        change=entity.id() < 0,
        holdposition=true,
        teleport=true,
        suicide=true
    }
  return supportedOrders[t]
end

orderFuncs = {
    suicide=function(current)
        itemDrop.setOverrideMode("Dead")
        return false
    end,
    change=function(current)
        local id = item.descriptor()
        if id.parameters.itemDrop then
            id.parameters.itemDrop = nil
            world.spawnItem(id,mcontroller.position(),nil,nil,mcontroller.velocity(),itemDrop.intangibleTime())
            itemDrop.setOverrideMode("Dead")
        end
        return true
    end,
    move=function(current)
        targetPos = current.target
        return world.magnitude(mcontroller.position(),current.target) < 0.25
    end,
    teleport=function(current)
        mcontroller.setPosition(current.target)
        return true
    end,
}
orderFuncs.holdposition = orderFuncs.move

