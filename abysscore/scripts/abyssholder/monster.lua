require "/scripts/util.lua"
require "/scripts/vec2.lua"
require "/scripts/terra_vec2ref.lua"
require "/scripts/terra_vec3.lua"
require "/scripts/poly.lua"
require "/scripts/status.lua"
require "/scripts/actions/movement.lua"
require "/scripts/actions/animator.lua"
require "/scripts/companions/capturable.lua"
require "/scripts/abyssparticles.lua"
require "/scripts/abyssphysics.lua"
require "/scripts/abyssholder/builder.lua"
require "/scripts/terra_renderutil.lua"

math.randomseed(math.floor(os.clock()*10000))
local initialized
local ownerId
local coreId
local timer = 0
local orders = {}
local zeroVec = {0,0}
local r = 0
local otherMinions = {}
local orbitD = math.pi/60
local orbitDistance = 7+8*math.random()
local orbitDFlipTimer = 120*math.random()
local colourTimeOffset = math.pi*2*math.random()
local vec2working1 = {0,0}
local vec2working2 = {0,0}
local vec2working3 = {0,0}
local vec2working4 = {0,0}
local approachSpeed = 2
local maxSpeed = 50
local movementDecel = 0.99
local targetQueryInterval = 20
local targetQueryTimer = 0
local targetPos
local overrideTargetPos
local followId
local follow = true
local preciseMove = false
local dropped = false
local passiveTargetPos = {0,0}
local attackFuncs
function defaultRangeFromCore()
  return 80
end
local completeItemConfig
local itemBaseScale
local maxStack
local playerId
local function getNameVis()
  return world.sendEntityMessage(playerId,"abyssNameVis"):result()
end
-- Engine callback - called on initialization of entity
function init()
    self.pathing = {}
    self.shouldDie = true
    initialized = false
    ownerId = config.getParameter("ownerId")
    coreId = storage.coreOverrideId or config.getParameter("coreId")
    playerId = config.getParameter("playerId",ownerId)
    status.setStatusProperty("playerId",playerId)
    storage.heldItem = storage.heldItem or config.getParameter("heldItem")
    local itemConfig = root.itemConfig(storage.heldItem)
    completeItemConfig = sb.jsonMerge(itemConfig.config, itemConfig.parameters)
    local itemSize = config.getParameter("itemSize")
    local maxSize = 1.5
    itemBaseScale = maxSize/itemSize
    followId = coreId
    maxStack = completeItemConfig.maxStack or root.assetJson("/items/defaultParameters.config").defaultMaxStack
    minionType = config.getParameter("minionType")
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
  monster.setName("^#7F0000;Abyssal Holder^reset;")
end
-- command mode things
function commandable()
  return true
end
function command_enableBars()
  return true
end
function command_category()
  return "abyssholder"
end
function supportsOrder(t)
  supportedOrders = {patrol="",move="",attackmove="",guard="",merge="",suicide="",killshield="",fuse=""}
  return supportedOrders[t]
end
function clearOrders()
  orders = {}
  overrideTargetPos = nil
  follow = true
  followId = coreId
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
function stackCompatible(i)
  if not root.itemDescriptorsMatch(i,storage.heldItem,true) then
    return false
  end
  if (i.count + storage.heldItem.count) > maxStack then
    return false
  end
  return true
end
function isItemRecipient(i)
  if i then
    return stackCompatible(i)
  else
    return true
  end
end
function getItem()
  return storage.heldItem
end
function giveItem(i)
  if stackCompatible(i) then
    storage.heldItem.count = storage.heldItem.count + i.count
    return true
  end
  return false
