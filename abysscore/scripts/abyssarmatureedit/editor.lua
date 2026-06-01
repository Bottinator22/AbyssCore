require "/scripts/terra_vec2ref.lua"
require "/scripts/terra_vec3.lua"
require "/scripts/terra_mat3.lua"
require "/scripts/terra_renderutil.lua"
require "/scripts/terra_proxy.lua"
require "/scripts/poly.lua"
require "/scripts/terra_inversekinematics.lua"

abyssRenderUtil_useVel = false

-- In-game pose override editor.

local lastSpecial2
local lastSpecial3
local editingEntity
local editingEntity_useMessage

local selected

local selectCircleSegments = 12
local selectCircleRadius = 0.5
local selectCircleHoverColour = {0,0,255}
local selectCircleColour = {0,255,255}
local selectCircleUnsupportedColour = {0,0,127}

local overriddenColour = {255,255,255}

armatureedit = {}
local function makePolyDrawables(poly, colour, width, fullbright)
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
local function contactEntity(...)
    if editingEntity_useMessage then
        return world.sendEntityMessage(editingEntity,...):result()
    else
        return world.callScriptedEntity(editingEntity,...)
    end
end
function armatureedit.init(entity,emsg)
    editingEntity = entity
    editingEntity_useMessage = emsg
    lastSpecial2 = false
    lastSpecial3 = false
end
local function worldToLocal(pos)
    return world.distance(pos, mcontroller.position())
end
local function worldToLocalPoly(poly)
    local newpoly = {}
    for k,v in next, poly do
        table.insert(newpoly, worldToLocal(v))
    end
    return newpoly
end
local function getLocalAnimator()
    if not localAnimator then
        localAnimator = terra_proxy.setupProxy("localAnimator",entity.id())
    end
    return localAnimator
end
local function entityLocalToMyLocal(transform)
    local facing = contactEntity("editable_getFacing")
    local rot = contactEntity("editable_getRotation")
    return mat3.translate(mat3.scale(mat3.rotate(transform,rot),{facing,1}),worldToLocal(world.entityPosition(editingEntity)))
end
local heldGizmoData
local lastAlt = false
local lastPrimary = false

local veryBig = 2^1023
local function isNaN(n)
    return (not (n < 0) and not (n > 0) and not (n == 0)) or math.abs(n) > veryBig
end
-- 2^53 is the limit before adding/subbing from 1 makes it equal to 1
-- make this fraction a bit larger than that to account for other imprecisions in the math of IK
local verySmall = 1/(2^10)
local greaterThanOne = 1 + verySmall
local lessThanOne = 1 - verySmall

