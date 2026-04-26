require "/scripts/terra_vec2ref.lua"
require "/scripts/terra_vec3.lua"
require "/scripts/terra_renderutil.lua"
require "/scripts/poly.lua"

-- RTS-like command interface.
-- The key to toggle, providing of controls, and disabling of controls/tool usage should be handled by whatever tech uses this.
-- Providing of localAnimator bindings are also handled by whatever uses this. If they are not provided, the command interface will default to using one from a metatable.
-- I do not recommend relying on this. Use terra_proxy to provide it localAnimator binds that are guaranteed to be from the correct entity.
-- Order kinds and displayed bars are in the config.
--[[
Orders:
"listPos" - where in the order list this is. Is a number.
"targetingType" - what type of target this is.
    Can be:
    "entity" - targets entity
    "position" - targets a position
    "rect" - targets a rect, requires dragging
    "none" - order has no target, cursor position is meaningless when ordering
if targeting type is entity:
    "allowNoTarget" - if true, can give targetless orders if no entity is under cursor when giving this order
    "targetingMode" - some other stuff
        Can be:
        null - doesn't have any extra targeting logic
        "container" - only targets container objects
        "fuser" - only targets Abyssal Holders or things that act like them
        "itemRecipient" - can target players, containers, or client master entities that indicate that they are item recipients
    "validTargetTypes" - what entities this order can target, accepts entity query-only types like "mobile" and "creature" as well
If targeting type is position or rect:
    "aligned" - if the position or rect should be aligned with grid
"lineColour" - the colour of this order when drawn after being ordered
"image" - the icon of this order in the interface
"repeating" - this order is marked as repeating when ordered
"unuseable" - this order cannot be ordered and works differently
"modes" - what modes of this order exist? if this key is present, selecting this order will lead to a modes menu
- modes are stored similarly to orders, key is name, value is object with properties
    "listPos" - where in mode order this is, is a number
    "image" - icon, also shown shrunk down in corner of order
]]

--[[
Implementation:
command.init() - not actually for running under init, run this when enabling command mode
command.update(args) - run on every frame when command mode is active, argument is the same object that's provided to tech update
command.togglePause() - just a toggle you can use at any time
command.uninit() - run when disabling command mode

I usually have a single key for toggling command mode, where holding Shift (run being false) toggles pause, not holding Shift toggles command mode itself.
]]

command = {}
local selected = {}
local unitCategories = {}
local currentOrder = "move"
local currentOrderMode = nil
local selectingMode = false
local selectingMode_order = "move"
local orderListWidth = 4
local orders
local ordersArr
local playersOnly = false
local lastSpecial2 = false
local lastSpecial3 = false
local dragOrderTarget = nil
local primaryHoldTime = 0
local defaultRadius = 1.5
local selectCircleSegments = 12
local selectCircleRadius = 0.5
local selectCircleHoverColour = {0,0,255}
local selectCircleColour = {0,127,255}
local selectCircleIncompatibleColour = {0,0,127}
local barCircleSegments = 24
local barCircleBaseRadius = 0.5
local barCircleThickness = 4
local barCircleRadiusAdd = 0.5
local bars
local selectBeginPos
local orderSelectModePos = nil
function table.find(org, findValue)
    for key,value in pairs(org) do
        if value == findValue then
            return key
        end
    end
    return nil
end
function generateLineDrawable(s, t) -- does not fill in all the data
    return {position=s,line={{0,0}, world.distance(t, s)}}
end
function makePolyDrawables(poly, colour, width, fullbright)
    if not width then width = 1.0 end
    if not colour then colour = {255,255,255} end
    if fullbright == nil then fullbright = true end
    local output = {}
    for k,v in next, poly do
        local n = poly[k+1] or poly[1]
        local line = generateLineDrawable(v,n)
        line.color = colour
        line.width = width
        line.fullbright = fullbright
        table.insert(output, line)
    end
    return output
end
function command.init()
    lastSpecial2 = false
    lastSpecial3 = false
end
function worldToLocal(pos)
    return world.distance(pos, mcontroller.position())
end
function worldToLocalPoly(poly)
    local newpoly = {}
    for k,v in next, poly do
        table.insert(newpoly, worldToLocal(v))
    end
    return newpoly
