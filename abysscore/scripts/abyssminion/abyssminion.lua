require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/terra_vec2ref.lua"
require "/scripts/terra_vec3.lua"
require "/scripts/poly.lua"
require "/scripts/status.lua"
require "/scripts/actions/movement.lua"
require "/scripts/actions/animator.lua"
require "/scripts/companions/capturable.lua"
require "/scripts/abyssphysics.lua"
require "/scripts/abysstrail.lua"
require "/scripts/abyssparticles.lua"
require "/scripts/terra_aimposition.lua"
require "/scripts/terra_loadRegion.lua"

local passiveMode = false
function command_isPassive()
  return passiveMode
end

math.randomseed(math.floor(os.clock()*10000))
local initialized
local ownerId
local coreId
local isExpanded
local dieTimer = 20
local timer = 0
local stateColours = {
  idle={255,0,0},
  green={0,255,0},
  purple={158,0,255},
  blue={0,170,255},
  yellow={255,255,0},
  aqua={0,255,255},
  deepblue={0,0,255},
  magenta={255,0,255}
}
local orders = {}
local zeroVec = {0,0}
local lastEyeAnimState
local closeEyeTimer = 0
local r = 0
local spinDir = (math.random()>0.5) and 1 or -1
local eyeState = "idle"
local eyeAnimState = "idle"
local eyeScale = 1
local eyeTarget = {0,0}
local shootTimer = 0
local orbitD = math.pi/60
local orbitDistance = 7+8*math.random()
local orbitDFlipTimer = 120*math.random()
local passiveTargetPos = {0,0}
local hasPassiveTargetPos = false
local colourTimeOffset = math.pi*2*math.random()
local mtrails = {{
  layer="front",
  size=4,
  time=0.15,
  color={255,0,0,255},
  part="bodyFullbright",
  point="lightPos"
},{
  layer="front",
  size=1,
  time=0.15,
  color={255,255,255,255},
  part="bodyFullbright",
  point="lightPos"
}}
local vec2working1 = {0,0}
local vec2working2 = {0,0}
local vec2working3 = {0,0}
local vec2working4 = {0,0}
local approachSpeed = 2
local maxSpeed = 50
local movementDecel = 0.99
local minTargetRange = 50
local maxTargetRange = 70
local maxTargetRangeFromCore = 80
local targetQueryInterval = 10
local targetQueryTimer = 0
local minionType
local targetPos
local overrideTargetPos
local overrideTargetId
local overrideHealId
local overrideTargetingPos
local overrideTargetVel
local targetStartingHealth
local targetLockTime
local lastTargetId
local followId
local targetId
local targetBlacklist = {}
local follow = true
local trueOwnerId
local anchorPos = nil
local anchorParent = nil
local anchorRotParent = nil
local anchorRotLimit = nil
local preciseMove = false
local attackFuncs
function table.find(org, findValue)
    for key,value in pairs(org) do
        if value == findValue then
            return key
        end
    end
    return nil
end
function defaultRangeFromCore()
  if anchorParent then
    return 1/0
  end
  return 80
end
function setType(f)
  minionType = f
end
function sanitizeString(s)
  local new = ""
  for c in string.gmatch(s,".") do
    if string.byte(c) ~= 0 then
      new=new..c
    end
  end
  return new
end
local isPassiveIdle = true
local builder_minPos
local builder_maxPos
local builder_blocks
local builder_timer = 0
function builder_key(x,y,layer)
  return string.format("x%.0fy%.0fl%s",x,y,layer)
end
local dOptions = {}
function builder_set(x,y, layer, mat, op)
  local key = builder_key(x,y,layer)
  if not builder_blocks then
    builder_blocks = {}
    builder_minPos = {math.huge,math.huge}
    builder_maxPos = {-math.huge,-math.huge}
  end
  builder_minPos[1] = math.min(builder_minPos[1], x)
  builder_minPos[2] = math.min(builder_minPos[2], y)
  builder_maxPos[1] = math.max(builder_maxPos[1], x+1)
  builder_maxPos[2] = math.max(builder_maxPos[2], y+1)
  builder_blocks[key] = {pos={x,y,layer},mat=mat,active=false,hue=(op or dOptions).hue or nil,collisionMode=(op or dOptions).coll or nil}
end
function builder_order(from, to, layer, mat)
  for x=from[1],to[1]-1,1 do
    for y=from[2],to[2]-1,1 do
      builder_set(x,y,layer,mat)
    end
  end
end
-- expects schematic to be decompressed already
-- same format as Support Drone schematic
function builder_schematic(schem, pos)
  local size = schem.size
  for y,r in next,schem.background do
    for x,v in next,r do
      builder_set(pos[1]+x-1,pos[2]-y+1,"background",v)
    end
  end
  for y,r in next,schem.foreground do
    for x,v in next,r do
      builder_set(pos[1]+x-1,pos[2]-y+1,"foreground",v)
    end
  end
  -- todo: objects
end
local otherLayer = {
  foreground="background",
  background="foreground"
}
local miscGroupI = 0
local miscGroups = {
  "misc1",
  "misc2",
  "misc3",
  "misc4",
  "misc5",
  "misc6"
}
local builder_maxBeams = 50
local builder_beams = {}
for i=1,builder_maxBeams,1 do
  local part = "laser"
  if i > 1 then
    part = string.format("laser%.0f",i)
  end
  table.insert(builder_beams, {
    part=part,
    current=nil
  })
end
local function builder_anyFreeBeams()
  for k,v in next, builder_beams do
    if not v.current then
      return true
    end
  end
  return false
end
local function builder_unassigned(b)
  --[[for k,v in next, builder_beams do
    if v.current == b then
      return false
    end
  end]]
  return not b.active
end
local function builder_assignBeam(b)
  for k,v in next, builder_beams do
    if not v.current then
      v.current = b
      b.active = true
      return true
    end
  end
  return false
end
function getMiscGroup()
  miscGroupI = miscGroupI + 1
  return miscGroups[miscGroupI]
end
local analyzerReadResources = {
  {
    name="shieldHealth",
    displayName="Shield Health"
  },
  {
    name="shieldStamina",
    displayName="Shield Stamina",
    perc=true
  },
  {
    name="energy",
    displayName="Energy"
  },
  {
    name="damageAbsorption",
    displayName="Damage Absorption"
  },
  {
    name="stunned",
    displayName="Stunned",
    noVal=true
  }
}
local analyzerReadStats = {
  {
    name="invulnerable",
    displayName="Invulnerable",
    noVal=true
  },
  {
    name="statusImmunity",
    displayName="Status Immune",
    noVal=true
  },
  {
    name="powerMultiplier",
    displayName="Power Multiplier",
    perc=true
  },
  {
    name="protection",
    displayName="Protection",
  },
  {
    name="healthRegen",
    displayName="Health Regen"
  },
  {
    name="grit",
    displayName="Knockback Resistance",
    perc=true
  },
  {
    name="poisonResistance",
    displayName="Poison Resistance",
    perc=true
  },
  {
    name="fireResistance",
    displayName="Fire Resistance",
    perc=true
  },
  {
    name="electricResistance",
    displayName="Electric Resistance",
    perc=true
  },
  {
    name="iceResistance",
    displayName="Ice Resistance",
    perc=true
  },
  {
    name="physicalResistance",
    displayName="Physical Resistance",
    perc=true
  },
  {
    name="poisonStatusImmunity",
    displayName="Poison Status Immune",
    noVal=true
  },
  {
    name="fireStatusImmunity",
    displayName="Fire Status Immune",
    noVal=true
  },
  {
    name="electricStatusImmunity",
    displayName="Electric Status Immune",
    noVal=true
  },
  {
    name="iceStatusImmunity",
    displayName="Ice Status Immune",
    noVal=true
  },
  {
    name="specialStatusImmunity",
    displayName="Special Status Immune",
    noVal=true
  },
  {
    name="healingStatusImmunity",
    displayName="Healing Status Immune",
    noVal=true
  },
  {
    name="lavaImmunity",
    displayName="Lava Immune",
    noVal=true
  },
  {
    name="stunImmunity",
    displayName="Stun Immune",
    noVal=true
  }
}
local playerId
local function getNameVis()
  return world.sendEntityMessage(playerId,"abyssNameVis"):result()