local function xyMode(isScale,isIK)
    return function(selBone,args)
        local aim = worldToLocal(tech.aimPosition())
        local e = contactEntity("editable_updateBone",selected)
        local bone = selBone
        local center = bone.center
        local transform
        if isScale then
            transform = entityLocalToMyLocal(bone.appliedTransform)
        elseif bone.parent and not isIK then
            center = mat3.transform(bone.center,mat3.multiply(bone.transform,bone.baseTransform))
            transform = entityLocalToMyLocal(bone.parent.appliedTransform)
        else
            if isIK and bone.ikData.ikCenter then
                -- TODO: this is inaccurate if the bone is rotated
                center = mat3.transform(mat3.transform(bone.ikData.ikCenter,mat3.getRotationMatrix(-e.rotation,bone.center)),bone.appliedTransform)
            else
                center = mat3.transform(bone.center,bone.appliedTransform)
            end
            transform = entityLocalToMyLocal(mat3.identity())
        end
        if heldGizmoData then
            transform = heldGizmoData.startTransform
            center = heldGizmoData.startCenter
        end
        local invTransform = mat3.invert(transform)
        local exportedTransform = mat3.exportJson(transform)
        local relAim = mat3.transform(aim,invTransform)
        local relAim2 = vec2.sub(relAim,center)
        local scale = 1/4
        local thickness = 1.5*scale
        local hThickness = thickness*0.5
        local startOff = 2*scale
        local len = 8*scale
        local arrowThickness = 4*scale
        local arrowHThickness = arrowThickness/2
        local arrowLen = 4*scale
        local xzStartOff = 2.5*scale
        local xzSize = 4*scale
        local gizmoHovered
        local gizmoHeld = heldGizmoData and heldGizmoData.heldGizmo
        local xHov = gizmoHeld == "x" or (relAim2[1] > startOff and relAim2[1] < startOff+len+arrowLen and relAim2[2] < arrowHThickness and relAim2[2] > -arrowHThickness)
        local yHov = gizmoHeld == "y" or (relAim2[2] > startOff and relAim2[2] < startOff+len+arrowLen and relAim2[1] < arrowHThickness and relAim2[1] > -arrowHThickness)
        local xyHov = gizmoHeld == "xy" or (relAim2[1] > xzStartOff and relAim2[2] > xzStartOff and relAim2[1] < xzStartOff+xzSize and relAim2[2] < xzStartOff+xzSize)
        if gizmoHeld then
            gizmoHovered = gizmoHeld
        elseif xyHov then
            gizmoHovered = "xy"
        elseif xHov then
            gizmoHovered = "x"
        elseif yHov then
            gizmoHovered = "y"
        else
            gizmoHovered = nil
        end
        if gizmoHovered and args.moves.primaryFire and not lastPrimary then
            local startState
            if isScale then
                startState = e.scale
            elseif isIK then
                startState = center
            else
                startState = e.offset
            end
            heldGizmoData = {
                startState=startState,
                startAim=relAim,
                startTransform=transform,
                startCenter=center,
                heldGizmo=gizmoHovered
            }
        end
        if gizmoHeld then
            local off = vec2.sub(relAim,heldGizmoData.startAim)
            if gizmoHeld == "x" then
                off[2] = 0
            elseif gizmoHeld == "y" then
                off[1] = 0
            elseif not args.moves.run and not isIK then
                local sx = (off[1] < 0) and -1 or 1
                local sy = (off[2] < 0) and -1 or 1
                local a = (math.abs(off[1])+math.abs(off[2]))/2
                off[1] = a*sx
                off[2] = a*sy
            end
            e.overridden = true
            if isScale then
                e.scale = vec2.add(heldGizmoData.startState,vec2.mul(off,scale))
            elseif isIK then
                -- TODO: IK
                local targetPos = vec2.add(heldGizmoData.startState,off)
                
                -- draw intended target
                local point = generatePointDrawable(targetPos,0.125)
                point.transformation = exportedTransform
                point.color = {0,0,255}
                point.fullbright = true
                localAnimator.addDrawable(point,"Overlay+32000")
                
                -- IK relies on the 2 bones directly before the IKed bone
                local ikData = bone.ikData
                
                local base = ikData.base
                local mid = ikData.mid
                
                local be = contactEntity("editable_updateBone",base.name)
                local me = contactEntity("editable_updateBone",mid.name)
                
                -- calculate IK
                
                -- appliedTransfrom still has the existing base bone transformation, calculate a version without
                -- NOTE: assumes base has a parent
                local baseTransform = mat3.multiply(mat3.translate(mat3.getScalingMatrix(be.scale,base.center),be.offset),base.baseTransform)
                local appliedTransform = mat3.multiply(baseTransform,base.parent.appliedTransform)
                
                local inv = mat3.invert(appliedTransform)
                local relTargetPos = mat3.transform(targetPos,inv)
                
                -- clamp the bone so it doesn't break
                -- unfortunately it seems to be broken if length >= maxLength, so we have to add a miniscule offset
                -- this is... annoyingly weird, need to figure out what the actual limit is
                local diff = vec2.sub(relTargetPos,base.center)
                local maxLength = ikData.firstLength+ikData.secondLength
                local minLength = math.abs(ikData.firstLength-ikData.secondLength)
                if vec2.mag(diff) >= maxLength then
                    relTargetPos = vec2.add(base.center,vec2.mul(vec2.norm(diff),maxLength*lessThanOne))
                elseif vec2.mag(diff) <= minLength then
                    relTargetPos = vec2.add(base.center,vec2.mul(vec2.norm(diff),minLength*greaterThanOne))
                end
                
                local Aa,Ba = inversekinematics.solveAngles(relTargetPos,base.center,ikData.firstLength,ikData.secondLength,ikData.useAltSolution)
                
                if isNaN(Aa) or isNaN(Ba) then
                    -- do nothing
                else
                    
                    local oldEndRotRef = be.rotation+me.rotation
                    be.rotation = Aa-ikData.firstAngleOffset
                    me.rotation = -Ba-ikData.secondAngleOffset
                    be.overridden = true
                    me.overridden = true
                    local endRotRef = be.rotation+me.rotation
                    local diff = util.angleDiff(endRotRef,oldEndRotRef)
                    if args.moves.run and not e.ikLeaveRot then
                        -- prevent rotation from changing (unless Shift held)
                        e.rotation = e.rotation + diff
                    end
                    contactEntity("editable_setState",base.name,be)
                    contactEntity("editable_setState",mid.name,me)
                end
            else
                e.offset = vec2.add(heldGizmoData.startState,off)
            end
            if not isScale then
                center = vec2.add(center,off)
            end
            if not args.moves.primaryFire then
                heldGizmoData = nil
            end
            contactEntity("editable_setState",selected,e)
        elseif isIK and bone.ikData.ikCenter then
            local point = generatePointDrawable(center,0.125)
            point.transformation = exportedTransform
            point.color = {0,0,255}
            point.fullbright = true
            localAnimator.addDrawable(point,"Overlay+32000")
        end
        local xColour
        local yColour
        local xyColour
        local xyInnerColour
        if isIK then
            xColour = xHov and {127,255,255} or {0,255,255}
            yColour = yHov and {255,127,255} or {255,0,255}
            xyColour = xyHov and {127,127,255} or {0,0,255}
            xyInnerColour = xyHov and {127,127,255,127} or {0,0,255,127}
        else
            xColour = xHov and {255,127,127} or {255,0,0}
            yColour = yHov and {127,255,127} or {0,255,0}
            xyColour = xyHov and {255,255,127} or {255,255,0}
            xyInnerColour = xyHov and {255,255,127,127} or {255,255,0,127}
        end
        
        local xHeadPoly
        local yHeadPoly
        if isScale then
            xHeadPoly = {
                {center[1]+startOff+len,              center[2]+arrowHThickness},
                {center[1]+startOff+len,              center[2]-arrowHThickness},
                {center[1]+startOff+len+arrowLen,     center[2]-arrowHThickness},
                {center[1]+startOff+len+arrowLen,     center[2]+arrowHThickness}
            }
            yHeadPoly = {
                {center[1]+arrowHThickness, center[2]+startOff+len         },
                {center[1]-arrowHThickness, center[2]+startOff+len         },
                {center[1]-arrowHThickness, center[2]+startOff+len+arrowLen},
                {center[1]+arrowHThickness, center[2]+startOff+len+arrowLen}
            }
        else
            xHeadPoly = {
                {center[1]+startOff+len,         center[2]+arrowHThickness},
                {center[1]+startOff+len,         center[2]-arrowHThickness},
                {center[1]+startOff+len+arrowLen,center[2]                }
            }
            yHeadPoly = {
                {center[1]+arrowHThickness, center[2]+startOff+len         },
                {center[1]-arrowHThickness, center[2]+startOff+len         },
                {center[1],                 center[2]+startOff+len+arrowLen}
            }
        end
        local xHead = {poly=xHeadPoly,transformation=exportedTransform,color=xColour,fullbright=true}
        local xBody = {poly={
            {center[1]+startOff,         center[2]+hThickness},
            {center[1]+startOff,         center[2]-hThickness},
            {center[1]+startOff+len,     center[2]-hThickness},
            {center[1]+startOff+len,     center[2]+hThickness}
        },transformation=exportedTransform,color=xColour,fullbright=true}
        
        local yHead = {poly=yHeadPoly,transformation=exportedTransform,color=yColour,fullbright=true}
        local yBody = {poly={
            {center[1]+hThickness, center[2]+startOff    },
            {center[1]-hThickness, center[2]+startOff    },
            {center[1]-hThickness, center[2]+startOff+len},
            {center[1]+hThickness, center[2]+startOff+len}
        },transformation=exportedTransform,color=yColour,fullbright=true}
        
        local xyBoxPoly = {
            {center[1]+xzStartOff,        center[2]+xzStartOff       },
            {center[1]+xzStartOff+xzSize, center[2]+xzStartOff       },
            {center[1]+xzStartOff+xzSize, center[2]+xzStartOff+xzSize},
            {center[1]+xzStartOff,        center[2]+xzStartOff+xzSize}
        }
        local xyBox = {poly=xyBoxPoly,transformation=exportedTransform,color=xyInnerColour,fullbright=true}
        
        for k,v in next, makePolyDrawables(mat3.transformPoly(xyBoxPoly,transform),xyColour,1.0,true) do
            localAnimator.addDrawable(v,"Overlay+32000")
        end
        localAnimator.addDrawable(xyBox,"Overlay+31999")
        localAnimator.addDrawable(xHead,"Overlay+32000")
        localAnimator.addDrawable(xBody,"Overlay+32000")
        localAnimator.addDrawable(yHead,"Overlay+32000")
        localAnimator.addDrawable(yBody,"Overlay+32000")
        return gizmoHovered
    end
