require "/scripts/vec2.lua"
require "/scripts/terra_vec2ref.lua"

-- Component of minion monster scripts.
-- Finds other minions via entity queries and performs physics with them.

local vec2working1 = {0,0}
local vec2working2 = {0,0}
local vec2working3 = {0,0}
local maxSize = 20
physics = {}
function getSize()
    return 1
end
function getMass()
  return 1
end
function push(accel)
  mcontroller.setVelocity(vec2.addToRef(mcontroller.velocity(), accel, vec2working1))
end
function abyss_isPhysics()
  return true
end
function physics()
  for k,v in next, world.entityQuery(mcontroller.position(),getSize()*2,{callScript="abyss_isPhysics",withoutEntityId=entity.id(),boundMode="metaboundbox"}) do
    local otherPos = world.entityPosition(v)
    local mag = world.magnitude(mcontroller.position(), otherPos)
    if mag < maxSize then
      local softness = 1/2
      local size = getSize() + world.callScriptedEntity(v, "getSize")
      if mag < size then
        local angle = vec2.normToRef(world.distance(mcontroller.position(), otherPos), vec2working1)
        local myMass = getMass()
        local otherMass = world.callScriptedEntity(v, "getMass")
        local totalMass = myMass + otherMass
        local disp = size-mag
        mcontroller.setVelocity(vec2.addToRef(mcontroller.velocity(), vec2.mulToRef(angle, (disp+otherMass/totalMass)/softness, vec2working2), vec2working2))
        world.callScriptedEntity(v, "push", vec2.mulToRef(angle, -(disp+myMass/totalMass)/softness, vec2working2))
        world.debugLine(mcontroller.position(), otherPos, "cyan")
      end
    end
  end
end