end
-- Engine callback - called on initialization of entity
function init()
    self.pathing = {}
    self.shouldDie = true
    initialized = false
    isExpanded = config.getParameter("isExpanded") -- whether or not this minion has expanded params
    ownerId = config.getParameter("ownerId")
    coreId = config.getParameter("coreId")
    anchorParent = config.getParameter("anchorParent")
    anchorRotParent = config.getParameter("anchorRotParent")
    anchorPos = config.getParameter("anchorPos",{0,0})
    anchorRotLimit = config.getParameter("anchorRotLimit")
    trueOwnerId = config.getParameter("trueOwnerId")
    playerId = config.getParameter("playerId",trueOwnerId or ownerId)
    status.setStatusProperty("playerId",playerId)
    followId = coreId
    minionType = config.getParameter("minionType")
    if config.getParameter("enableRedirect",false) then
      status.setStatusProperty("needsMessage2", true)
      status.setStatusProperty("needsMessage", true)
      if trueOwnerId or config.getParameter("noMessage",false) then
        table.insert(targetBlacklist, trueOwnerId)
        status.setStatusProperty("needsMessage2", false)
        status.setStatusProperty("needsMessage", false)
      end
      status.setStatusProperty("head2Id", ownerId)
      status.setStatusProperty("redirectCap", 300)
    end
    monster.setAggressive(true)
    local position = mcontroller.position()
    targetPos = position
    myDamageSources = ControlMap:new(config.getParameter("damageSources", {}))
    maxTargetRangeFromCore = defaultRangeFromCore()

  message.setHandler("damageTeam", function(_,_,team)
        monster.setDamageTeam(team)
  end)
  self.notifications = {}
  if not storage.spawnTime then
    abyssParticles.spawnParticles(position, 6, 15)
  end
  storage.spawnTime = world.time()

  self.collisionPoly = mcontroller.collisionPoly()

  if animator.hasSound("deathPuff") then
    monster.setDeathSound("deathPuff")
  end
  if config.getParameter("deathParticles") then
    monster.setDeathParticleBurst(config.getParameter("deathParticles"))
  end

  script.setUpdateDelta(config.getParameter("initialScriptDelta", 1))
  mcontroller.setAutoClearControls(false)

  animator.setGlobalTag("flipX", "")

  self.debug = true

  message.setHandler("notify", function(_,_,notification)
      return notify(notification)
    end)
  message.setHandler("despawn", function()
    end)

  self.forceRegions = ControlMap:new(config.getParameter("forceRegions", {}))
  self.damageSources = ControlMap:new(config.getParameter("damageSources", {}))
  self.touchDamageEnabled = false
  
  monster.setInteractive(config.getParameter("interactive", false))

  monster.setAnimationParameter("chains", config.getParameter("chains"))
  
  mcontroller.controlFace(1)
    status.setPersistentEffects("wormImmunity", {
        {stat = "lavaImmunity", amount = 1},
        {stat = "poisonStatusImmunity", amount = 1},
        {stat = "fireStatusImmunity", amount = 1},
        {stat = "electricStatusImmunity", amount = 1},
        {stat = "iceStatusImmunity", amount = 1}
    })
  monster.setName("^#7F0000;Abyssal Minion^reset;")
  local dt = script.updateDt()
  passiveFuncs={
    builder=function()
        -- TODO: move this to its own script
        if not isExpanded then
          world.debugText("Attempting to run builder code on a non-expanded minion!",mcontroller.position(),"red")
          return
        end
        builder_timer = builder_timer+1
        timer = timer + 1
        local anyToDo = false
        if builder_blocks and builder_timer > 0 and builder_anyFreeBeams() then
          builder_timer = 0
          for k,v in next, builder_blocks do
            if builder_unassigned(v) then
              if world.isTileProtected(v.pos) or v.pos[2] < 0 or v.pos[2] >= world.size()[2] then
                builder_blocks[k] = nil
              elseif v.pos[3] == "liquid" then
                local l = world.liquidAt(vec2.copyToRef(v.pos, vec2working1))
                local g = false
                if not l then
                  if not v.mat or world.material(v.pos,"foreground") then
                    g = true
                  end
                else
                  if v.mat == root.liquidName(l[1]) then
                    g = true
                  end
                end
                if not g then
                  anyToDo = true
                  builder_assignBeam(v)
                  if not builder_anyFreeBeams() then
                    break
                  end
                else
                  builder_blocks[k] = nil
                end
              else
                if v.delayUntil and v.delayUntil > timer then
                  anyToDo = true
                elseif world.material(v.pos,v.pos[3]) ~= v.mat then
                  anyToDo = true
                  builder_assignBeam(v)
                  if not builder_anyFreeBeams() then
                    break
                  end
                elseif not (v.expireDelayUntil and v.expireDelayUntil > timer) then
                  builder_blocks[k] = nil
                else
                  anyToDo = true
                end
              end
            else
              anyToDo = true
            end
          end
          if not anyToDo then
            builder_blocks = nil
          end
        end
        local mePos = vec2.add(mcontroller.position(), vec2.mulToRef(mcontroller.velocity(), 1/60, vec2working1))
        if builder_blocks then
          vec2.addToRef(vec2.mulToRef(vec2.disToRef(builder_maxPos, builder_minPos, vec2working1),0.5,vec2working1), builder_minPos, eyeTarget)
          world.debugPoint(eyeTarget, "green")
          local t = vec2working4
          t[1] = math.min(math.max(mePos[1],builder_minPos[1]),builder_maxPos[1])
          t[2] = math.min(math.max(mePos[2],builder_minPos[2]),builder_maxPos[2])
          world.debugPoint(t, "magenta")
          if vec2.eq(t, mePos) then
            -- move out of the target square
            -- eyeTarget is currently the center of the structure, so use it as a position to move away from
            local angle = vec2.normToRef(world.distance(mePos, eyeTarget), vec2working1)
            local dis = 100
            vec2.addToRef(mePos, vec2.mulToRef(angle, dis, vec2working1), targetPos)
          else
            -- keep within a distance of the target square
            local angle = vec2.normToRef(world.distance(mePos, t), vec2working1)
            local dis = orbitDistance
            vec2.addToRef(t, vec2.mulToRef(angle, dis, vec2working1), targetPos)
          end
          isPassiveIdle = false
          animator.setAnimationState("misc", "deepblue")
          -- visually represent the target square with 4 animated parts
          local poly = {builder_minPos, {builder_minPos[1],builder_maxPos[2]}, builder_maxPos, {builder_maxPos[1],builder_minPos[2]}}
          local gA = 0
          local ga = 0
          local gb = 0
          for k,v in next, poly do
            local n = poly[k+1]
            if k == 4 then
              n = poly[1]
            end
            local l = world.magnitude(v,n)
            local a = vec2.angle(world.distance(n,v))
            local g = getMiscGroup()
            animator.resetTransformationGroup(g)
            animator.scaleTransformationGroup(g, {l*8,1})
            animator.translateTransformationGroup(g,{l/2,0})
            animator.rotateTransformationGroup(g, a)
            animator.translateTransformationGroup(g,world.distance(v,mePos))
            
            local a1 = vec2.angle(world.distance(v, mePos))
            for k2,v2 in next, poly do
              local a2 = vec2.angle(world.distance(v2, mePos))
              local d = math.abs(util.angleDiff(a1,a2))
              if d > gA then
                gA = d
                ga = v
                gb = v2
              end
            end
          end
          local rect = {builder_minPos[1],builder_minPos[2],builder_maxPos[1],builder_maxPos[2]}
          loadRegion(rect)
          local isFirst = true
          for k,v in next, builder_beams do
            animator.resetTransformationGroup(v.part)
            -- work on the current block
            if v.current then
              if isFirst then
                vec2.addToRef(v.current.pos, 0.5, eyeTarget)
              end
              world.debugPoint(v.current.pos, "red")
              local angle = vec2.angle(world.distance(eyeTarget, mePos))
              local l = world.magnitude(eyeTarget, mePos)-0.5
              animator.scaleTransformationGroup(v.part, {l*8,1})
              animator.translateTransformationGroup(v.part,{l/2,0})
              animator.rotateTransformationGroup(v.part, angle)
              if v.current.pos[3] == "liquid" then
                local ll = world.liquidAt(vec2.copyToRef(v.current.pos, vec2working1))
                local l = ll and root.liquidName(ll[1]) or nil
                if l ~= v.current.mat then
                  if not l then
                    animator.setAnimationState(v.part,"deepblue")
                    if world.spawnLiquid(v.current.pos, root.liquidId(v.current.mat), 1) then
                      -- important that this be done immediately
                      builder_blocks[builder_key(v.current.pos[1],v.current.pos[2],v.current.pos[3])] = nil
                      v.current.active = false
                      v.current = nil
                    end
                  else
                    animator.setAnimationState(v.part,"red")
                    world.destroyLiquid(v.current.pos)
                  end
                else
                  builder_blocks[builder_key(v.current.pos[1],v.current.pos[2],v.current.pos[3])] = nil
                  v.current.active = false
                  v.current = nil
                end
              else
                -- is mat
                local mat = world.material(v.current.pos, v.current.pos[3])
                if mat ~= v.current.mat then
                  if not mat and not world.tileIsOccupied(v.current.pos, v.current.pos[3] == "foreground") then
                    animator.setAnimationState(v.part,"green")
                    if not world.placeMaterial(v.current.pos, v.current.pos[3], v.current.mat, v.current.hue or 0, true) then
                      local fgKey = builder_key(v.current.pos[1],v.current.pos[2],"foreground")
                      if v.current.pos[3] == "background" and builder_blocks[fgKey] and builder_blocks[fgKey].mat then
                        v.current.delayUntil = timer+60
                        v.current.active = false
                        v.current = nil
                      elseif v.current.tempObjPos and v.current.pos[3] == "background" then
                        if world.placeMaterial(v.current.pos, "foreground", "blackblock", 0, true) then
                          v.current.tempTile = fgKey
                          builder_blocks[fgKey] = {pos={v.current.pos[1],v.current.pos[2],"foreground"},mat=false,delayUntil=timer+30,expireDelayUntil=timer+120}
                        end
                      elseif not world.tileIsOccupied(v.current.pos, true) then
                        -- trying to place background blocks directly behind this client master object crashes the game, so don't
                        local pos = vec2.addToRef(v.current.pos,{0,1},vec2working1)
                        local k = builder_key(pos[1],pos[2],"foreground")
                        if builder_blocks[k] and builder_blocks[k].active and builder_blocks[k].mat then
                          -- do this later
                          v.current.active = false
                          v.current = nil
                        else
                          if builder_blocks[k] then
                            builder_blocks[k].delayUntil = timer+60
                          end
                          v.current.tempObjPos = pos
                          world.placeObject("invisibleproximitysensor",pos,0,{scripts={"/scripts/abyssbuild/abyssplacehelper.lua"},block=v.current,clientEntityMode="clientMasterAllowed"})
                        end
                      else
                        -- object is obstructed... just do this later
                        v.current.active = false
                        v.current.delayUntil = timer+30
                        v.current = nil
                      end
                    else
                      v.current.active = false
                      v.current = nil
                    end
                  elseif world.replaceMaterials and v.current.mat then
                    animator.setAnimationState(v.part,"green")
                    world.replaceMaterials({v.current.pos}, v.current.pos[3], v.current.mat, v.current.hue or 0, false)
                  else
                    animator.setAnimationState(v.part,"red")
                    world.damageTiles({v.current.pos}, v.current.pos[3], mePos, "beamish", 1000, 0)
                  end
                else
                  animator.setAnimationState(v.part,"off")
                  v.current.active = false
                  v.current = nil
                end
              end
            end
          end
          -- draw lines from eye to the square
          local eoff = vec2.withAngleToRef(vec2.angle(world.distance(eyeTarget, mePos)), math.min(world.magnitude(eyeTarget, mePos)/2, 0.5), vec2working2)
          local epos = vec2.addToRef(mePos, eoff, vec2working1)
          local l = world.magnitude(epos,ga)
          local d = world.distance(ga,epos)
          local a = vec2.angle(d)
          local g = getMiscGroup()
          animator.resetTransformationGroup(g)
          animator.scaleTransformationGroup(g, {l*8,1})
          animator.translateTransformationGroup(g,{l/2,0})
          animator.rotateTransformationGroup(g, a)
          animator.translateTransformationGroup(g,eoff)
          l = world.magnitude(epos,gb)
          d = world.distance(gb,epos)
          a = vec2.angle(d)
          g = getMiscGroup()
          animator.resetTransformationGroup(g)
          animator.scaleTransformationGroup(g, {l*8,1})
          animator.translateTransformationGroup(g,{l/2,0})
          animator.rotateTransformationGroup(g, a)
          animator.translateTransformationGroup(g,eoff)
        else
          animator.setAnimationState("misc", "off")
          for k,v in next, builder_beams do
            animator.setAnimationState(v.part,"off")
            v.current = nil
          end
        end
    end
  }
  attackFuncs={
      ranged=function()
        local targetPosition = overrideTargetingPos or entityPosition(targetId)
        --local targetVel = world.entityVelocity(targetId)
        -- no linear targeting
        vec2.copyToRef(targetPosition, eyeTarget)
        if shootTimer > 20 then
          local angle = vec2.angle(world.distance(targetPosition, mcontroller.position()))
          vec2.addToRef(mcontroller.position(), vec2.withAngleToRef(angle, 0.5, vec2working1), vec2working2)
          world.spawnProjectile("plasmabullet", vec2working2, entity.id(), vec2.withAngleToRef(angle, 2, vec2working1), false, {power=2*root.evalFunction("monsterLevelPowerMultiplier", monster.level()) * status.stat("powerMultiplier"),renderLayer="ForegroundEntity+3",movementSettings={collisionEnabled=false,gravityEnabled=false,liquidFriction=0}})
          abyssParticles.shootParticles(vec2working2, 3, {255, 127, 127, 255})
          shootTimer = 0
          animator.setSoundVolume("projectileFire", 0.5, 0)
          animator.playSound("projectileFire")
        end
        local targetActualPosition = overrideTargetingPos or entityPosition(targetId)
        local angle = vec2.angle(world.distance(mcontroller.position(), targetActualPosition))
        angle = angle + orbitD
        vec2.addToRef(targetActualPosition, vec2.withAngleToRef(angle, orbitDistance, vec2working1), targetPos)
      end,
      melee=function()
        vec2.copyToRef(overrideTargetingPos or entityPosition(targetId), targetPos)
      end,
      heal=function()
        local targetPosition = overrideTargetingPos or entityPosition(targetId)
        local angle = vec2.angle(world.distance(mcontroller.position(), targetPosition))
        local dis = orbitDistance
        vec2.addToRef(targetPosition, vec2.withAngleToRef(angle, dis, vec2working1), targetPos)
        if hasEnergy() and targetId then
          local level = 1
          for k,v in next, world.entityQuery(targetPosition,40,{withoutEntityId=entity.id(),callScript="healMinionTarget",callScriptResult=targetId}) do
            if t == targetId and world.callScriptedEntity(v, "hasEnergy") then
              level = level + 1
            end
          end
          level = math.min(level, 4)
          local rates = {60,50,40,30,10}
          world.sendEntityMessage(targetId, "applyStatusEffect", string.format("shipregeneration%.0f",level), 1, entity.id())
          world.sendEntityMessage(targetId, "applyStatusEffect", string.format("shipregeneration%.0f",level+1), 1, entity.id())
          local toTarget = vec2.normToRef(world.distance(targetPosition, mcontroller.position()), vec2working1)
          abyssParticles.targetedHealParticles(vec2.addToRef(mcontroller.position(), vec2.mulToRef(toTarget,0.5, vec2working2), vec2working1), targetPosition, 3, 1)
          local hp = world.entityHealth(targetId)
          -- find total HP being healed per tick
          local e = hp[2] / rates[level] / 60 + hp[2] / rates[level+1] / 60
          -- divide it based on how many minions are healing (split energy load among multiple healers)
          e = e/level
          -- consume it
          status.overConsumeResource("energy",e)
          if os.clock() - targetLockTime > 20 and hp[1] == targetStartingHealth then
            table.insert(targetBlacklist, targetId)
          elseif hp[1] ~= targetStartingHealth then
            targetLockTime = os.clock()
          end
        end
      end,
      shield=function(dt)
        if targetId == entity.id() then
          return
        end
        local targetPosition = overrideTargetingPos or entityPosition(targetId)
        local angle = vec2.angle(world.distance(mcontroller.position(), targetPosition))
        local dis = orbitDistance
        vec2.addToRef(targetPosition, vec2.withAngleToRef(angle, dis, vec2working1), targetPos)
        if hasEnergy() and targetId then
          -- TODO
          local l = world.magnitude(targetPosition, mcontroller.position())-0.5
          animator.scaleTransformationGroup("laser", {l*8,1})
          animator.translateTransformationGroup("laser",{l/2,0})
          animator.setAnimationState("laser","magenta")
          animator.rotateTransformationGroup("laser", angle+math.pi)
          
          local e = status.stat("maxEnergy")*dt*0.25
          -- heal target shields by this amount
          world.sendEntityMessage(targetId, "abyss_addShield", e*0.75)
          
          -- consume it
          status.overConsumeResource("energy",e)
        else
          animator.setAnimationState("laser","off")
        end
      end,
      analysis=function()
        local targetPosition = overrideTargetingPos or entityPosition(targetId)
        local angle = vec2.angle(world.distance(mcontroller.position(), targetPosition))
        local dis = orbitDistance
        vec2.addToRef(targetPosition, vec2.withAngleToRef(angle, dis, vec2working1), targetPos)
        local text = ""
        if targetId then
          local entityData
          if world.entity then
            entityData = world.entity(targetId)
          end
          if world.entityCanDamage(entity.id(), targetId) then
            world.sendEntityMessage(targetId, "applyStatusEffect", "l6doomed", 1, entity.id())
          end
          local descBase = sanitizeString(world.entityDescription(targetId))
          local descCurrent = ""
          local desc
          local isFirst = true
          for v in string.gmatch(descBase,"([^ ]+)") do
            if not isFirst then
              descCurrent = descCurrent.." "
            end
            isFirst = false
            descCurrent = descCurrent..v
            if string.len(descCurrent) > 100 then
              if desc then
                desc = desc.."\n"..descCurrent
              else
                desc = descCurrent
              end
              descCurrent = ""
              isFirst = true
            end
          end
          if string.len(descCurrent) > 0 and desc then
            desc = desc.."\n"..descCurrent
          else
            desc = descCurrent
          end
          text = "Name: "..sanitizeString(world.entityName(targetId)).."^reset;\nDescription: "..desc.."^reset;"
          local etype = world.entityType(targetId)
          if etype == "monster" or etype == "npc" then
            text = text.."\nType: "..world.entityTypeName(targetId)
          end
          if isSameMaster(entity.id(), targetId) then
            text = text.."\nSame Master"
          end
          local relation = "^#ffff00;Neutral^reset;"
          if not world.entityCanDamage(entity.id(), targetId) then
            relation = "^#00ff00;Ally^reset;"
          elseif entity.isValidTarget(targetId) then
            relation = "^#ff0000;Enemy^reset;"
          end
          text = string.format("%s\nRelation: %s", text, relation)
          text = string.format("%s\nHealth: %.1f/%.1f",text,table.unpack(world.entityHealth(targetId)))
          if entityData then
            for k,v in next, analyzerReadResources do
              if entityData:isResource(v.name) then
                local val = entityData:resource(v.name)
                local m = entityData:resourceMax(v.name)
                if v.perc then
                  val = val*100
                  if m then
                    m = m*100
                  end
                end
                local nSuff = v.perc and "%" or ""
                if v.noVal and val ~= 0 then
                  text = string.format("%s\n%s", text, v.displayName)
                elseif m and m ~= 0 then
                  text = string.format("%s\n%s: %.1f%s/%.1f%s", text, v.displayName, val,nSuff, m,nSuff)
                elseif val ~= 0 then
                  text = string.format("%s\n%s: %.1f%s", text, v.displayName, val,nSuff)
                end
              end
            end
            for k,v in next, analyzerReadStats do
              local stat = entityData:stat(v.name)
              if stat ~= 0 and (not v.noVal or stat > 0) then
                if v.perc then
                  stat = stat*100
                end
                if v.noVal then
                  text = string.format("%s\n%s", text, v.displayName)
                else
                  text = string.format("%s\n%s: %.1f%s", text, v.displayName, stat, v.perc and "%" or "")
                end
              end
            end
          end
        else
          text = "There's nothing here."
        end
        local particleConfig = {
            type = "text",
            size = 0.5,
            text = text,
            color = {0, 255, 255, 255},
            light = {0, 0, 0},
            initialVelocity = {0.0, 0.0},
            finalVelocity = {0.0, 0.0},
            approach = {0, 0},
            timeToLive = dt*2,
            layer = "front",
            flippable = false
        }
        world.spawnProjectile("invisibleprojectile", vec2.addToRef(targetPosition, {9, 4}, vec2working1), entity.id(), {0,0}, false, {
            damageTeam = {type="ghostly"},
            movementSettings={collisionEnabled=false},
            periodicActions={{
                action="particle",
                time=0,
                ["repeat"]=false,
                rotate=false,
                specification=particleConfig
            }},
            timeToLive=0.1,
            speed=0
        })
      end,
      bomb=function()
        -- bomber
        local targetPosition = overrideTargetingPos or entityPosition(targetId)
        local targetVel = overrideTargetVel or world.entityVelocity(targetId)
        local bombTime = 1
        if vec2.mag(targetVel) > 4 then
          -- place bombs in front of target
          vec2.addToRef(targetPosition, vec2.mulToRef(targetVel, bombTime, vec2working1), targetPos)
        else
          -- place bombs in circle
          local angle = vec2.angle(world.distance(mcontroller.position(), targetPosition))
          angle = angle + orbitD
          vec2.addToRef(targetPosition, vec2.withAngleToRef(angle, 7, vec2working1), targetPos)
        end
        if shootTimer > 30 then
          spawnBomb(mcontroller.position())
          shootTimer = 0
        end
      end,
      ranged2=function()
        -- ranged 2 (blue)
        local targetPosition = overrideTargetingPos or entityPosition(targetId)
        local targetVel = overrideTargetVel or world.entityVelocity(targetId)
        -- linear targeting with slower bullet
        local precision = 10
        local projSpeed = 25
        local tick = 1
        while (projSpeed * tick) / precision < world.magnitude(mcontroller.position(), targetPosition) do
            tick = tick + 1
            vec2.addToRef(targetPosition, vec2.divToRef(targetVel, precision, vec2working1), targetPosition)
            if tick > 50 then -- prevent an infinite loop (for example, from something moving away from this at a speed faster than a projectile)
                break
            end
        end
        vec2.copyToRef(targetPosition,eyeTarget)
        if shootTimer > 15 then
          local angle = vec2.angle(world.distance(targetPosition, mcontroller.position()))
          vec2.addToRef(mcontroller.position(), vec2.withAngleToRef(angle, 0.5, vec2working2), vec2working1)
          world.spawnProjectile("lightpellet", vec2working1, entity.id(), vec2.withAngleToRef(angle, 2, vec2working2), false, {power=3*root.evalFunction("monsterLevelPowerMultiplier", monster.level()) * status.stat("powerMultiplier"),renderLayer="ForegroundEntity+3",movementSettings={collisionEnabled=false,gravityEnabled=false,liquidFriction=0}})
          abyssParticles.shootParticles(vec2working1, 4, {127, 198, 255, 255})
          shootTimer = 0
          animator.setSoundVolume("projectileFire2", 0.75, 0)
          animator.playSound("projectileFire2")
        end
        local targetActualPosition = overrideTargetingPos or entityPosition(targetId)
        local angle = vec2.angle(world.distance(mcontroller.position(), targetActualPosition))
        angle = angle + orbitD
        vec2.addToRef(targetActualPosition, vec2.withAngleToRef(angle, orbitDistance, vec2working1), targetPos)
      end,
      sniper=function()
        -- sniper (red, with laser)
        local targetPosition = overrideTargetingPos or entityPosition(targetId)
        local targetVel = overrideTargetVel or world.entityVelocity(targetId)
        -- linear targeting with faster bullet
        local precision = 50
        local projSpeed = 125
        local tick = 1
        while (projSpeed * tick) / precision < world.magnitude(mcontroller.position(), targetPosition) do
            tick = tick + 1
            vec2.addToRef(targetPosition, vec2.divToRef(targetVel, precision, vec2working1), targetPosition)
            if tick > 100 then -- prevent an infinite loop (for example, from something moving away from this at a speed faster than a projectile)
                break
            end
        end
        vec2.copyToRef(targetPosition,eyeTarget)
        if shootTimer > 30 then
          local angle = vec2.angle(world.distance(targetPosition, mcontroller.position()))
          local l = world.magnitude(targetPosition, mcontroller.position())-0.5
          animator.scaleTransformationGroup("laser", {l*8,1})
          animator.translateTransformationGroup("laser",{l/2,0})
          animator.setAnimationState("laser","red")
          animator.rotateTransformationGroup("laser", angle)
          if shootTimer > 60 then
            vec2.addToRef(mcontroller.position(), vec2.withAngleToRef(angle, 0.5, vec2working2), vec2working1)
            world.spawnProjectile("plasmabullet", vec2working1, entity.id(), vec2.withAngleToRef(angle, 2, vec2working2), false, {speed=125,power=12*root.evalFunction("monsterLevelPowerMultiplier", monster.level()) * status.stat("powerMultiplier"),renderLayer="ForegroundEntity+3",movementSettings={collisionEnabled=false,gravityEnabled=false,liquidFriction=0}})
            abyssParticles.shootParticles(vec2working1, 15, {255, 127, 127, 255})
            shootTimer = 0
            animator.setSoundVolume("projectileFire3", 0.75, 0)
            animator.playSound("projectileFire3")
          end
        else
          animator.setAnimationState("laser","off")
        end
        local targetActualPosition = overrideTargetingPos or entityPosition(targetId)
        local angle = vec2.angle(world.distance(mcontroller.position(), targetActualPosition))
        angle = angle + orbitD
        vec2.addToRef(targetActualPosition, vec2.withAngleToRef(angle, orbitDistance, vec2working1), targetPos)
      end
    }