end
local fuseFuncs = {
  unknown=function(items,configs)
    return {
      shortdescription="Incomprehensible Blob",
      description="A strange mesh of multiple items.",
      ab_itemType="rottenfood"
    }
  end
}
local fusionIcon = "/assetmissing.png?crop;0;0;1;1?setcolor=fff?replace;fff0=fff?border=1;fff;000?scale=1.15;1.12?crop;1;1;3;3?replace;fbfbfb=0000;eaeaea=10000000;e4e4e4=00001000;6a6a6a=10001000?scale=15.5?crop=0;0;16;16?replace;00000500=110;00000600=110;00000700=110;00000800=010;00000900=010;00000a00=010;01000300=110;01000400=110;01000500=110;01000600=110;01000700=110;01000800=010;01000900=010;01000a00=010;01000b00=010;01000c00=010;02000200=110;02000300=110;02000400=110;02000500=110;02000600=010;02000700=010;02000800=f00;02000900=f00;02000a00=010;02000b00=010;02000c00=010;02000d00=010;03000100=110;03000200=110;03000300=110;03000400=010;03000500=010;03000600=010;03000700=010;03000800=f00;03000900=f00;03000a00=f00;03000b00=f00;03000c00=010;03000d00=010;03000e00=010;04000100=110;04000200=110;04000300=010;04000400=010;04000500=010;04000600=010;04000700=010;04000800=010;04000900=f00;04000a00=f00;04000b00=f00;04000c00=f00;04000d00=010;04000e00=010;05000000=110;05000100=110;05000200=110;05000300=010;05000400=010;05000500=010;05000600=010;05000700=010;05000800=010;05000900=f00;05000a00=f00;05000b00=f00;05000c00=f00;05000d00=010;05000e00=010;05000f00=010;06000000=110;06000100=110;06000200=010;06000300=010;06000400=010;06000500=010;06000600=010;06000700=010;06000800=010;06000900=010;06000a00=f00;06000b00=f00;06000c00=f00;06000d00=f00;06000e00=010;06000f00=010;07000000=110;07000100=110;07000200=010;07000300=010;07000400=010;07000500=010;07000600=010;07000700=010;07000800=010;07000900=010;07000a00=010;07000b00=010;07000c00=f00;07000d00=f00;07000e00=010;07000f00=010;08000000=210;08000100=210;08000200=110;08000300=110;08000400=010;08000500=010;08000600=010;08000700=010;08000800=010;08000900=010;08000a00=010;08000b00=010;08000c00=010;08000d00=010;08000e00=110;08000f00=110;09000000=210;09000100=210;09000200=110;09000300=110;09000400=110;09000500=110;09000600=010;09000700=010;09000800=010;09000900=010;09000a00=010;09000b00=010;09000c00=010;09000d00=010;09000e00=110;09000f00=110;0a000000=210;0a000100=210;0a000200=210;0a000300=110;0a000400=110;0a000500=110;0a000600=110;0a000700=010;0a000800=010;0a000900=010;0a000a00=010;0a000b00=010;0a000c00=010;0a000d00=110;0a000e00=110;0a000f00=110;0b000100=210;0b000200=210;0b000300=110;0b000400=110;0b000500=110;0b000600=110;0b000700=010;0b000800=010;0b000900=010;0b000a00=010;0b000b00=010;0b000c00=010;0b000d00=110;0b000e00=110;0c000100=210;0c000200=210;0c000300=210;0c000400=110;0c000500=110;0c000600=110;0c000700=110;0c000800=010;0c000900=010;0c000a00=010;0c000b00=010;0c000c00=110;0c000d00=110;0c000e00=110;0d000200=210;0d000300=210;0d000400=210;0d000500=210;0d000600=110;0d000700=110;0d000800=010;0d000900=010;0d000a00=110;0d000b00=110;0d000c00=110;0d000d00=110;0e000300=210;0e000400=210;0e000500=210;0e000600=210;0e000700=210;0e000800=110;0e000900=110;0e000a00=110;0e000b00=110;0e000c00=110;0f000500=210;0f000600=210;0f000700=210;0f000800=110;0f000900=110;0f000a00=110?replace;f00=%s;010=%s;110=%s;210=%s"
local fusionIconShades = {
  -- val, sat
  {1,1},
  {0.75,1},
  {0.5,1},
  {0.25,1}
}
-- creates a merged item that may share properties or be utterly useless
local function fuseItems(is)
  local fusedColour = {0,0,0}
  local fusedVal = 0
  local n = 0
  local itemConfigs = {}
  local avgCount = 0
  for k,v in next, is do
    avgCount = avgCount + v.count
    local ic = root.itemConfig(v)
    local icc = sb.jsonMerge(ic.config,ic.parameters)
    if type(icc.inventoryIcon) == "string" then
      if string.sub(icc.inventoryIcon,1,1) ~= "/" then
        icc.inventoryIcon = ic.directory..icc.inventoryIcon
      end
      local palettes = renderutil.scanPalettes(icc.inventoryIcon)
      local colour = {0,0,0}
      local val = 0
      for k,v in next, palettes do
        local brightest = renderutil.toRGB({v.hue,v.saturation,v.brightestV})
        vec3.addToRef(colour,brightest,colour)
        val = val + v.brightestV
      end
      vec3.divToRef(colour,math.max(colour[1],colour[2],colour[3])/255,colour)
      val = val/#palettes
      vec3.mulToRef(colour,val,colour)
      vec3.addToRef(fusedColour,colour,fusedColour)
      n = n + 1
      fusedVal = fusedVal + val
    end
    table.insert(itemConfigs, icc)
  end
  avgCount = avgCount / #is
  vec3.divToRef(fusedColour,math.max(fusedColour[1],fusedColour[2],fusedColour[3])/255,fusedColour)
  fusedVal = fusedVal / n
  vec3.mulToRef(fusedColour,fusedVal,fusedColour)
  sb.logInfo(string.format("Fused item colour determined to be %s (value %.1f)", sb.print(fusedColour), fusedVal))
  local ftype
  for k,v in next, is do
    if ftype then
      if ftype ~= root.itemType(v.name) then
        ftype = "unknown"
        break
      end
    else
      ftype = root.itemType(v.name)
    end
  end
  if not fuseFuncs[ftype] then
    ftype = "unknown"
  end
  local params = fuseFuncs[ftype](is,itemConfigs)
  local fCHSV = renderutil.toHSV(fusedColour)
  local shades = {}
  for k,v in next, fusionIconShades do
    local c = renderutil.toRGB({fCHSV[1],fCHSV[2]*v[2],fCHSV[3]*v[1]})
    table.insert(shades,renderutil.toHexColour(c))
  end
  params.inventoryIcon = string.format(fusionIcon,table.unpack(shades))
  params.ab_fusionSources=is
  
  return {name=params.ab_itemType,count=avgCount,parameters=params}
