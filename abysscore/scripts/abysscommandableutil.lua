require "/scripts/terra_vec2ref.lua"

-- make sure to call updateOrders in your update

local vec2working1 = {0,0}
local vec2working2 = {0,0}

-- order functions, provided the same argument as updateOrders_execute, key is ordertypes
orderFuncs = {}
orderCancelFuncs = {}

-- example:
--[[
orderFuncs = {
    move=function(current)
      follow = false
      overrideTargetPos = current.target
      improveCorners = true
      maxTargetRangeFromCore = 1/0
      return world.magnitude(mePos, current.target) < 1
    end
}
]]


-- order data structure:
--[[
  type: the kind of order this is
  target: what this is targeting
  targettype: what kind of thing this is targeting
  repeating: if this order repeats (is readded to order queue after completion)
  mode: this order's mode
]]

-- note: most of my code still doesn't use this
-- this'll just make life easier tho

function updateOrders_reset()
    -- reset variables here, runs before an order is executed
end

-- enable if this has bars to show
-- see abyss minions for how this might be used
-- healthbar can also be overridden for vehicles but I'll leave that to you to figure out
function command_enableBars()
  return false
end
-- REPLACE THIS!
-- The category returned here should account for all order combinations returned by supportsOrder. Should make some things faster.
-- If nil, command will fall back to just using the entity ID for a category, which can leak as the categories are never cleaned up
function command_category()
  return nil
end
function supportsOrder(t)
  -- replace this, example:
  --local supportedOrders = {attackmove="",patrol="",move="",guard="",change="",attackpos="",suicide="",killshield="",togglepassive="",holdposition="",addminion="",addminion_sniper=""}
  --return supportedOrders[t]
  return false
end

-- asthetic, change to represent your size
function command_radius()
  return 1
end

-- if clicking a position, higher numbered entities will be prioritized over lower numbered entities
function command_priority()
  return 0
end

-- if you have a passive mode triggered by togglepassive, override this
function command_isPassive()
  return false
end

-- example updateFunc, this one's used by config
-- returns an array of drawables, should be able to do pretty much whatever you want
-- this one only necessary and called if config order is specified as supported
-- note: drawables are done using owner localAnimator, use worldToLocal to transform them correctly
-- same applies with drawOrders_extra
-- you can also use this to draw, say, structure position previews
function updateConfig(ownerPos, aimPos, moves, currentOrderMode)
    local function worldToLocal(pos)
        return world.distance(pos, ownerPos)
    end
    return {}
end

function command_fullReset()
  -- possibly reset other data when orders are cancelled
  -- probably not necessary but minions do something like this
end

function drawOrders_extra(orderTypes,ownerPos,worldToLocal,output)
  --[[if targetId and world.entityExists(targetId) then
    local line = generateLineDrawable(worldToLocal(entity.position()), worldToLocal(entityPosition(targetId)))
    line.color = {255,255,255}
    line.width = 1.0
    line.fullbright = true
    table.insert(output, line)
  end]]
end
function updateOrders_execute(current)
    -- can be overridden to handle orders a bit differently, or left as it is
    -- (most of my existing code just implements this as a bunch of if statements)
    local func = orderFuncs[current.type]
    if not func then
        -- order not defined, just terminate immediately
        return true
    end
    return func(current)
end

-- other stuff that doesn't need to be touched
orders = {}
function commandable()
  return true
end
function command_version()
  return 1
end
function clearOrders()
  local first = orders[1]
  if first and orderCancelFuncs[first.type] then
    orderCancelFuncs[first.type](first)
  end
  orderChanged(nil)
  orders = {}
  command_fullReset()
end
function order(order, okind)
  local typeStr
  if order.mode then
    typeStr = string.format("%s_%s",order.type,order.mode)
  else
    typeStr = order.type
  end
  if supportsOrder(typeStr) then
    if #orders == 0 then
      orderChanged(order)
    end
    table.insert(orders, order)
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
      if orders[#orders].targettype == "position" then
        lastTargetPosition = orders[#orders].target
      end
    end
  end
  for k,v in next, orders do
    if v.targettype == "position" then
      -- position target
      local line = generateLineDrawable(worldToLocal(lastTargetPosition), worldToLocal(v.target))
      line.color = orderTypes[v.type].lineColour
      line.width = 1.0
      line.fullbright = true
      table.insert(output, line)
      lastTargetPosition = v.target
    elseif v.targettype == "entity" then
      -- entity target
      if world.entityExists(v.target) then
        local line = generateLineDrawable(worldToLocal(lastTargetPosition), worldToLocal(world.entityPosition(v.target)))
        line.color = orderTypes[v.type].lineColour
        line.width = 1.0
        line.fullbright = true
        table.insert(output, line)
        lastTargetPosition = world.entityPosition(v.target)
      end
    elseif v.targettype == "rect" then
      -- rect target
      local function worldToLocalPoly(poly)
          local newpoly = {}
          for k,v in next, poly do
              table.insert(newpoly, worldToLocal(v))
          end
          return newpoly
      end
      local poly
      if orderTypes[v.type].aligned then
        local mi = {math.min(v.target[1],v.target[3]),  math.min(v.target[2],v.target[4])  }
        local ma = {math.max(v.target[1],v.target[3])+1,math.max(v.target[2],v.target[4])+1}
        poly = worldToLocalPoly({{mi[1],mi[2]}, {mi[1],ma[2]}, {ma[1],ma[2]}, {ma[1],mi[2]}})
      else
        poly = worldToLocalPoly({{v.target[1],v.target[2]}, {v.target[1],v.target[4]}, {v.target[3],v.target[4]}, {v.target[3],v.target[2]}})
      end
      local total = {0,0}
      local ref = worldToLocal(v.target)
      for k2,v2 in next, poly do
          vec2.addToRef(total,vec2.sub(v2,ref),total)
          local n = poly[k2+1] or poly[1]
          local line = generateLineDrawable(v2,n)
          line.color = orderTypes[v.type].lineColour
          line.width = 1.0
          line.fullbright = true
          table.insert(output, line)
      end
      local center = vec2.add(v.target,vec2.div(total,#poly))
      local line = generateLineDrawable(worldToLocal(lastTargetPosition), worldToLocal(center))
      line.color = orderTypes[v.type].lineColour
      line.width = 1.0
      line.fullbright = true
      table.insert(output, line)
      lastTargetPosition = center
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
  drawOrders_extra(orderTypes,ownerPos,worldToLocal,output)
  return {out=output,endPos=lastTargetPosition}
end 

function orderChanged(new)

end

-- call this in your update
function updateOrders()
  updateOrders_reset()
  local current = orders[1]
  if current then
    if updateOrders_execute(current) then
      table.remove(orders, 1)
      if current.repeating then
        table.insert(orders, current)
      end
      if #orders == 0 then
        clearOrders()
      elseif orders[1] ~= current then
        orderChanged(orders[1])
      end
    end
  end
end