end
function equips()
  dieTimer = 20
end
local healerMinions = {
  shield=true,
  heal=true
}
-- command mode things
function commandable()
  return true
end
function command_enableBars()
  return true
end
require("/scripts/abyssenergysegment_bars.lua")
require("/scripts/abyssshieldablesegment_bars.lua")
local energyUsing = {
  heal=true,
  shield=true
}
function command_energyMax()
  if energyUsing[minionType] then
    return status.resourceMax("energy")
  else
    return nil
  end
end
function command_category()
  local category = "abyssminion"
  if minionType == "builder" then
    category = category.."_builder"
  elseif healerMinions[minionType] then
    category = category.."_support"
  end
  if minionType == "sniper" or minionType == "analysis" then
    category = category.."_unchangeable"
  end
  if anchorParent then
    category = category.."_anchored"
  end
  return category
end
function supportsOrder(t)
  if minionType == "builder" then
    return t == "suicide" or t == "killshield"
  end
  supportedOrders = {attackmove="",patrol="",move="",guard="",change="",attackpos="",suicide="",killshield="",togglepassive="",holdposition=""}
  if anchorParent then
    supportedOrders.move = nil
    supportedOrders.attackmove = nil
    supportedOrders.patrol = nil
    supportedOrders.guard = nil
    supportedOrders.killshield = nil
    supportedOrders.holdposition = nil
  end
  if minionType == "sniper" then
    supportedOrders.change = nil
  end
  if minionType == "analysis" then
    supportedOrders.change = nil
  end
  if healerMinions[minionType] then
    supportedOrders.heal = ""
  else
    supportedOrders.attack = ""
  end
  return supportedOrders[t]
