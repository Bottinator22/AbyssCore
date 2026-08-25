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
local lockedPositionUid
local lockedPositionEType
local lockedPositionUPromise

local module = {
    moduleSlots={
        movement=true
    }
}
function setLockedPosition(p)
    if lockedPositionEntity and lockedPositionEntity:exists() then
        local rotOffset = -(lockedPositionEntity:rotation() or 0)
        lockedPosition = vec2.rotate(world.distance(p,lockedPositionEntity:position()),rotOffset)
        lockedPositionFacing = lockedPositionEntity:facingDirection() or 1
        lockedPositionMyFacing = mcontroller.facingDirection()
        lockedPositionRot = (lockedPositionEntity:rotation() or 0) + rotOffset
        lockedPositionMyRot = mcontroller.rotation() + rotOffset
    elseif lockedPositionUid then
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
local function resetLock()
    lockedPosition = nil
    lockedPositionEntity = nil
    lockedPositionUid = nil
    lockedPositionUPromise = nil
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
            resetLock()
            return "Position no longer locked."
        else
            lockedPosition = mcontroller.position()
            return "Position now locked."
        end
    end)
    message.setHandler("/attach",function(_,l,c)
        if not l then return "no" end
        if lockedPositionEntity or lockedPositionUid then
            resetLock()
            return "Position no longer locked to entity."
        else
            local t = nil
            if c == "player" then
                t = {"player"}
            end
            local e = world.entityQuery(tech.aimPosition(),1,{order="nearest",includedTypes=t})[1]
            if e then
                lockedPositionEntity = world.entity(e)
                lockedPositionUid = lockedPositionEntity:uniqueId()
                lockedPositionEType = lockedPositionEntity:type()
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
    message.setHandler("abyss_remoteAttachAllowed",function(_,l,s)
        return not not player.getProperty("abyss_allowRemoteAttach")
    end)
    message.setHandler("abyss_sit",function(_,l,s)
        if not l and not player.getProperty("abyss_allowRemoteAttach") then return "not enabled" end
        sitMode = not not s
        sitState = s
    end)
    message.setHandler("abyss_attach",function(_,l,e)
        if not l and not player.getProperty("abyss_allowRemoteAttach") then return "not enabled" end
        if not e then
            if lockedPositionEntity or lockedPositionUid then
                resetLock()
            end
        else
            if world.entityExists(e) then
                if player.isLounging() then
                    player.stopLounging()
                end
                lockedPositionEntity = world.entity(e)
                lockedPositionUid = lockedPositionEntity:uniqueId()
                lockedPositionEType = lockedPositionEntity:type()
                setLockedPosition(mcontroller.position())
            end
        end
    end)
    message.setHandler("abyss_attachPos",function(_,l,p)
        if not l and not player.getProperty("abyss_allowRemoteAttach") then return "not enabled" end
        if not p and lockedPosition then
            resetLock()
            return
        end
        if lockedPositionEntity or lockedPositionUid then
            setLockedPosition(p)
        end
    end)
    message.setHandler("abyss_attachRot",function(_,l,r)
        if not l and not player.getProperty("abyss_allowRemoteAttach") then return "no" end
        local tr = 0
        if r and type(r) == "number" then
            tr = r
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
        
        if player.isLounging() then
            resetLock()
        end
        if lockedPositionEntity and not lockedPositionEntity:exists() then
            if not lockedPositionUid then
                lockedPosition = nil
            end
            lockedPositionEntity = nil
        end
        if lockedPosition then
            if lockedPositionEntity then
                local f = lockedPositionEntity:facingDirection() or 1
                local r = lockedPositionEntity:rotation() or 0
                local faceDiff = f*lockedPositionFacing
                local rd = util.angleDiff(lockedPositionRot,r)
                mcontroller.setPosition(vec2.add(lockedPositionEntity:position(),vec2.rotate(vec2.mul(lockedPosition,{faceDiff,1}),rd)))
                if targetFace ~= 0 then
                    lockedPositionMyFacing = targetFace*f*lockedPositionFacing
                else
                    mcontroller.controlFace(lockedPositionMyFacing*f*lockedPositionFacing)
                end
                mcontroller.setRotation((lockedPositionMyRot*faceDiff+rd))
                world.debugLine(mcontroller.position(),lockedPositionEntity:position(),"white")
            elseif lockedPositionUid then
                -- wait for the entity to be found and reloaded
                if not lockedPositionUPromise then
                    lockedPositionUPromise = world.findUniqueEntity(lockedPositionUid)
                elseif lockedPositionUPromise:finished() then
                    if lockedPositionUPromise:succeeded() then
                        mcontroller.setPosition(lockedPositionUPromise:result())
                    else
                        resetLock()
                    end
                    lockedPositionUPromise = nil
                end
                local entities = world.entityQuery(mcontroller.position(),30,{includedTypes={lockedPositionEType},order="nearest"})
                for k,v in next, entities do
                    if world.entityUniqueId(v) == lockedPositionUid then
                        lockedPositionEntity = world.entity(v)
                        break
                    end
                end
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