end
local ordersPaused = false
local queuedOrders = {}
function executeSendOrder(e,order,target,targettype)
    local okind = orders[order]
    for k,v in next, e do
        if world.entityExists(v) then
            local ver = world.callScriptedEntity(v, "command_version")
            if not ver then
                world.callScriptedEntity(v, "order",order,target,targettype,okind)
            else
                world.callScriptedEntity(v, "order",{type=order,target=target,targettype=targettype,repeating=okind.repeating,mode=currentOrderMode},okind)
            end
        end
    end
end
function sendOrder(e, order, target,targettype)
    if type(e) == "number" then
        e = {e}
    end
    if ordersPaused then
        table.insert(queuedOrders, {entities=e,order=order,target=target,targettype=targettype})
    else
        executeSendOrder(e,order,target,targettype)
    end
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
local function getLocalAnimator()
    return localAnimator or getmetatable''.localAnimator
end
local function orderModeName(o,m)
    return string.format("%s_%s",o,m)
end
local function ensureCategory(e)
    local category = world.callScriptedEntity(e,"command_category") or string.format("e_%d",e)
    if not unitCategories[category] then
        unitCategories[category] = {
            supportedOrders={},
            present=true,
            selected=false
        }
        for k,v in next, orders do
            if world.callScriptedEntity(e,"supportsOrder",k) then
                local o = true
                if v.modes then
                    o = {}
                    for k2,v2 in next, v.modes do
                        local n = orderModeName(k,k2)
                        if world.callScriptedEntity(e,"supportsOrder",n) then
                            table.insert(o,k2)
                        end
                    end
                end
                unitCategories[category].supportedOrders[k] = o
            end
        end
    end
    return category
