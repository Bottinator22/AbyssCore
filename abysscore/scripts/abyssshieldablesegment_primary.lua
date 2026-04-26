require "/scripts/vec2.lua"
require "/scripts/abyssimmunity.lua"
require "/scripts/abyssminionstats.lua"

function init()
  self.damageFlashTime = 0

  message.setHandler("applyStatusEffect", function(_, _, effectConfig, duration, sourceEntityId)
      -- refuse to apply status effects if immune
      if abyssStatusImmunity.isImmune(effectConfig) then
        return
      end
      status.addEphemeralEffect(effectConfig, duration, sourceEntityId)
      local pass = status.statusProperty("passEffectMessages")
      if pass then
        local head = status.statusProperty("headId")
        local head2  = status.statusProperty("head2Id")
        if head then
          world.sendEntityMessage(head, "applyStatusEffect", effectConfig, duration, sourceEntityId)
        end
        if head2 then
          world.sendEntityMessage(head2, "applyStatusEffect", effectConfig, duration, sourceEntityId)
        end
      end
    end)
    message.setHandler("abyss_shieldable",function()
      return not status.statusProperty("noShield") and status.stat("maxShield") > 0 and status.resourcePercentage("shieldHealth") < 1
    end)
    message.setHandler("abyss_addShield",function(_,_,am)
      if status.statusProperty("noShield") then
        return
      end
      if am > 0 then
        if not status.resourcePositive("shieldHealth") then
          world.callScriptedEntity(entity.id(),"shieldCreateEffects")
        end
        status.modifyResource("shieldHealth",am)
      end
    end)
    message.setHandler("abyss_applyBoost",function(_,l,e)
      if status.isResource("energy") and status.resourcePercentage("energy") < 1 then
        status.modifyResource("energy",e)
      elseif status.resourcePercentage("health") < 1 then
        status.modifyResource("health",e)
      elseif e > 0 and not status.statusProperty("noShield") then
        if not status.resourcePositive("shieldHealth") then
          world.callScriptedEntity(entity.id(),"shieldCreateEffects")
        end
        status.modifyResource("shieldHealth",e)
      end
    end)
    message.setHandler("anchoredMinionDamageMode",function(_,l)
      if status.resourcePositive("shieldHealth") then
        return "redirect"
      else
        return "take"
      end
    end)
end

local infShield
local damageScore = 0
function applyDamageRequest(damageRequest)
  if world.getProperty("nonCombat") then
    return {}
  end
  if world.getProperty("invinciblePlayers") then
    return {}
  end
  local head = status.statusProperty("headId")
  local head2  = status.statusProperty("head2Id")

  -- don't get hit by knockback attacks if immune to knockback
  if damageRequest.damageType == "Knockback" and status.stat("grit") >= 1 then
    return {}
  end

  local damage = 0
  if damageRequest.damageType == "Damage" or damageRequest.damageType == "Knockback" then
    damage = damage + root.evalFunction2("protection", damageRequest.damage, status.stat("protection"))
  elseif damageRequest.damageType == "IgnoresDef" then
    damage = damage + damageRequest.damage
  elseif damageRequest.damageType == "Status" then
    -- only apply status effects
    status.addEphemeralEffects(abyssStatusImmunity.filter(damageRequest.statusEffects), damageRequest.sourceEntityId)
    return {}
  elseif damageRequest.damageType == "Environment" then
    return {}
  end
  
  local shieldAbsorb = 0
  local wasShield = status.resourcePositive("shieldHealth")
  if status.resourcePositive("shieldHealth") then
    damage = math.min(damage, status.statusProperty("redirectCap", 1/0))
    shieldAbsorb = math.min(damage, status.resource("shieldHealth"))
    status.modifyResource("shieldHealth", -shieldAbsorb)
    world.callScriptedEntity(entity.id(), "shieldHit",shieldAbsorb)
    damage = damage - shieldAbsorb
  end
  if infShield and not status.statusProperty("noShield") then
    if not wasShield then
        world.callScriptedEntity(entity.id(),"shieldCreateEffects")
    end
    status.setResourcePercentage("shieldHealth",1)
    shieldAbsorb = shieldAbsorb + damage
    damage = 0
  end
  if not status.resourcePositive("shieldHealth") and shieldAbsorb > 0 then
    world.callScriptedEntity(entity.id(),"shieldBreakEffects")
  end

  local hitType = damageRequest.hitType
  local elementalStat = root.elementalResistance(damageRequest.damageSourceKind)
  local resistance = status.stat(elementalStat)
  damage = damage - (resistance * damage)
  if resistance ~= 0 and damage > 0 then
    hitType = resistance > 0 and "weakhit" or "stronghit"
  end
  
  damage = math.min(damage, status.statusProperty("redirectCap", 1/0), status.statusProperty("dpsCap", 1/0)-damageScore)
  damageScore = damageScore + damage

  if head then
      damageRequest.damage = damage
      damage = 0
      damageRequest.statusEffects = {}
      if status.statusProperty("needsMessage", false) then
        world.sendEntityMessage(head, "takeDamage", damageRequest)
      else
        world.callScriptedEntity(head, "takeDamage", damageRequest)
      end
      if head2 then
        if status.statusProperty("needsMessage2", false) then
          world.sendEntityMessage(head2, "takeDamage", damageRequest)
        else
          world.callScriptedEntity(head2, "takeDamage", damageRequest)
        end
      end
  elseif head2 then
    -- deal damage but don't cancel it from here
    damageRequest.damage = damage
    damageRequest.statusEffects = {}
    if status.statusProperty("needsMessage2", false) then
      world.sendEntityMessage(head2, "takeDamage", damageRequest)
    else
      world.callScriptedEntity(head2, "takeDamage", damageRequest)
    end
  end
  
  local healthLost = math.min(damage, status.resource("health"))
  if healthLost > 0 and damageRequest.damageType ~= "Knockback" then
      if not head then
        status.modifyResource("health", -healthLost)
      end
      if not status.statusProperty("noFlash",false) then
        if hitType == "stronghit" then
          self.damageFlashTime = 0.07
          self.damageFlashType = "strong"
        elseif hitType == "weakhit" then
          self.damageFlashTime = 0.07
          self.damageFlashType = "weak"
        else
          self.damageFlashTime = 0.07
          self.damageFlashType = "default"
        end
      end
  end

  status.addEphemeralEffects(abyssStatusImmunity.filter(damageRequest.statusEffects), damageRequest.sourceEntityId)

  local knockbackFactor = (1 - status.stat("grit"))
  local momentum = knockbackMomentum(vec2.mul(damageRequest.knockbackMomentum, knockbackFactor))
  if status.resourcePositive("health") and vec2.mag(momentum) > 0 then
    self.applyKnockback = momentum
    if vec2.mag(momentum) > status.stat("knockbackThreshold") then
      status.setResource("stunned", math.max(status.resource("stunned"), status.stat("knockbackStunTime")))
    end
  end

  if not status.resourcePositive("health") then
    hitType = "kill"
  end
  
  return {{
    sourceEntityId = damageRequest.sourceEntityId,
    targetEntityId = entity.id(),
    position = mcontroller.position(),
    damageDealt = damage+shieldAbsorb,
    healthLost = healthLost,
    hitType = hitType,
    kind = "Normal",
    damageSourceKind = damageRequest.damageSourceKind,
    targetMaterialKind = status.statusProperty("targetMaterialKind")
  }}
