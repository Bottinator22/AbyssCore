require "/scripts/vec2.lua"

local function otherHandType()
    if activeItem.callOtherHandScript("activeItem.hand") then
        return "normal"
    end
    return nil
end
function activate(fireMode, shifting, moves)
    if otherHandType() then
        local mode = "none"
        if fireMode == "primary" then
            mode = "alt"
            activeItem.callOtherHandScript("activate",mode,shifting,moves)
        end
    else
    end
end

local anims
function init()
    -- I'd make this adapt to species but there's probably no point to that
    local baseHumanoidConfig = root.assetJson("/humanoid.config")
    local stateFrames = baseHumanoidConfig.humanoidTiming.stateFrames
    local stateCycle = baseHumanoidConfig.humanoidTiming.stateCycle
    local function configToAnim(index,seq,noLoop)
        return {
            frameTime=stateCycle[index]/stateFrames[index],
            frames=stateFrames[index],
            sequence=seq,
            loop=not noLoop
        }
    end
    anims = {
        walk=configToAnim(2,baseHumanoidConfig.armWalkSeq),
        run=configToAnim(3,baseHumanoidConfig.armRunSeq),
        jump=configToAnim(4,nil,true),
        fall=configToAnim(5,nil,true),
        swim=configToAnim(6),
        swimIdle=configToAnim(7,nil,true),
        duck=configToAnim(8),
        sit=configToAnim(9),
        lay=configToAnim(10)
    }
end

function setArmFrame(f)
    activeItem.setFrontArmFrame(f)
    activeItem.setBackArmFrame(f)
end

local frame = 0
local frameTimer = 0
local lastState
function update(dt,fireMode,shifting,moves)
    local oht = otherHandType()
    if oht then
        if not activeItem.callOtherHandScript("setAltHeld",activeItem.fireMode() == "primary") and oht == "normal" then
            -- patch it
            activeItem.callOtherHandScript("require","/scripts/abyssotherhand/weaponPatch.lua")
            activeItem.callOtherHandScript("setAltHeld",activeItem.fireMode() == "primary")
        end
    end
    
    -- try to look like a normal hand when not punching
    local state = world.sendEntityMessage(entity.id(),"abyss_parentState"):result()
    local frameDir = 1
    if not state then
        -- determine it otherwise
        state = "idle"
        if not mcontroller.groundMovement() then
            if mcontroller.yVelocity() > 0 then
                state = "jump"
            elseif mcontroller.yVelocity() < -4 then
                state = "fall"
            else
                state = lastState or "idle"
            end
        elseif mcontroller.walking() then
            state = "walk"
        elseif mcontroller.running() then
            state = "run"
        elseif mcontroller.crouching() then
            state = "duck"
        end
    end
    if state == "stand" then
        state = "idle"
    elseif state == "fly" then
        state = "jump"
    end
    if state ~= lastState then
        frame = 1
        frameTimer = 0
    end
    lastState = state
    --world.debugText(string.format("%s\n%d\n%.1f",state,frame,frameTimer),mcontroller.position(),"cyan")
    if state == "idle" then
        if not punching then
            setArmFrame(player.humanoidIdentity().personalityArmIdle)
        end
    elseif state == "duck" then
        if not punching then
            setArmFrame("duck.1?crop=0;0;43;27") -- NOTE: only works with base vanilla-like humanoids!
        end
    else
        frameTimer = frameTimer + dt
        local anim = anims[state]
        if frameTimer > anim.frameTime then
            frame = frame + frameDir
            if frame <= 0 then
                if anim.loop then
                    frame = anim.frames
                else
                    frame = 1
                end
            elseif frame > anim.frames then
                if anim.loop then
                    frame = 1
                else
                    frame = anim.frames
                end
            end
            frameTimer = frameTimer - anim.frameTime
        end
        -- still do the animation behind the scenes when punching
        if not punching then
            local frameN = frame
            if anim.sequence then
                frameN = anim.sequence[frame]
            end
            local frameName = string.format("%s.%d",state,frameN)
            setArmFrame(frameName)
        end
    end
end

function uninit()
end