end
function fuseItemWith(i)
  local i1 = {i}
  if i.parameters.ab_fusionSources then
    i1 = i.parameters.ab_fusionSources
  end
  local i2 = {storage.heldItem}
  if storage.heldItem.parameters.ab_fusionSources then
    i1 = storage.heldItem.parameters.ab_fusionSources
  end
  for k,v in next, i2 do
    table.insert(i1, v)
  end
  local ni = fuseItems(i1)
  -- spawn holder with this new item
  local params = buildHolder(ni,ownerId,coreId)
  local minionId = world.spawnMonster("mechmultidrone", pos or mcontroller.position(), params)
  world.sendEntityMessage(coreId, "abyssAddHolder", minionId)
  dropped = true
  status.setResourcePercentage("health",0)
end
function isHolder()
  return true
end
local physicsEnabled = true
function isPhysics()
  return physicsEnabled
end
function updateOrders()
  local current = orders[1]
  physicsEnabled = true
  if current then
    -- fast movement
    approachSpeed = 2
    maxSpeed = 50
    movementDecel = 0.99
    local done = false
    local improveCorners = false
    local mePos = mcontroller.position()
    overrideTargetPos = nil
    follow = true
    followId = coreId
    if current.type == "move" then
      follow = false
      overrideTargetPos = current.target
      done = world.magnitude(mePos, current.target) < 1
      improveCorners = true
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
    if current.type == "attackmove" or current.type == "patrol" then
      follow = false
      vec2.copyToRef(current.target, targetPos)
      done = world.magnitude(mePos, current.target) < 1
      improveCorners = true
    end
    if current.type == "guard" then
      done = not world.entityExists(current.target)
      if not done then
        followId = current.target
      end
    end
    if current.type == "merge" then
      done = (current.target == entity.id()) or not world.entityExists(current.target)
      if not done then
        if world.entityType(current.target) == "monster" and not world.callScriptedEntity(current.target, "isItemRecipient",storage.heldItem) then
          done = true
        elseif world.entityType(current.target) == "object" then
          local fit = world.containerItemsCanFit(current.target, storage.heldItem)
          if fit and fit >= storage.heldItem.count then
          else
            done = true
          end
        end
      end
      if not done then
        follow = false
        improveCorners = true
        overrideTargetPos = world.entityPosition(current.target)
        if world.magnitude(mePos, overrideTargetPos) < 4 then
          physicsEnabled = false
        end
        if world.magnitude(mePos, overrideTargetPos) < 1 then
          done = true
          if world.entityType(current.target) == "monster" and world.callScriptedEntity(current.target, "isItemRecipient") then
            if world.callScriptedEntity(current.target,"giveItem",storage.heldItem) then
              dropped = true
              status.setResourcePercentage("health",0)
            end
          elseif world.entityType(current.target) == "object" then
            world.containerAddItems(current.target, storage.heldItem)
            dropped = true
            status.setResourcePercentage("health",0)
          elseif current.target == playerId and world.sendEntityMessage(current.target,"player.giveItem",storage.heldItem):succeeded() then
            
            dropped = true
            status.setResourcePercentage("health",0)
          else
            -- allow target to pick up item itself
            mcontroller.setPosition(overrideTargetPos)
            status.setResourcePercentage("health",0)
          end
        end
      end
    end
    if current.type == "fuse" then
      done = (current.target == entity.id()) or not world.entityExists(current.target)
      if not done then
        follow = false
        improveCorners = true
        overrideTargetPos = world.entityPosition(current.target)
        if world.magnitude(mePos, overrideTargetPos) < 4 then
          physicsEnabled = false
        end
        if world.magnitude(mePos, overrideTargetPos) < 1 then
          done = true
          if world.entityType(current.target) == "monster" and world.callScriptedEntity(current.target, "isHolder") then
            world.callScriptedEntity(current.target,"fuseItemWith",storage.heldItem)
            dropped = true
            status.setResourcePercentage("health",0)
          end
        end
      end
    end
    if done then
      table.remove(orders, 1)
      if current.type == "patrol" then
        table.insert(orders, current)
      end
      if #orders == 0 then
        clearOrders()
      end
    end
    if improveCorners then
      if world.magnitude(mePos, overrideTargetPos or targetPos) < 5 then
        movementDecel = 0.9
      end
    end
  end