end
function clearOrders()
  orders = {}
  overrideTargetPos = nil
  overrideTargetId = nil
  overrideHealId = nil
  overrideTargetingPos = nil
  follow = true
  followId = coreId
  maxTargetRangeFromCore = defaultRangeFromCore()
end
function order(otype, target, targettype, okind)
  if supportsOrder(otype) then
    table.insert(orders, {type=otype, target=target, targettype=targettype, repeating=okind.repeating})
  end
end
function generateLineDrawable(s, t) -- does not fill in all the data
    return {position={s[1],s[2]},line={{0,0}, world.distance(t, s)}}
end

function drawOrders(orderTypes, ownerPos)
  local function worldToLocal(pos)
    return world.distance(pos, ownerPos)
  end
  local output = {}
  local lastTargetPosition = entity.position()
  if #orders >= 2 then
    if orders[1].repeating then
      if type(orders[#orders].target) == "table" then
        lastTargetPosition = orders[#orders].target
      end
    end
  end
  for k,v in next, orders do
    if type(v.target) == "table" then
      -- position target
      local line = generateLineDrawable(worldToLocal(lastTargetPosition), worldToLocal(v.target))
      line.color = orderTypes[v.type].lineColour
      line.width = 1.0
      line.fullbright = true
      table.insert(output, line)
      lastTargetPosition = v.target
    elseif type(v.target) == "number" then
      -- entity target
      if world.entityExists(v.target) then
        local line = generateLineDrawable(worldToLocal(lastTargetPosition), worldToLocal(world.entityPosition(v.target)))
        line.color = orderTypes[v.type].lineColour
        line.width = 1.0
        line.fullbright = true
        table.insert(output, line)
        lastTargetPosition = world.entityPosition(v.target)
      end
    else
      -- no target
      local poly = {{1,1},{1,-1},{-1,-1},{-1,1}}
      local pos = worldToLocal(lastTargetPosition)
      for k,v2 in next, poly do
        local line = generateLineDrawable(vec2.addToRef(pos, v2, vec2working1), vec2.addToRef(pos, poly[k+1] or poly[1], vec2working2))
        line.color = orderTypes[v.type].lineColour
        line.width = 1.0
        line.fullbright = true
        table.insert(output, line)
      end
    end
  end
  if targetId and world.entityExists(targetId) then
    local line = generateLineDrawable(worldToLocal(entity.position()), worldToLocal(entityPosition(targetId)))
    line.color = {255,255,255}
    line.width = 1.0
    line.fullbright = true
    table.insert(output, line)
  end
  return {out=output,endPos=lastTargetPosition}
end
function updateOrders()
  local current = orders[1]
  if current then
    -- fast movement
    approachSpeed = 2
    maxSpeed = 50
    movementDecel = 0.99
    maxTargetRangeFromCore = defaultRangeFromCore()
    local done = false
    local improveCorners = false
    local mePos = mcontroller.position()
    overrideTargetPos = nil
    overrideTargetId = nil
    overrideHealId = nil
    overrideTargetingPos = nil
    follow = true
    followId = coreId
    if current.type == "move" or current.type == "holdposition" then
      follow = false
      overrideTargetPos = current.target
      done = world.magnitude(mePos, current.target) < 1
      improveCorners = true
      maxTargetRangeFromCore = 1/0
    end
    if current.type == "suicide" then
      status.setResourcePercentage("health",0)
    end
    if current.type == "killshield" then
      if status.resourcePositive("shieldHealth") then
        shieldBreakEffects()
      end
      status.setResourcePercentage("shieldHealth",0)
      done = true
    end
    if current.type == "togglepassive" then
      passiveMode = not passiveMode
      done = true
    end
    if current.type == "attackmove" or current.type == "patrol" then
      follow = false
      vec2.copyToRef(current.target, targetPos)
      done = world.magnitude(mePos, current.target) < 1
      improveCorners = true
      maxTargetRangeFromCore = 1/0
    end
    if current.type == "guard" then
      done = not world.entityExists(current.target)
      if not done then
        followId = current.target
      end
    end
    if current.type == "change" then
      local nexts = {
        ranged="melee",
        melee="heal",
        heal="bomb",
        bomb="ranged2",
        ranged2="shield",
        shield="ranged",
        sniper="ranged",
        analysis="analysis",
        builder="builder"
      }
      minionType = nexts[minionType]
      done = true
    end
    if current.type == "attack" then
      done = not world.entityExists(current.target)
      if not done then
        overrideTargetId = current.target
      end
    end
    if current.type == "attackpos" then
      if not rotCheck(current.target) then
        overrideTargetingPos = current.target
      end
    end
    if current.type == "heal" then
      done = not world.entityExists(current.target)
      if not done then
        overrideHealId = current.target
      end
    end
    if done then
      table.remove(orders, 1)
      if current.type == "patrol" or current.type == "holdposition" then
        table.insert(orders, current)
      end
      if #orders == 0 then
        clearOrders()
      end
    end
    if improveCorners then -- move orders only
      if world.magnitude(mePos, current.target) < 5 then
        movementDecel = 0.9
      end
    end
  end
end
function updateAnchorPos(n)
  anchorPos = n
end
local workingAnchorPos = {0,0}
function getAnchorPos()
  if not anchorParent then -- if not anchored, then there's no anchor position
    return nil
  elseif type(anchorPos) == "table" then -- is anchorPos a vector? use it as an offset to parent
    return vec2.rotateToRef(
          anchorPos, 
          world.callScriptedEntity(anchorRotParent or anchorParent, "getRotation") or 0,
          workingAnchorPos
        )
  else -- otherwise give it back to the parent to use as an index
    return world.callScriptedEntity(anchorRotParent or anchorParent, "getMinionAnchorPos", anchorPos)
  end
end
function rotCheck(target)
  return anchorRotLimit and math.abs(
    util.angleDiff(
      math.pi+vec2.angle(
        getAnchorPos()), 
      vec2.angle(
        world.distance(
          world.entityPosition(anchorParent), 
          target
    )))) > anchorRotLimit
end
function validTarget(target)
    if healerMinions[minionType] then
      if not target then
          return false
      elseif not world.entityExists(target) then
          return false
      elseif rotCheck(world.entityPosition(target)) then
          return false
      elseif target == overrideHealId then
          return true
      elseif passiveMode then
          return false
      elseif world.entityCanDamage(entity.id(),target) then
          return false
      else
        local typeCond = false
        if minionType == "heal" then
          local health = world.entityHealth(target)
          typeCond = health[1] < health[2]
        elseif minionType == "shield" then
          typeCond = isEntityShieldable(target)
        end
        if not typeCond then
            return false
        elseif world.magnitude(mcontroller.position(), world.entityPosition(target)) > maxTargetRange then
            return false
        elseif world.magnitude(world.entityPosition(followId), world.entityPosition(target)) > maxTargetRangeFromCore then
            return false
        elseif table.find(targetBlacklist, target) then
            return false
        elseif minionType == "heal" and 
        (isSameMaster(entity.id(), target) and world.entityType(target) == "monster" and world.callScriptedEntity(target, "noHeal")) then
            return false
        end
      end
      return true
    elseif minionType ~= "builder" then
      if not target then
          return false
      elseif not world.entityExists(target) then
          return false
      elseif rotCheck(world.entityPosition(target)) then
          return false
      elseif target == overrideTargetId then
          return true
      elseif passiveMode then
          return false
      elseif not entity.isValidTarget(target) then
          return false
      elseif world.getProperty("nonCombat") then
          return false
      elseif world.magnitude(mcontroller.position(), world.entityPosition(target)) > maxTargetRange then
          return false
      elseif world.magnitude(world.entityPosition(followId), world.entityPosition(target)) > maxTargetRangeFromCore then
          return false
      end
      return true
    else
      return false
    end
end
function updateMinions(minions)
  -- just keeping this here so old code doesn't break
end
function attackTarget(target)
  overrideTargetId = target
end
function followTarget(target)
  followId = target
  if not target then
    followId = coreId
  end
end
function getMinionType()
  return minionType
end
function isSameMaster(id1, id2)
  if (id1 >= 0) == (id2 >= 0) then
    if id1 >= 0 and id2 >= 0 then
      return true
    elseif math.floor(id1 / 65536) == math.floor(id2 / 65536) then
      return true
    else
      return false
    end
  end
  return false
end
function isMinion()
  return true
end
local passiveTargetId
function targeting()
  if overrideTargetId and world.entityExists(overrideTargetId) and not rotCheck(world.entityPosition(overrideTargetId)) then
    targetId = overrideTargetId
    return
  end
  if overrideHealId and world.entityExists(overrideHealId) and not rotCheck(world.entityPosition(overrideHealId)) then
    targetId = overrideHealId
    return
  end
  if not validTarget(targetId) then
    targetId = nil
  end
  targetQueryTimer = targetQueryTimer + 1
  if targetQueryTimer > targetQueryInterval and not targetId then
    targetQueryTimer = 0
    passiveTargetId = nil
    local targets = world.entityQuery(mcontroller.position(), minTargetRange, {includedTypes={"creature"},order="nearest",withoutEntityId=entity.id()})
    for k,v in next, targets do
      if validTarget(v) then
        targetId = v
        break
      end
    end
    if not targetId then
      for k,v in next, targets do
        if not isSameMaster(entity.id(), v) and world.magnitude(mcontroller.position(), world.entityPosition(v)) < 30 then
          if not rotCheck(world.entityPosition(v)) then
            passiveTargetId = v
            break
          end
        end
      end
    end
  end
end
local info = {}
local hasInfo = false
function infoKey(e)
  return string.format("e_%d",e)
end
function isEntityShieldable(e)
  return info[infoKey(e)] and info[infoKey(e)].shieldable
end
local messageQueryTypes = {
  shield=true
}
local messageQueryTimer = 0
function doMessageChecks()
  if not messageQueryTypes[minionType] then
    if hasInfo then
      info = {}
      hasInfo = false
    end
    return
  end
  hasInfo = true
  for k,v in next, info do
    if not world.entityExists(v.entity) then
      info[k] = nil
    else
      if v.shieldPromise and v.shieldPromise:finished() then
        if v.shieldPromise:succeeded() and v.shieldPromise:result() then
          v.shieldable = true
        else
          v.shieldable = false
        end
        v.shieldPromise = nil
      end
    end
  end
  
  messageQueryTimer = messageQueryTimer + 1
  if messageQueryTimer > 5 then
    messageQueryTimer = 0
    local entities = world.entityQuery(mcontroller.position(), minTargetRange, {includedTypes={"creature"},order="nearest",withoutEntityId=entity.id()})
    for k,v in next, entities do
      local infoEntry = info[infoKey(v)]
      if not infoEntry then
        infoEntry = {
          entity=v
        }
        info[infoKey(v)] = infoEntry
      end
      if not infoEntry.shieldPromise then
        infoEntry.shieldPromise = world.sendEntityMessage(v,"abyss_shieldable")
      end
    end
  end
end
function healMinionTarget()
  if minionType == "heal" then
    return targetId
  else
    return nil
  end
end
function hasEnergy()
  return status.consumeResource("energy", 0)
end
function spawnBomb(pos)
  world.spawnProjectile("fireplasmagrenade", pos, entity.id(), {0, 0}, false, {
    speed=0, movementSettings={collisionEnabled=false,gravityEnabled=false}, timeToLive=1, damagePoly = {}, damageTeam={type="passive"}, actionOnReap={{action="projectile",type="fireplasmagrenade",config={speed=0,movementSettings={collisionEnabled=false,gravityEnabled=false},timeToLive=0,damageTeam=entity.damageTeam(),power=4*root.evalFunction("monsterLevelPowerMultiplier", monster.level()) * status.stat("powerMultiplier")}}}
  })
  animator.playSound("projectileSpawn")
end
function setMinionType(t)
  minionType = t
end
function getSize()
  return 1
end
local lastShieldHit = 0
function shieldBreakEffects()
  animator.playSound("breakShield")
  abyssParticles.shieldParticles(mcontroller.position(), 2, 4, 30)
end
function shieldCreateEffects()
  animator.playSound("activateShield")
  abyssParticles.shieldParticles(mcontroller.position(), 2, 4, 30)
  lastShieldHit = world.time()
end
function shieldHit()
  lastShieldHit = world.time()
end
function updatePosition(p)
  local anchorPos = getAnchorPos()
  mcontroller.setPosition(vec2.addToRef(p, anchorPos, vec2working1))
  mcontroller.setVelocity({0,0})
end
function update(dt)
  miscGroupI = 0
  if minionType == "heal" or minionType == "shield" then
    overrideTargetId = nil
  end
  math.randomseed(math.floor(os.clock()*10000))
  if not world.entityExists(followId) then
    followId = coreId
  end
  local red = math.max(math.min(math.sin(os.clock()*3+colourTimeOffset)*127, 127), 0)
  local classC = math.max(math.min(math.sin(os.clock()*-1.5+colourTimeOffset)*127, 127) + 128, 0)
  local colour = string.format("^#%02x0000;", math.floor(red))
  if minionType == "ranged" then
    eyeState = "idle"
    eyeAnimState = "idle"
    monster.setName(colour.."Abyssal "..string.format("^#%02x0000;", math.floor(classC)).."Blaster"..colour.." Minion^reset;")
  end
  if minionType == "melee" then
    eyeState = "purple"
    eyeAnimState = "purple"
    monster.setName(colour.."Abyssal "..string.format("^#%02x00%02x;", math.floor(classC/2), math.floor(classC)).."Warrior"..colour.." Minion^reset;")
  end
  if minionType == "heal" then
    eyeState = "green"
    eyeAnimState = "green"
    monster.setName(colour.."Abyssal "..string.format("^#00%02x00;", math.floor(classC)).."Healer"..colour.." Minion^reset;")
  end
  if minionType == "bomb" then
    eyeState = "yellow"
    eyeAnimState = "yellow"
    monster.setName(colour.."Abyssal "..string.format("^#%02x%02x00;", math.floor(classC), math.floor(classC)).."Bomber"..colour.." Minion^reset;")
  end
  if minionType == "ranged2" then
    eyeState = "blue"
    eyeAnimState = "blue"
    monster.setName(colour.."Abyssal "..string.format("^#00%02x%02x;", math.floor(classC/2), math.floor(classC)).."Swarmer"..colour.." Minion^reset;")
  end
  if minionType == "shield" then
    eyeState = "magenta"
    eyeAnimState = "magenta"
    monster.setName(colour.."Abyssal "..string.format("^#%02x00%02x;", math.floor(classC), math.floor(classC)).."Shielder"..colour.." Minion^reset;")
  end
  if minionType == "sniper" then
    eyeState = "idle"
    eyeAnimState = "idle"
    monster.setName(colour.."Abyssal "..string.format("^#%02x0000;", math.floor(classC)).."Sniper"..colour.." Minion^reset;")
    minTargetRange = 150
    maxTargetRange = 200
  else
    minTargetRange = 50
    maxTargetRange = 70
  end
  if minionType == "analysis" then
    eyeState = "aqua"
    eyeAnimState = "aqua"
    monster.setName(colour.."Abyssal "..string.format("^#00%02x%02x;", math.floor(classC), math.floor(classC)).."Analyzer"..colour.." Minion^reset;")
  end
  if minionType == "builder" then
    eyeState = "deepblue"
    eyeAnimState = "deepblue"
    monster.setName(colour.."Abyssal "..string.format("^#0000%02x;", math.floor(classC), math.floor(classC)).."Builder"..colour.." Minion^reset;")
  end
  monster.setDisplayNametag(getNameVis())
  orbitDFlipTimer = orbitDFlipTimer - 1
  if orbitDFlipTimer <= 0 then
    orbitDFlipTimer = 1000*math.random()
    orbitD = orbitD * -1
  end
  dieTimer = dieTimer - 1
  r = r + math.pi/30*spinDir
  if dieTimer < 0 then
    status.setResourcePercentage("health", 0)
    return
  end  
    if not world.entityExists(coreId) then
        status.setResourcePercentage("health", 0)
        return
    elseif anchorParent and not world.entityExists(anchorParent) then
        status.setResourcePercentage("health", 0)
        return
    elseif anchorRotParent and not world.entityExists(anchorRotParent) then
        status.setResourcePercentage("health", 0)
        return
    else
      monster.setDamageTeam(world.entityDamageTeam(ownerId))
    end
  doMessageChecks()
  updateOrders()
  targeting()
  if targetId ~= lastTargetId then
    if targetId then
      targetStartingHealth = world.entityHealth(targetId)[1]
    else
      targetStartingHealth = nil
    end
    lastTargetId = targetId
    targetLockTime = os.clock()
  end
  local anchorRotPos = getAnchorPos()
  if (targetId or overrideTargetingPos) then
    vec2.copyToRef(overrideTargetingPos or entityPosition(targetId),eyeTarget)
  elseif passiveTargetId and world.entityExists(passiveTargetId) then
    vec2.copyToRef(world.entityPosition(passiveTargetId),eyeTarget)
  else
    if anchorParent then
      if anchorRotPos then
        vec2.addToRef(world.entityPosition(anchorParent), vec2.mulToRef(anchorRotPos,2,vec2working1),eyeTarget)
      end
    else
      vec2.copyToRef(world.entityPosition(followId),eyeTarget)
    end
  end
  --[[local closeEyeScale = 1
  if closeEyeTimer > 0 then
    closeEyeTimer = closeEyeTimer - 1
    closeEyeScale = 0.1
  end]]
  monster.setDamageOnTouch(true)
  animator.resetTransformationGroup("body")
  --eyeScale = math.max(1, eyeScale - 0.05)
  animator.resetTransformationGroup("core")
  animator.rotateTransformationGroup("core", r)
  animator.resetTransformationGroup("shield")
  animator.rotateTransformationGroup("shield", r*-1.25)
  if status.resourcePositive("shieldHealth") then
    animator.setAnimationState("shield","on")
    animator.setGlobalTag("shieldDirectives",string.format("?fade=ffffff=%.5f",1-math.min(4*(world.time()-lastShieldHit),1)))
  else
    animator.setAnimationState("shield","off")
  end
  shootTimer = shootTimer + 1
  if minionType == "sniper" and not (targetId or overrideTargetingPos) and shootTimer > 30 then
    shootTimer = 30
  end
  animator.resetTransformationGroup("laser")
  if not (targetId or overrideTargetingPos) then
    animator.setAnimationState("laser", "off")
  end
  isPassiveIdle = true
  if passiveFuncs[minionType] then
    passiveFuncs[minionType]()
  end
  if targetId or overrideTargetingPos then
    approachSpeed = 2
    maxSpeed = 50
    movementDecel = 0.99
    overrideTargetVel = nil
    if overrideTargetingPos then
      overrideTargetVel = zeroVec
    end
    attackFuncs[minionType](dt)
  elseif follow and isPassiveIdle then
    local corePos = world.entityPosition(followId)
    world.debugLine(mcontroller.position(), corePos, "yellow")
    if world.magnitude(corePos, mcontroller.position()) > 12 then
      hasPassiveTargetPos = true
      approachSpeed = 2
      movementDecel = 0.99
      maxSpeed = 50
      if world.magnitude(corePos, mcontroller.position()) > 24 then
        approachSpeed = 3
        maxSpeed = 70
      end
      targetPos = corePos
    else
      approachSpeed = 0.25
      maxSpeed = 50
      movementDecel = 0.98
      if hasPassiveTargetPos and world.magnitude(corePos, passiveTargetPos) > 11 then
        hasPassiveTargetPos = false
      end
      if hasPassiveTargetPos and world.magnitude(mcontroller.position(), passiveTargetPos) < 0.75 then
        hasPassiveTargetPos = false
      end
      if not hasPassiveTargetPos then
        local angle = vec2.angle(world.distance(mcontroller.position(), corePos))+orbitD*math.random()*30
        local dis = 3+5*math.random()
        vec2.addToRef(corePos, vec2.withAngleToRef(angle, dis, vec2working1),passiveTargetPos)
        hasPassiveTargetPos = true
      end
      targetPos = passiveTargetPos
    end
  end
  if stateColours[eyeState] then
    eyeAnimState = eyeState
  end
  animator.resetTransformationGroup("eye")
  --animator.scaleTransformationGroup("eye", {eyeScale,eyeScale*closeEyeScale})
  if eyeTarget then
    world.debugLine(mcontroller.position(), eyeTarget, "green")
    local angle = vec2.angle(world.distance(eyeTarget, mcontroller.position()))
    animator.translateTransformationGroup("eye", vec2.withAngleToRef(angle, math.min(world.magnitude(eyeTarget, mcontroller.position())/2, 0.5), vec2working1))
    animator.setLightActive("eye", true)
    animator.setLightPointAngle("eye", angle/math.pi*180)
  else
    animator.setLightActive("eye", false)
  end
  if eyeAnimState ~= lastEyeAnimState then
    animator.setAnimationState("eye", eyeAnimState)
    animator.setLightColor("glow", vec3.mul(stateColours[eyeAnimState], 2/3))
    animator.setLightColor("eye", stateColours[eyeAnimState])
    lastEyeAnimState = eyeAnimState
  end
  if overrideTargetPos then
    vec2.copyToRef(overrideTargetPos, targetPos)
  end
  if not anchorParent then
    move()
    physics()
  else
    local pos = world.entityPosition(anchorParent)
    if anchorRotPos then
      mcontroller.setPosition(vec2.addToRef(pos, anchorRotPos, vec2working1))
    end
    mcontroller.setVelocity({0,0})
    status.setStatusProperty("noShield",true)
    local mode = world.sendEntityMessage(anchorRotParent or anchorParent, "anchoredMinionDamageMode"):result()
    if mode == "redirect" then
      status.setStatusProperty("headId", anchorRotParent or anchorParent)
      status.setStatusProperty("head2Id", nil)
      status.setStatusProperty("noFlash",true)
    elseif mode == "redirectandtake" then
      status.setStatusProperty("headId", nil)
      status.setStatusProperty("head2Id", anchorRotParent or anchorParent)
      status.setStatusProperty("noFlash",false)
    elseif mode == "take" then
      status.setStatusProperty("headId", nil)
      status.setStatusProperty("head2Id", nil)
      status.setStatusProperty("noFlash",false)
    elseif mode == "default" then
      status.setStatusProperty("headId", nil)
      status.setStatusProperty("head2Id", trueOwnerId or ownerId)
      status.setStatusProperty("noFlash",false)
    end
  end
  --local c = stateColours[eyeAnimState]
  --mtrails[1].color = {c[1],c[2],c[3],255}
  --trail.update(mtrails,0.5)
  abyssParticles.execute()
end
function abyss_isPhysics()
  return not anchorParent
end
function move()
    world.debugLine(mcontroller.position(), targetPos, "red")
    local decel = movementDecel
    --if world.magnitude(targetPos, mcontroller.position()) < 0.1 and preciseMove then
    --  decel = 0
    --end
    vec2.normToRef(world.distance(targetPos, mcontroller.position()), vec2working1)
    local toTarget = vec2.mulToRef(vec2working1,approachSpeed,vec2working2)
    mcontroller.setVelocity(vec2.add(vec2.mul(mcontroller.velocity(), decel), toTarget))
    if vec2.mag(mcontroller.velocity(), {0, 0}) > maxSpeed then
        local new = vec2.mulToRef(vec2.normToRef(mcontroller.velocity(), vec2working1), maxSpeed, vec2working1)
        mcontroller.setVelocity(new)
    end
end

function interact(args)
end

function shouldDie()
    return (self.shouldDie and status.resource("health") <= 0)
end

function die()
    if world.entityExists(ownerId) and config.getParameter("incMaxOnKill", true) and dieTimer >= 0 then
      world.sendEntityMessage(ownerId, "incMaxMinions")
    end
end
