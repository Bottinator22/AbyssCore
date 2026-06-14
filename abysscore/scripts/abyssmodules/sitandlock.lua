require "/scripts/abyssmodules/modules.lua"
require "/scripts/terra_vec2ref.lua"
require "/scripts/util.lua"

-- bind is used for sitting.
-- also allows locking position.

-- ...and a bunch of other utilities, actually.
local sitMode
local sitState = "sit"
local lockedPosition
local lockedPositionRot
local lockedPositionMyRot
local lockedPositionFacing
local lockedPositionMyFacing
local lockedPositionEntity

local module = {
    moduleSlots={
        movement=true
    }
}
function setLockedPosition(p)
    if lockedPositionEntity and lockedPositionEntity:exists() then
        lockedPosition = world.distance(p,lockedPositionEntity:position())
        lockedPositionFacing = lockedPositionEntity:facingDirection() or 1
        lockedPositionMyFacing = mcontroller.facingDirection()
        lockedPositionRot = lockedPositionEntity:rotation() or 0
        lockedPositionMyRot = mcontroller.rotation()
    else
        lockedPosition = p
    end
end
local wasMoving = false
local function setEnabled(mode)
    if sitMode ~= mode then
        sitMode = mode
    end
end
function module.isBindHeld(args)
    return false
end
function module.shouldEnable(args)
    return (sitMode or lockedPosition) and (args.moves.up or args.moves.down or args.moves.left or args.moves.right)
end
function module.init()
    if onTeleport then
        -- work with teleport module
        local oldOT = onTeleport
        onTeleport = function(pos)
            if lockedPosition then
                setLockedPosition(pos)
            end
            oldOT(pos)
        end
        local oldOF = onFace
        onFace = function(targetFace)
            if lockedPosition and lockedPositionEntity then
                local f = lockedPositionEntity:facingDirection() or 1
                lockedPositionMyFacing = targetFace*f*lockedPositionFacing
            end
            oldOF(targetFace)
        end
    end
    modules.addPressCommand("/sit",module)
    message.setHandler("/sitState",function(_,l,c)
        if #c <= 0 then
            sitState = "sit"
        else
            sitState = c
        end
    end)
    message.setHandler("/lockPos",function(_,l)
        if not l then return "no" end
        if lockedPosition then
            lockedPosition = nil
            lockedPositionEntity = nil
            return "Position no longer locked."
        else
            lockedPosition = mcontroller.position()
            return "Position now locked."
        end
    end)
    message.setHandler("/attach",function(_,l)
        if not l then return "no" end
        if lockedPositionEntity then
            lockedPosition = nil
            lockedPositionEntity = nil
            return "Position no longer locked to entity."
        else
            local e = world.entityQuery(tech.aimPosition(),1,{order="nearest"})[1]
            if e then
                lockedPositionEntity = world.entity(e)
            else
                return "Can't find an entity to lock to."
            end
            setLockedPosition(mcontroller.position())
            return "Position now locked to entity."
        end
    end)
    message.setHandler("/rot",function(_,l,c)
        if not l then return "no" end
        local tr = 0
        if #c <= 0 or not tonumber(c) then
        else
            local a = tonumber(c)/180*math.pi
            tr = a
        end
        mcontroller.setRotation(tr)
        if lockedPositionEntity then
            local r = lockedPositionEntity:rotation() or 0
            local rd = util.angleDiff(lockedPositionRot,r)
            lockedPositionMyRot = tr-rd
        end
    end)
end
function module.enable()
end
function module.suppressMovement()
    return false
end
function module.isActive()
    return (sitMode or lockedPosition) and wasMoving
end
function module.bindPressed()
    setEnabled(not sitMode)
end
function module.disable()
end
function module.update(args)
    if sitMode or lockedPosition then
        if sitMode then
            module.parentState = sitState
            mcontroller.controlParameters({
                gravityEnabled=false,
                collisionEnabled=false
            })
        end
        
        wasMoving = args.moves.up or args.moves.down or args.moves.left or args.moves.right
        
        local targetFace = 0
        local flyVelocity = {0,0}
        if module.enabled then
            local s = 1
            if args.moves.run then s = 5 end
            if args.moves["right"] then flyVelocity[1] = s end
            if args.moves["left"] then flyVelocity[1] = -s end
            if args.moves["up"] then flyVelocity[2] = s end
            if args.moves["down"] then flyVelocity[2] = -s end
        end
        
        if flyVelocity[1] < 0 then
            targetFace = -1
        elseif flyVelocity[1] > 0 then
            targetFace = 1
        end
        
        mcontroller.setVelocity(flyVelocity)
        
        if lockedPositionEntity and not lockedPositionEntity:exists() then
            lockedPosition = nil
            lockedPositionEntity = nil
        end
        if lockedPosition then
            if lockedPositionEntity then
                local f = lockedPositionEntity:facingDirection() or 1
                local r = lockedPositionEntity:rotation() or 0
                local rd = util.angleDiff(lockedPositionRot,r)
                mcontroller.setPosition(vec2.add(lockedPositionEntity:position(),vec2.rotate(vec2.mul(lockedPosition,{f*lockedPositionFacing,1}),rd)))
                if targetFace ~= 0 then
                    lockedPositionMyFacing = targetFace*f*lockedPositionFacing
                else
                    mcontroller.controlFace(lockedPositionMyFacing*f*lockedPositionFacing)
                end
                mcontroller.setRotation(lockedPositionMyRot+rd)
                world.debugLine(mcontroller.position(),lockedPositionEntity:position(),"white")
            else
                vec2.addToRef(lockedPosition,vec2.mul(flyVelocity,args.dt),lockedPosition)
                mcontroller.setPosition(lockedPosition)
            end
            mcontroller.setVelocity({0,0})
            if vec2.mag(flyVelocity) > 0 and lockedPositionEntity then
                setLockedPosition(vec2.add(mcontroller.position(),vec2.mul(flyVelocity,args.dt)))
            end
        end
    end
    if not sitMode then
        module.parentState = nil
    end
end
presentModules.sit = module