end
function updateMinions(minions)
  otherMinions = minions
end
function isMinion()
  return true
end
function getSize()
  return 1
end
require("/scripts/abyssshieldablesegment_bars.lua")
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

function update(dt)
  math.randomseed(math.floor(os.clock()*10000))
  animator.resetTransformationGroup("item")
  local scale = itemBaseScale*0.5 + (storage.heldItem.count/maxStack)*0.5
  animator.scaleTransformationGroup("item",scale)
  if not world.entityExists(coreId) then
    coreId = ownerId
    storage.coreOverrideId = ownerId
    world.sendEntityMessage(ownerId, "abyssAddHolder", entity.id())
  end
  if not world.entityExists(followId) then
    followId = coreId
  end
  local red = math.max(math.min(math.sin(os.clock()*3+colourTimeOffset)*127, 127), 0)
  local colour = string.format("^#%02x0000;", math.floor(red))
  local itemName = completeItemConfig.shortdescription or "^red;Unknown Item"
  monster.setName(string.format("%sAbyssal ^reset;%s^reset; %sHolder^reset;", colour, itemName, colour))
  monster.setDisplayNametag(getNameVis())
  orbitDFlipTimer = orbitDFlipTimer - 1
  if orbitDFlipTimer <= 0 then
    orbitDFlipTimer = 1000*math.random()
    orbitD = orbitD * -1
  end
  r = r + math.pi/30
  if not world.entityExists(ownerId) then
      status.setResourcePercentage("health", 0)
      return
  else
    monster.setDamageTeam(world.entityDamageTeam(ownerId))
  end
  updateOrders()
  monster.setDamageOnTouch(true)
  animator.resetTransformationGroup("body")
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
  if follow then
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
  if overrideTargetPos then
    vec2.copyToRef(overrideTargetPos, targetPos)
  end
  move()
  if physicsEnabled then
    physics(otherMinions)
  end
  abyssParticles.execute()
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
    return (self.shouldDie and status.resource("health") <= 0) or capturable.justCaptured
end

function die()
  if not dropped then
    dropped = true
    world.spawnItem(storage.heldItem, mcontroller.position())
  end
end
function setHealth(health)
    lastHealth = health
    status.setResourcePercentage("health", health)
end