end

function knockbackMomentum(momentum)
  local knockback = vec2.mag(momentum)
  if mcontroller.baseParameters().gravityEnabled and math.abs(momentum[1]) > 0  then
    local dir = momentum[1] > 0 and 1 or -1
    return {dir * knockback / 1.41, knockback / 1.41}
  else
    return momentum
  end
end

function update(dt)
  status.setPersistentEffects("entities", abyssStatusImmunity.filter(status.getPersistentEffects("entities")))
  if not status.statusProperty("leaveDirectives") then
    if self.damageFlashTime > 0 then
      local color = status.statusProperty("damageFlashColor") or "ff0000=0.85"
      if self.damageFlashType == "strong" then
        color = status.statusProperty("strongDamageFlashColor") or "ffffff=1.0" or color
      elseif self.damageFlashType == "weak" then
        color = status.statusProperty("weakDamageFlashColor") or "000000=0.0" or color
      end
      status.setPrimaryDirectives(string.format("fade=%s", color))
    else
      status.setPrimaryDirectives()
    end
  end
  
  local ownerId = status.statusProperty("playerId") or status.statusProperty("headId") or status.statusProperty("head2Id")
  infShield = status.statusProperty("infShield", false) or (ownerId and world.entityExists(ownerId) and world.sendEntityMessage(ownerId,"infiniteShieldActive"):result())
  
  damageScore = math.max(damageScore - status.statusProperty("dpsCap", 1/0)*dt, 0)

  self.damageFlashTime = math.max(0, self.damageFlashTime - dt)
  
  abyssStatusImmunity.update()
  adaptStats()
  if not status.statusProperty("shield_useParentHealth") or (ownerId and world.entityExists(ownerId)) then
    local maxHealth = status.stat("maxHealth")
    if status.statusProperty("shield_useParentHealth") then
      maxHealth = world.entityHealth(ownerId)[2]
    else
      maxHealth = status.stat("maxHealth")
    end
    status.setPersistentEffects("abyssShield", {
        {stat = "maxShield", amount = maxHealth*status.stat("shieldHealthPerc")}
    })
  end
  
  if self.applyKnockback then
    mcontroller.setVelocity({0,0})
    if vec2.mag(self.applyKnockback) > status.stat("knockbackThreshold") then
      mcontroller.addMomentum(self.applyKnockback)
    end
    self.applyKnockback = nil
  end

  if mcontroller.atWorldLimit(true) then
    --status.setResourcePercentage("health", 0)
  end
end
