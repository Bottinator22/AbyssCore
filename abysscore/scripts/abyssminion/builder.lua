
local vec2working1 = {0,0}
local vec2working2 = {0,0}
local vec2working3 = {0,0}
local vec2working4 = {0,0}

local builder_minPos
local builder_maxPos
local builder_blocks
local builder_timer = 0
local timer = 0
function builder_key(x,y,layer)
  return string.format("x%.0fy%.0fl%s",x,y,layer)
end
local function absoluteImage(img,directory)
    if string.sub(img,1,1) == "/" then
      return img
    else
      return directory..img
    end
end
local function replaceTags_withDefault(str,tags)
  local o = ""
  local tag
  for c in string.gmatch(str,".") do
    if tag then
      if c == ">" then
          if tags[tag] then
            o = o..tags[tag]
          else
            o = o.."default"
          end
          tag = nil
      else
          tag = tag..c
      end
    else
      if c == "<" then
        tag = ""
      else
        o = o..c
      end
    end
  end
  return o
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
  if layer == "object" then
    if mat then
      local d = root.itemConfig(mat)
      local directory = d.directory
      local cfg = d.config
      local orientations = {}
      for i,o in next, cfg.orientations do
          -- ObjectDatabase does this too
          if o.dualImage then
              o.image = o.dualImage
              o.direction = "right"
              local no = sb.jsonMerge(o)
              no.image = o.dualImage
              no.flipImages = true
              no.direction = "left"
              table.insert(orientations,no)
          elseif o.leftImage then
              o.image = o.rightImage
              o.direction = "right"
              local no = sb.jsonMerge(o)
              no.image = o.leftImage
              no.direction = "left"
              table.insert(orientations,no)
          end
          table.insert(orientations,o)
      end
      local collisionTiles = {}
      local oriChecks = {}
      for i,o in next, orientations do
          if (o.direction or "right") == op.direction or "right" then
              local bgOnly = false
              local spaces = sb.jsonMerge(o.spaces or {{0,0}})
              if o.spaceScan then
                  local imglayers = {}
                  local imgKeys = {color=o.color or "default"}
                  for k,v in next, sb.jsonMerge(cfg.imageKeys or {}, o.imageKeys or {}) do
                    imgKeys[k] = v
                  end
                  if o.imageLayers then
                      for k,v in next, o.imageLayers do
                          table.insert(imglayers, absoluteImage(v.image,directory))
                      end
                  else
                      table.insert(imglayers, absoluteImage(o.image,directory))
                  end
                  for _,l in next, imglayers do
                      for k,v in next, root.imageSpaces(replaceTags_withDefault(l,imgKeys), o.imagePosition or {0,0}, o.spaceScan, o.flipImages) do
                          local key = builder_key(v[1],v[2],"")
                          spaces[key] = v
                      end
                  end
              end
              local bbox = {2^16,2^16,-2^16,-2^16}
              for _,v in next, spaces do
                  if v[1] < bbox[1] then
                      bbox[1] = v[1]
                  end
                  if v[2] < bbox[2] then
                      bbox[2] = v[2]
                  end
                  if v[1] > bbox[3] then
                      bbox[3] = v[1]
                  end
                  if v[2] > bbox[4] then
                      bbox[4] = v[2]
                  end
              end
              -- TODO: anchor material/mod requirements
              local topRight = {-2^16,-2^16} -- not really a top right, just the rightmost of the topmost points
              local fgAnchors = {}
              local bgAnchors = {}
              for k,v in next, sb.jsonMerge(o.fgAnchors or {}) do
                local key = builder_key(v[1],v[2],"")
                fgAnchors[key] = v
              end
              for k,v in next, sb.jsonMerge(o.bgAnchors or {}) do
                local key = builder_key(v[1],v[2],"")
                bgAnchors[key] = v
              end
              local offs = {
                top={0,1,2,4},
                bottom={0,-1,2,2},
                left={-1,0,1,1},
                right={1,0,1,3},
                background={0,0}
              }
              for _,an in next, o.anchors or {} do
                  local amap = fgAnchors
                  local off = offs[an]
                  if an == "background" then
                    amap = bgAnchors
                  end
                  for k,v in next, spaces do
                    if an == "background" or v[off[3]] == bbox[off[4]] then
                      local pos = vec2.add(v,off)
                      local key = builder_key(pos[1],pos[2],"")
                      amap[key] = pos
                    end
                  end
              end
              local checks = {
                spaces={},
                anchors={}
              }
              for k,v in next, spaces do
                local key = builder_key(v[1]+x,v[2]+y,"foreground")
                checks.spaces[key] = {v[1]+x,v[2]+y,"foreground"}
              end
              for k,v in next, fgAnchors do
                local key = builder_key(v[1]+x,v[2]+y,"foreground")
                checks.anchors[key] = {v[1]+x,v[2]+y,"foreground"}
              end
              for k,v in next, bgAnchors do
                local key = builder_key(v[1]+x,v[2]+y,"background")
                checks.anchors[key] = {v[1]+x,v[2]+y,"background"}
              end
              table.insert(oriChecks,checks)
              if o.materialSpaces then
                for k,v in next, o.materialSpaces do
                  if v[2] then
                    local pos = {v[1][1]+x,v[1][2]+y,"foreground"}
                    local key = builder_key(pos[1],pos[2],pos[3])
                    collisionTiles[key] = pos
                  end
                end
              elseif o.collision and o.collision ~= "none" then
                local collisionSpaces = o.collisionSpaces or spaces
                local nonTopSpaces = o.collisionSpaces or o.collision == "solid"
                for k,v in next, collisionSpaces do
                  if nonTopSpaces or v[2] == bbox[4] then
                    local pos = {v[1]+x,v[2]+y,"foreground"}
                    local key = builder_key(pos[1],pos[2],pos[3])
                    collisionTiles[key] = pos
                  end
                end
              end
          end
      end
      local obj = {
        pos={x,y,layer},
        mat=mat,
        active=false,
        spaces=nil,
        orientations=oriChecks,
        direction=op.direction == "left" and -1 or 1,
        params=op
      }
      local spaces = {}
      for k,v in next, collisionTiles do
        if not builder_blocks[k] then
          local sp = {
            pos={v[1],v[2],"objectSpace"},
            object=obj,
            objectKey=key
          }
          spaces[k] = sp
          builder_blocks[k] = sp
        end
      end
      obj.spaces = spaces
      builder_blocks[key] = obj
    else
      builder_blocks[key] = {pos={x,y,layer},mat=nil,active=false}
    end
  elseif layer == "liquid" then
    local id = mat
    if type(mat) == "string" then
      id = root.liquidId(mat)
    end
    builder_blocks[key] = {pos={x,y,layer},mat=id or false,active=false,level=op or 1}
  else
    builder_blocks[key] = {pos={x,y,layer},mat=mat,active=false,hue=(op or dOptions).hue or nil,collisionMode=(op or dOptions).coll or nil,colour=(op or dOptions).colour or nil}
  end