end
local modesArr = {
    {
        name="rotate",
        image="/ab_armatureedit/rotate.png",
        update=function(selBone,args)
            local aim = worldToLocal(tech.aimPosition())
            local epos = worldToLocal(selBone.editorData.worldPos)
            if heldGizmoData then
                epos = heldGizmoData.gizmoPos
            end
            local aimDis = world.magnitude(aim,epos)
            local size = 6
            local rdiff = size/16
            local radius = 1.5
            local hovered = false
            if math.abs(aimDis-radius) < rdiff then
                hovered = true
                if args.moves.primaryFire and not lastPrimary then
                    local e = contactEntity("editable_updateBone",selected)
                    heldGizmoData = {
                        startState=e.rotation,
                        startAim=aim,
                        gizmoPos=epos,
                        startFacing=contactEntity("editable_getFacing")
                    }
                end
            end
            local segments = 25
            local aoffset = 0
            if heldGizmoData then
                local e = selBone.editorData
                e.overridden = true
                local sAngle = vec2.angle(vec2.sub(heldGizmoData.gizmoPos,heldGizmoData.startAim))
                local eAngle = vec2.angle(vec2.sub(heldGizmoData.gizmoPos,aim))
                local angleDiff = util.angleDiff(sAngle,eAngle)
                e.rotation = heldGizmoData.startState+angleDiff*heldGizmoData.startFacing
                aoffset = angleDiff
                contactEntity("editable_setState",selected,e)
                if not args.moves.primaryFire then
                    heldGizmoData = nil
                end
            end
            local colour = {255,0,0}
            if hovered or heldGizmoData then
                colour = {255,127,127}
            end
            for i=1,segments do
                local p1 = vec2.add(epos, vec2.withAngle(math.pi*2/segments*(i-1)+aoffset, radius))
                local p2 = vec2.add(epos, vec2.withAngle(math.pi*2/segments*i+aoffset, radius))
                local line = generateLineDrawable(p1, p2)
                line.color = colour
                line.fullbright = true
                line.width = size
                localAnimator.addDrawable(line,"Overlay+32000")
            end
            return hovered or not not heldGizmoData
        end
    },
    {
        name="translate",
        image="/ab_armatureedit/translate.png",
        update=xyMode(false,false)
    },
    {
        name="scale",
        image="/ab_armatureedit/scale.png",
        update=xyMode(true,false)
    },
    {
        name="translateIK",
        image="/ab_armatureedit/translateIK.png",
        update=xyMode(false,true)
    }
}
local modes = {}
for _,v in next, modesArr do
    modes[v.name] = v
