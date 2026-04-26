require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/poly.lua"
require "/scripts/actions/movement.lua"
require "/scripts/actions/animator.lua"
require "/scripts/companions/capturable.lua"

local ownerId
local dieTimer = 10
local tickDieTimer = true
local slavePerc = false
local uuid
local ownerUuid
-- Engine callback - called on initialization of entity
function init()
    self.pathing = {}
    self.shouldDie = true
    ownerId = config.getParameter("ownerId")
    tickDieTimer = not config.getParameter("noKeepAlive",false)
    slavePerc = config.getParameter("slavePerc",false)
    uuid = config.getParameter("uuid")
    ownerUuid = uuid
    monster.setAggressive(false)

  message.setHandler("damageTeam", function(_,_,team)
        monster.setDamageTeam(team)
  end)
  
  script.setUpdateDelta(config.getParameter("initialScriptDelta", 1))
  mcontroller.setAutoClearControls(false)

  animator.setGlobalTag("flipX", "")

  self.debug = true

  message.setHandler("despawn", function()
    end)
  
  monster.setInteractive(config.getParameter("interactive", false))
  
  mcontroller.controlFace(1)
  if not storage.damageBar then
    monster.setDamageBar("None")
    storage.damageBar = "None"
  end
  monster.setDamageOnTouch(false)
end
function noHeal()
  return true
end
function keepAlive()
  dieTimer = 10
end
equips = keepAlive

function toggleDamageBar()
  if storage.damageBar == "None" then
    storage.damageBar = "Special"
  else
    storage.damageBar = "None"
  end
  monster.setDamageBar(storage.damageBar)
  return storage.damageBar
end

local forceDie = false
function update(dt)
  local red = math.max(math.min(math.sin(os.clock())*127, 127), 0)
  if tickDieTimer then
    dieTimer = dieTimer - 1
  end
  if dieTimer < 0 then
    forceDie = true
    return
  end  
  if not world.entityExists(ownerId) then
    forceDie = true
    return
  else
    monster.setDamageTeam(world.entityDamageTeam(ownerId))
    monster.setName(world.entityName(ownerId))
    ownerUuid = world.entityUniqueId(ownerId)
    if uuid and ownerUuid ~= uuid then
      forceDie = true
    end
  end
  mcontroller.setPosition(vec2.add(world.entityPosition(ownerId),vec2.mul(world.entityVelocity(ownerId),dt)))
  mcontroller.setVelocity({0,0})
  local hp
  if slavePerc then
    hp = world.sendEntityMessage(ownerId,"abyss_getHealthPerc"):result()
  else
    local hpv = world.entityHealth(ownerId)
    hp = hpv[1]/hpv[2]
  end
  status.setResourcePercentage("health", hp)
end
function inflictedDamage()
  local out,t = status.inflictedDamageSince(storage.since)
  storage.since = t
  return out
end

function interact(args)
end

function shouldDie()
    return (self.shouldDie and status.resource("health") <= 0) or dieTimer < 0 or forceDie
end

function die()
end
function kill()
  dieTimer = -1
end
function setHealth(health)
    lastHealth = health
    status.setResourcePercentage("health", health)
end