end
function builder_order(from, to, layer, mat)
  for x=from[1],to[1]-1,1 do
    for y=from[2],to[2]-1,1 do
      builder_set(x,y,layer,mat)
    end
  end
end
local placeholderProps = {}
local placeholderPropRow = {}
setmetatable(placeholderPropRow,{__index=function()
    return nil
end})
setmetatable(placeholderProps,{__index=function()
    return placeholderPropRow
end})
-- expects schematic to be decompressed already
-- same format as Support Drone schematic
-- TODO: coroutines for particularly large schematics
function builder_schematic(schem, pos)
  local fgColours = schem.fgColours or placeholderProps
  local bgColours = schem.bgColours or placeholderProps
  local fgHues = schem.fgHues or placeholderProps
  local bgHues = schem.bgHues or placeholderProps
  local fgCollisions = schem.fgCollisions or placeholderProps
  local bgCollisions = schem.bgCollisions or placeholderProps
  local size = schem.size
  for y,r in next,schem.background do
    for x,v in next,r do
      builder_set(pos[1]+x-1,pos[2]-y+1,"background",v,{colour=bgColours[y][x] ~= 0 and bgColours[y][x],hue=bgHues[y][x]/255*360,coll=bgCollisions[y][x]})
    end
  end
  for y,r in next,schem.foreground do
    for x,v in next,r do
      builder_set(pos[1]+x-1,pos[2]-y+1,"foreground",v,{colour=fgColours[y][x] ~= 0 and fgColours[y][x],hue=fgHues[y][x]/255*360,coll=fgCollisions[y][x]})
    end
  end
  for k,v in next, schem.objects do
    builder_set(v.pos[1]+pos[1],v.pos[2]+pos[2],"object",v.type,v.params or {})
  end
  if schem.liquids then
    for y,r in next,schem.liquids do
      for x,v in next,r do
        --builder_set(pos[1]+x-1,pos[2]-y+1,"liquid",v and v[1],v and v[2])
      end
    end
  end
  -- todo: wires (oSB)