end
local currentMode = modes.rotate
local modeListWidth = 1
function armatureedit.update(args)
    local localAnimator = getLocalAnimator()
    if not localAnimator then
        return
    end
    if args.moves.special2 ~= lastSpecial2 then
        if args.moves.special2 then
            if modeSelectPos then
                modeSelectPos = nil
            else
                modeSelectPos = world.distance(tech.aimPosition(), mcontroller.position())
            end
        end
        lastSpecial2 = args.moves.special2
    end
    if modeSelectPos then
        local x = 0
        local y = 0
        local iconSpacing = 2.5
        local needModeSelect = false
        local mCell = vec2.floor(vec2.sub(vec2.div(vec2.sub(world.distance(tech.aimPosition(), mcontroller.position()),modeSelectPos), iconSpacing), {-0.5,-0.5}))
        mCell[2] = mCell[2] * -1
        for k,v in next, modesArr do
            local img = v.image
            if mCell[1] == x and mCell[2] == y then
                img = img.."?saturation=-25?brightness=50"
                if args.moves.primaryFire and not lastPrimary then
                    currentMode = v
                    heldGizmoData = nil
                end
            end
            localAnimator.addDrawable({image=img,position=vec2.add(modeSelectPos, {x*iconSpacing,y*iconSpacing*-1}),fullbright=true},"Overlay+32005")
            x = x + 1
            if x >= modeListWidth then
                y = y + 1
                x = 0
            end
        end
        if (args.moves.primaryFire and not lastPrimary) or (args.moves.altFire and not lastAlt) then
            modeSelectPos = nil
        end
    else
        local bones = contactEntity("editable_getEditableBones")
        for k,v in next, bones do
            local colour = renderutil.namedColour(v.debugColour)
            local point = generatePointDrawable_absolute(v.editorData.worldPos,0.125)
            point.color = colour
            if v.editorData.overridden then
                point.color = overriddenColour
            end
            point.fullbright = true
            localAnimator.addDrawable(point,"Overlay+31901")
            if v.parent then
                local line = generateLineDrawable_absolute(v.editorData.worldPos,v.parent.editorData.worldPos)
                line.color = colour
                line.fullbright = true
                line.width = 1
                localAnimator.addDrawable(line,"Overlay+31900")
            end
        end
        local modeHasPrimary = false
        if selected then
            local selBone = bones[selected]
            local isIK = currentMode == modes.translateIK
            local supported = not isIK or not not selBone.ikData
            local colour = selectCircleColour
            if not supported then
                colour = selectCircleUnsupportedColour
            end
            local radius = selectCircleRadius
            local epos = worldToLocal(selBone.editorData.worldPos)
            local aoffset = os.clock()*math.pi
            for i=1,selectCircleSegments do
                local p1 = vec2.add(epos, vec2.withAngle(math.pi*2/selectCircleSegments*(i-1)+aoffset, radius))
                local p2 = vec2.add(epos, vec2.withAngle(math.pi*2/selectCircleSegments*i+aoffset, radius))
                local line = generateLineDrawable(p1, p2)
                line.color = colour
                line.fullbright = true
                line.width = 1.0
                localAnimator.addDrawable(line,"Overlay+32000")
            end
            if args.moves.special3 then
                selBone.editorData.overridden = false
                contactEntity("editable_setState",selected,selBone.editorData)
                if isIK and selBone.ikData then
                    selBone.parent.editorData.overridden = false
                    contactEntity("editable_setState",selBone.parentName,selBone.parent.editorData)
                    selBone.parent.parent.editorData.overridden = false
                    contactEntity("editable_setState",selBone.parent.parentName,selBone.parent.parent.editorData)
                end
            elseif supported then
                modeHasPrimary = currentMode.update(selBone,args)
            end
        end
        local aimPos = tech.aimPosition()
        if args.moves.primaryFire and not lastPrimary and not modeHasPrimary then
            local closest = nil
            local closestDis = 0.5
            for k,v in next, bones do
                local dis = world.magnitude(aimPos,v.editorData.worldPos)
                if dis < closestDis then
                    closest = k
                    closestDis = dis
                end
            end
            if closest then
                selected = closest
            end
        end
        if args.moves.altFire and not lastAlt then
            selected = nil
        end
        local modeImgPos = {5,5}
        if world.magnitude(tech.aimPosition(), mcontroller.position()) > 40 then
            modeImgPos = vec2.add(world.distance(tech.aimPosition(),mcontroller.position()),{2.5,2.5})
        end
        local img = currentMode.image
        localAnimator.addDrawable({image=img,position=modeImgPos,fullbright=true},"Overlay+32005")
    end
    lastPrimary = args.moves.primaryFire
    lastAlt = args.moves.altFire
    lastSpecial3 = args.moves.special3
end
function armatureedit.uninit()
end