end
local commandConfig
local lastAlt = false
local lastPrimary = false
local orderStateUpdateTimer = 0
function command.update(args)
    local localAnimator = getLocalAnimator()
    if not localAnimator then
        return
    end
    if args.moves.special2 ~= lastSpecial2 then
        if args.moves.special2 then
            if orderSelectModePos then
                orderSelectModePos = nil
            else
                orderSelectModePos = world.distance(tech.aimPosition(), mcontroller.position())
                selectingMode = false
            end
        end
        lastSpecial2 = args.moves.special2
    end
    
    if not commandConfig then
        commandConfig = root.assetJson("/abysscommand.config")
    end
    if not orders then
        orders = commandConfig.orders
        ordersArr = {}
        for k,v in next, orders do
            v.name = k
            table.insert(ordersArr, v)
            if v.modes then
                v.modesArr = {}
                for k2,v2 in next, v.modes do
                    v2.name = k2
                    table.insert(v.modesArr,v2)
                end
                table.sort(v.modesArr, function(a,b)
                    return a.listPos < b.listPos
                end)
            end
        end
        table.sort(ordersArr, function(a,b)
            return a.listPos < b.listPos
        end)
    end
    if not bars then
        bars = commandConfig.bars
    end
    orderStateUpdateTimer = orderStateUpdateTimer + 1
    if orderStateUpdateTimer > 1 then
        orderStateUpdateTimer = 0
        for k,v in next, unitCategories do
            v.present = false
            v.selected = false
        end
        for k,v in next, orders do
            v._enabled = false
            v._visible = false
            if v.modes then
                for k2,v2 in next, v.modes do
                    v._enabled = false
                end
            end
        end
        local screenRect = world.clientWindow()
        local margin = 20
        local es = world.entityQuery({screenRect[1]-margin,screenRect[2]-margin},{screenRect[3]+margin,screenRect[4]+margin},{
            includedTypes={"creature","vehicle"},order="nearest",callScript="commandable"
        })
        for k,v in next, es do
            local category = ensureCategory(v)
            unitCategories[category].present = true
        end
        for k,v in next, selected do
            if world.entityExists(v) then
                local category = ensureCategory(v)
                unitCategories[category].present = true
                unitCategories[category].selected = true
            end
        end
        for k,v in next, unitCategories do
            if v.present then
                for k2,v2 in next, v.supportedOrders do
                    orders[k2]._visible = true
                end
            end
            if v.selected then
                for k2,v2 in next, v.supportedOrders do
                    orders[k2]._enabled = true
                    if orders[k2].modes then
                        for k3,v3 in next,v2 do
                            orders[k2].modes[v3]._enabled = true
                        end
                    end
                end
            end
        end
    end
    if orderSelectModePos then
        local x = 0
        local y = 0
        local iconSpacing = 2.5
        local needModeSelect = false
        if selectingMode then
            local o = orders[selectingMode_order]
            iconSpacing = (o.modeIconSize+2)/8
            local mCell = vec2.floor(vec2.sub(vec2.div(vec2.sub(world.distance(tech.aimPosition(), mcontroller.position()),orderSelectModePos), iconSpacing), {-0.5,-0.5}))
            mCell[2] = mCell[2] * -1
            for k,v in next, o.modesArr do
                local img = v.image
                if mCell[1] == x and mCell[2] == y then
                    img = img.."?saturation=-25?brightness=50"
                    if args.moves.primaryFire and not lastPrimary then
                        currentOrder = selectingMode_order
                        currentOrderMode = v.name
                        dragOrderTarget = nil
                    end
                end
                if #selected > 0 and not v._enabled then
                    img = img.."?multiply=ffffff7f"
                end
                localAnimator.addDrawable({image=img,position=vec2.add(orderSelectModePos, {x*iconSpacing,y*iconSpacing*-1}),fullbright=true},"Overlay+32000")
                x = x + 1
                if x >= orderListWidth then
                    y = y + 1
                    x = 0
                end
            end
        else
            local mCell = vec2.floor(vec2.sub(vec2.div(vec2.sub(world.distance(tech.aimPosition(), mcontroller.position()),orderSelectModePos), iconSpacing), {-0.5,-0.5}))
            mCell[2] = mCell[2] * -1
            for k,v in next, ordersArr do
                if v._visible or v.alwaysVisible then
                    local img = v.image
                    if mCell[1] == x and mCell[2] == y then
                        img = img.."?saturation=-25?brightness=50"
                        if args.moves.primaryFire and not lastPrimary then
                            if v.modes then
                                selectingMode = true
                                selectingMode_order = v.name
                                needModeSelect = true
                            else
                                currentOrder = v.name
                                dragOrderTarget = nil
                                currentOrderMode = nil
                            end
                        end
                    end
                    if #selected > 0 and not v._enabled then
                        img = img.."?multiply=ffffff7f"
                    end
                    localAnimator.addDrawable({image=img,position=vec2.add(orderSelectModePos, {x*iconSpacing,y*iconSpacing*-1}),fullbright=true},"Overlay+32000")
                    x = x + 1
                    if x >= orderListWidth then
                        y = y + 1
                        x = 0
                    end
                end
            end
        end
        if args.moves.primaryFire and not lastPrimary and not needModeSelect then
            selectingMode = false
            orderSelectModePos = nil
            primaryHoldTime = -1
        end
    else
        if args.moves.primaryFire then
            primaryHoldTime = primaryHoldTime + args.dt
            if primaryHoldTime > 0 and not selectBeginPos then
                selectBeginPos = tech.aimPosition()
            end
        elseif primaryHoldTime > 0 then
            if primaryHoldTime > 0.125 then
                -- area select
                if args.moves.run then
                    selected = {}
                end
                local endPos = tech.aimPosition()
                local minPos = {math.min(selectBeginPos[1], endPos[1]),math.min(selectBeginPos[2], endPos[2])}
                local maxPos = {math.max(selectBeginPos[1], endPos[1]),math.max(selectBeginPos[2], endPos[2])}
                local q = world.entityQuery(minPos, maxPos, {includedTypes={"creature","vehicle"},callScript="commandable"})
                for k,v in next, q do
                    if not table.find(selected, v) then
                        table.insert(selected, v)
                    end
                end
            else
                -- select 1
                if args.moves.run then
                    selected = {}
                end
                local toSelect = world.entityQuery(tech.aimPosition(), 2, {includedTypes={"creature","vehicle"},order="nearest",callScript="commandable"})
                local sel = nil
                local selPriority = -math.huge
                for _,v in next, toSelect do
                    local priority = world.callScriptedEntity(v,"command_priority") or 0
                    if selPriority < priority then
                        sel = v
                        selPriority = priority
                    end
                end
                if sel then
                    if not table.find(selected, sel) then
                        table.insert(selected, sel)
                    end
                end
            end
            primaryHoldTime = 0
            selectBeginPos = nil
        else
            primaryHoldTime = 0
        end
        if primaryHoldTime > 1/12 then
            local endPos = tech.aimPosition()
            local poly = {selectBeginPos, {selectBeginPos[1],endPos[2]}, endPos, {endPos[1],selectBeginPos[2]}}
            local polyLines = makePolyDrawables(worldToLocalPoly(poly),{255,255,255},1.0,true)
            for k,v in next, polyLines do
                localAnimator.addDrawable(v,"Overlay+32005")
            end
        end
        local orderImgPos = {5,5}
        if world.magnitude(tech.aimPosition(), mcontroller.position()) > 40 then
            orderImgPos = vec2.add(world.distance(tech.aimPosition(),mcontroller.position()),{2.5,2.5})
        end
        local co = orders[currentOrder]
        local img = co.image
        if ordersPaused then
            img = img.."?multiply=ffffff7f"
        end
        localAnimator.addDrawable({image=img,position=orderImgPos,fullbright=true},"Overlay+32000")
        if co.modes then
            local mimg = co.modes[currentOrderMode].image
            if ordersPaused then
                mimg = mimg.."?multiply=ffffff7f"
            end
            localAnimator.addDrawable({image=mimg,position=orderImgPos,fullbright=true,transformation=
            {
            {0.5,0,  -0.75},
            {0,  0.5,-0.75},
            {0,  0,   1}
            }},"Overlay+32001")
        end
        if playersOnly then
            local imgPos = {-5,5}
            if world.magnitude(tech.aimPosition(), mcontroller.position()) > 40 then
                imgPos = vec2.add(world.distance(tech.aimPosition(),mcontroller.position()),{-2.5,2.5})
            end
            localAnimator.addDrawable({image="/ab_commandmode/player.png",position=imgPos,fullbright=true},"Overlay+32000")
        end
        local newSelected = {}
        for k,v in next, selected do
            if world.entityExists(v) then
                table.insert(newSelected, v)
                local colour = selectCircleColour
                local supported = true
                local coName = currentOrder
                if co.modes then
                    coName = orderModeName(currentOrder,currentOrderMode)
                end
                if not world.callScriptedEntity(v, "supportsOrder", coName) then
                    colour = selectCircleIncompatibleColour
                    supported = false
                end
                local radius = (world.callScriptedEntity(v,"command_radius") or defaultRadius) + selectCircleRadius
                local epos = worldToLocal(world.entityPosition(v))
                local aoffset = os.clock()*math.pi+(math.pi/4)*k
                for i=1,selectCircleSegments do
                    local p1 = vec2.add(epos, vec2.withAngle(math.pi*2/selectCircleSegments*(i-1)+aoffset, radius))
                    local p2 = vec2.add(epos, vec2.withAngle(math.pi*2/selectCircleSegments*i+aoffset, radius))
                    local line = generateLineDrawable(p1, p2)
                    line.color = colour
                    line.fullbright = true
                    line.width = 1.0
                    localAnimator.addDrawable(line,"Overlay+32001")
                end
                --[[
                local polyd = {}
                local drawable = {
                    position=epos,
                    poly=polyd,
                    color=colour,
                    fullbright=true
                }
                for i=0,selectCircleSegments do
                    local p = vec2.withAngle(math.pi*2/selectCircleSegments*i+aoffset, radius-0.5)
                    table.insert(polyd,p)
                end
                for i=selectCircleSegments,0,-1 do
                    local p = vec2.withAngle(math.pi*2/selectCircleSegments*i+aoffset, radius+0.5)
                    table.insert(polyd,p)
                end
                world.debugPoly(poly.translate(polyd,mcontroller.position()),"red")
                localAnimator.addDrawable(drawable,"Overlay+32001")
                ]]
                if world.callScriptedEntity(v,"command_enableBars") and #selected <= 3 then
                    local radius = radius + barCircleBaseRadius
                    for _,bar in next, bars do
                        local val
                        local max
                        local colour = bar.colour
                        if bar.isHealth then
                            if world.entityType(v) ~= "vehicle" then
                                local h = world.entityHealth(v)
                                val = h[1]
                                max = h[2]
                            else
                                val = world.callScriptedEntity(v,"command_health")
                                max = world.callScriptedEntity(v,"command_healthMax")
                            end
                        else
                            max = world.callScriptedEntity(v,bar.maxFunc)
                            if max and max > 0 then
                                val = world.callScriptedEntity(v,bar.valFunc)
                                local locked = false
                                if bar.lockedColour then
                                    locked = world.callScriptedEntity(v,bar.lockedFunc)
                                    if locked then
                                        colour = bar.lockedColour
                                    end
                                end
                                if not locked then
                                    if bar.regenDelayColour then
                                        local perc = world.callScriptedEntity(v,bar.regenDelayFunc) or 0
                                        if perc > 0 then
                                            if bar.rgbLerp then
                                                colour = vec3.lerp(perc, bar.colour, bar.regenDelayColour)
                                            else
                                                colour = renderutil.mixRGB(bar.colour,bar.regenDelayColour,perc,1)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        if max and max > 0 then
                            local perc = val/max
                            local off = math.pi/2
                            for i=1,barCircleSegments do
                                local p1 = vec2.add(epos, vec2.withAngle(math.pi*2/barCircleSegments*(i-1)*perc+off, radius))
                                local p2 = vec2.add(epos, vec2.withAngle(math.pi*2/barCircleSegments*i*perc+off, radius))
                                local line = generateLineDrawable(p1, p2)
                                line.color = colour
                                line.fullbright = true
                                line.width = barCircleThickness
                                localAnimator.addDrawable(line,"Overlay+32001")
                            end
                            radius = radius + barCircleRadiusAdd
                        end
                    end
                end
                if world.callScriptedEntity(v,"command_isPassive") then
                    localAnimator.addDrawable({image="/ab_commandmode/passive.png?multiply=ffffff7f",position=epos,fullbright=true},"Overlay+32001")
                end
                local d = world.callScriptedEntity(v, "drawOrders", orders, entity.position())
                local orderLines = d.out
                local lastPos = d.endPos
                if ordersPaused then
                    for k,v2 in next, queuedOrders do
                        local has = false
                        for k,v3 in next, v2.entities do
                            if v3 == v then
                                has = true
                                break
                            end
                        end
                        if has then
                            local colour = {orders[v2.order].lineColour[1],orders[v2.order].lineColour[2],orders[v2.order].lineColour[3],127}
                            if type(v2.target) == "table" then
                                -- position target
                                local line = generateLineDrawable(worldToLocal(lastPos), worldToLocal(v2.target))
                                line.color = colour
                                line.width = 1.0
                                line.fullbright = true
                                table.insert(orderLines, line)
                                lastPos = v2.target
                            elseif type(v2.target) == "number" then
                                -- entity target
                                if world.entityExists(v2.target) then
                                    local line = generateLineDrawable(worldToLocal(lastPos), worldToLocal(world.entityPosition(v2.target)))
                                    line.color = colour
                                    line.width = 1.0
                                    line.fullbright = true
                                    table.insert(orderLines, line)
                                    lastPos = world.entityPosition(v2.target)
                                end
                            else
                                -- no target
                                local poly = {{1,1},{1,-1},{-1,-1},{-1,1}}
                                local pos = worldToLocal(lastPos)
                                for k,v3 in next, poly do
                                    local line = generateLineDrawable(vec2.add(pos, v3), vec2.add(pos, poly[k+1] or poly[1]))
                                    line.color = colour
                                    line.width = 1.0
                                    line.fullbright = true
                                    table.insert(orderLines, line)
                                end
                            end
                        end
                    end
                end
                for k,v2 in next, orderLines do
                    localAnimator.addDrawable(v2,"Overlay+32002")
                end
                if co.updateFunc and supported then
                    for k,v2 in next, world.callScriptedEntity(v, co.updateFunc, entity.position(), tech.aimPosition(), args.moves, currentOrderMode) do
                        localAnimator.addDrawable(v2,"Overlay+32002")
                    end
                end
            end
        end
        if args.moves.altFire ~= lastAlt then
            if args.moves.altFire and co.targetingType == "rect" then
                dragOrderTarget = tech.aimPosition()
                if co.aligned then
                    dragOrderTarget = vec2.floor(dragOrderTarget)
                end
            elseif (args.moves.altFire or co.targetingType == "rect") and not co.unuseable then
                local target = tech.aimPosition()
                if co.aligned then
                    target = vec2.floor(target)
                end
                local targetType = "position"
                if co.targetingType == "rect" then
                    targetType = "rect"
                    if dragOrderTarget then
                        target = {dragOrderTarget[1],dragOrderTarget[2],target[1],target[2]}
                    else
                        target = nil
                    end
                elseif co.targetingType == "entity" then
                    if co.targetingMode == "itemRecipient" then
                        local targets = world.entityQuery(tech.aimPosition(), 2, {includedTypes=playersOnly and {"player"} or co.validTargetTypes,order="nearest"})
                        target = nil
                        targetType = "entity"
                        for k,v in next, targets do
                            if world.entityType(v) == "player" or (world.entityType(v) == "monster" and isSameMaster(v,entity.id()) and world.callScriptedEntity(v,"isItemRecipient")) or (world.entityType(v) == "object" and world.containerSize(v)) then
                                target = v
                                break
                            end
                        end
                    elseif co.targetingMode == "fuser" then
                        target = world.monsterQuery(tech.aimPosition(), 2, {callScript="isHolder",order="nearest"})[1]
                        targetType = "entity"
                    elseif co.targetingMode == "container" then
                        local targets = world.objectQuery(tech.aimPosition(), 2, {order="nearest"})
                        target = nil
                        targetType = "entity"
                        for k,v in next, targets do
                            if world.containerSize(v) then
                                target = v
                                break
                            end
                        end
                    else
                        target = world.entityQuery(tech.aimPosition(), 2, {includedTypes=playersOnly and {"player"} or co.validTargetTypes,order="nearest"})[1]
                        targetType = "entity"
                    end
                end
                if co.targetingType == "none" then
                    target = nil
                end
                if not target then
                    targetType = "none"
                end
                dragOrderTarget = nil
                if target or co.targetingType == "none" or co.allowNoTarget then
                    for k,v in next, selected do
                        if args.moves.run then
                            world.callScriptedEntity(v, "clearOrders")
                        end
                    end
                    sendOrder(selected, currentOrder, target, targetType)
                    --[[
                    -- TODO: update
                    local coreId = getmetatable''.coreId
                    if coreId and world.entityExists(coreId) then
                        world.callScriptedEntity(coreId, "orderAnim")
                    end
                    ]]
                end
            end
            lastAlt = args.moves.altFire
        end
        if dragOrderTarget then
            local endPos = tech.aimPosition()
            local poly
            if co.aligned then
                endPos = vec2.floor(endPos)
                world.debugPoint(dragOrderTarget,"white")
                world.debugPoint(endPos,"white")
                local mi = {math.min(dragOrderTarget[1],endPos[1]),math.min(dragOrderTarget[2],endPos[2])}
                local ma = {math.max(dragOrderTarget[1],endPos[1])+1,math.max(dragOrderTarget[2],endPos[2])+1}
                world.debugPoint(mi,"cyan")
                world.debugPoint(ma,"cyan")
                poly = {{mi[1],mi[2]}, {mi[1],ma[2]}, {ma[1],ma[2]}, {ma[1],mi[2]}}
            else
                poly = {dragOrderTarget, {dragOrderTarget[1],endPos[2]}, endPos, {endPos[1],dragOrderTarget[2]}}
            end
            local polyLines = makePolyDrawables(worldToLocalPoly(poly),co.lineColour,1.0,true)
            for k,v in next, polyLines do
                localAnimator.addDrawable(v,"Overlay+32005")
            end
        end
        if args.moves.special3 ~= lastSpecial3 then
            if args.moves.special3 then
                if args.moves.run then
                    for k,v in next, selected do
                        world.callScriptedEntity(v, "clearOrders")
                    end
                    queuedOrders = {}
                    --[[
                    -- TODO: update
                    local coreId = getmetatable''.coreId
                    if coreId and world.entityExists(coreId) then
                        world.callScriptedEntity(coreId, "orderAnim")
                    end
                    ]]
                else
                    playersOnly = not playersOnly
                end
            end
            lastSpecial3 = args.moves.special3
        end
        selected = newSelected
    end
    lastPrimary = args.moves.primaryFire
end
function command.togglePause()
    if ordersPaused then
        ordersPaused = false
        for k,v in next, queuedOrders do
            executeSendOrder(v.entities, v.order, v.target,v.targettype)
        end
        queuedOrders = {}
    else
        ordersPaused = true
    end
end
function command.uninit()
    if ordersPaused then
        command.togglePause()
    end
    selected = {}
end