end
local otherLayer = {
  foreground="background",
  background="foreground"
}
miscGroupI = 0
local miscGroups = {
  "misc1",
  "misc2",
  "misc3",
  "misc4",
  "misc5",
  "misc6"
}
local builder_maxBeams = 50
local builder_maxBeamParts = 50
local builder_beams = {}
for i=1,builder_maxBeams,1 do
  local part = "laser"
  if i > 1 then
    part = string.format("laser%.0f",i)
  end
  if i > builder_maxBeamParts then
    part = nil
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
function builder_cancel()
  for k,v in next, builder_beams do
    if v.current then
      v.current.active = false
      v.current = nil
    end
  end
  builder_blocks = nil
end
function getMiscGroup()
  miscGroupI = miscGroupI + 1
  return miscGroups[miscGroupI]
end

function builder_update()
    -- TODO: total rework. A* builder maybe?
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
            -- unplaceable tile
            builder_blocks[k] = nil
            elseif v.pos[3] == "liquid" then
            -- liquid, just places the liquid immediately
            -- TODO: handle liquids after everything else is set, currently this fails
            anyToDo = true
            builder_assignBeam(v)
            if not builder_anyFreeBeams() then
                break
            end
            elseif v.pos[3] == "objectSpace" then
            -- object space tile that can support other objects. technically in foreground, technically its own layer codewise.
            if not builder_blocks[v.objectKey] then
                builder_blocks[k] = nil
            end
            elseif v.pos[3] == "object" then
            -- object
            anyToDo = true
            if v.mat then
                -- TODO: will have deadlock in some very specific cases.
                -- TODO: will prefer placing torches on walls over torches placed on desks, for example. it's highly opportunistic.
                local anyValidNowNoChanges = false
                local anyAnyChanges = false
                for _,ori in next, v.orientations do
                local validNow = true
                local anyChanges = false
                for sk,sp in next, ori.spaces do
                    local later = builder_blocks[sk]
                    if later and later.pos[3] ~= "objectSpace" then
                    -- something is changing here, wait for it to finish first
                    world.debugPoint(sp,"white")
                    world.debugLine(v.pos,sp,"white")
                    anyChanges = true
                    validNow = false
                    break
                    end
                    if validNow and world.tileIsOccupied(sp) then
                    world.debugPoint(sp,"black")
                    world.debugLine(v.pos,sp,"black")
                    -- obstructed
                    validNow = false
                    break
                    end
                end
                for ak,ap in next, ori.anchors do
                    local later = builder_blocks[ak]
                    if later and not (later.pos[3] == "objectSpace" and later.object == v) then
                    -- something is changing here, wait for it to finish first
                    world.debugPoint(ap,"red")
                    world.debugLine(v.pos,ap,"red")
                    anyChanges = true
                    validNow = false
                    break
                    end
                    -- TODO: more accurate anchor check
                    if validNow and not world.tileIsOccupied(ap,ap[3] == "foreground") then
                    -- something doesn't support it here
                    world.debugPoint(ap,"green")
                    world.debugLine(v.pos,ap,"green")
                    validNow = false
                    break
                    end
                end
                if validNow and not anyChanges then
                    anyValidNowNoChanges = true
                end
                if anyChanges then
                    anyAnyChanges = true
                end
                if not validNow then
                    world.debugLine(mcontroller.position(),v.pos,"white")
                end
                end
                if not anyValidNowNoChanges and not anyAnyChanges then
                -- give up
                if not v.giveUpTimer then
                    v.giveUpTimer = timer+60
                elseif v.giveUpTimer > timer then
                    builder_blocks[k] = nil
                    for sk,o in next, v.spaces do
                    if builder_blocks[sk] == o then
                        builder_blocks[sk] = nil
                    end
                    end
                end
                elseif anyValidNowNoChanges then
                anyToDo = true
                builder_assignBeam(v)
                if not builder_anyFreeBeams() then
                    break
                end
                else
                v.giveUpTimer = nil
                end
            elseif world.tileIsOccupied(v.pos) then
                anyToDo = true
                builder_assignBeam(v)
                if not builder_anyFreeBeams() then
                break
                end
            else
                builder_blocks[k] = nil
            end
            else
            -- tile
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
        if v.part then
            animator.resetTransformationGroup(v.part)
        end
        -- work on the current block
        if v.current then
            if isFirst then
            isFirst = false
            vec2.addToRef(v.current.pos, 0.5, eyeTarget)
            end
            world.debugPoint(v.current.pos, "red")
            if v.part then
            local angle = vec2.angle(world.distance(v.current.pos, mePos))
            local l = world.magnitude(v.current.pos, mePos)-0.5
            animator.scaleTransformationGroup(v.part, {l*8,1})
            animator.translateTransformationGroup(v.part,{l/2,0})
            animator.rotateTransformationGroup(v.part, angle)
            end
            if v.current.pos[3] == "liquid" then
            local ll = world.liquidAt(vec2.copyToRef(v.current.pos, vec2working1))
            local l = ll and ll[1] or false
            if l ~= v.current.mat then
                if not l then
                if v.part then
                    animator.setAnimationState(v.part,"deepblue")
                end
                if world.spawnLiquid(v.current.pos, v.current.mat, v.current.level) then
                    -- important that this be done immediately
                    builder_blocks[builder_key(v.current.pos[1],v.current.pos[2],v.current.pos[3])] = nil
                    v.current.active = false
                    v.current = nil
                end
                else
                if v.part then
                    animator.setAnimationState(v.part,"red")
                end
                if world.destroyLiquid(v.current.pos) then
                    builder_blocks[builder_key(v.current.pos[1],v.current.pos[2],v.current.pos[3])] = nil
                    v.current.active = false
                    v.current = nil
                end
                end
            else
                builder_blocks[builder_key(v.current.pos[1],v.current.pos[2],v.current.pos[3])] = nil
                v.current.active = false
                v.current = nil
            end
            elseif v.current.pos[3] == "object" then
            -- object
            if v.current.mat then
                if v.part then
                animator.setAnimationState(v.part,"green")
                end
                if world.placeObject(v.current.mat,v.current.pos,v.current.direction,v.current.params) then
                for sk,o in next, v.current.spaces do
                    if builder_blocks[sk] == o then
                    builder_blocks[sk] = nil
                    end
                end
                builder_blocks[builder_key(v.current.pos[1],v.current.pos[2],v.current.pos[3])] = nil
                v.current.active = false
                v.current = nil
                end
            elseif world.tileIsOccupied(v.current.pos) then
                if v.part then
                animator.setAnimationState(v.part,"red")
                end
                world.damageTiles({v.current.pos}, "foreground", mePos, "beamish", 1000, 0)
            else
                if v.part then
                animator.setAnimationState(v.part,"off")
                end
                v.current.active = false
                v.current = nil
            end
            else
            -- is mat
            local mat = world.material(v.current.pos, v.current.pos[3])
            if mat ~= v.current.mat then
                if not mat and not world.tileIsOccupied(v.current.pos, v.current.pos[3] == "foreground") then
                if v.part then
                    animator.setAnimationState(v.part,"green")
                end
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
                          world.placeObject("invisibleproximitysensor",pos,0,{scripts={"/scripts/abyssminion/abyssplacehelper.lua"},block=v.current,clientEntityMode="clientMasterAllowed"})
                      end
                    else
                    -- object is obstructed... just do this later
                    v.current.active = false
                    v.current.delayUntil = timer+30
                    v.current = nil
                    end
                else
                    if v.current.colour then
                    world.setMaterialColor(v.current.pos,v.current.pos[3],v.current.colour)
                    end
                    v.current.active = false
                    v.current = nil
                end
                elseif world.replaceMaterials and v.current.mat then
                if v.part then
                    animator.setAnimationState(v.part,"green")
                end
                world.replaceMaterials({v.current.pos}, v.current.pos[3], v.current.mat, v.current.hue or 0, false)
                else
                if v.part then
                    animator.setAnimationState(v.part,"red")
                end
                world.damageTiles({v.current.pos}, v.current.pos[3], mePos, "beamish", 1000, 0)
                end
            else
                if v.part then
                animator.setAnimationState(v.part,"off")
                end
                if v.current.colour then
                world.setMaterialColor(v.current.pos,v.current.pos[3],v.current.colour)
                end
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
          if v.part then
            animator.setAnimationState(v.part,"off")
          end
          v.current = nil
        end
    end
end
