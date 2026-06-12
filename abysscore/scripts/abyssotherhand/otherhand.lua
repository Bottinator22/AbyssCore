require "/scripts/vec2.lua"

-- note: likely animates wrong on everyone else's end, especially where FPS differs

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

local function cropOffset(o)
    -- only works on standard 43x43 humanoids!
    -- has a limit to how much it can offset before stuff starts getting actually cropped out
    local b = 0
    local l = 0
    local u = 43
    local r = 43
    if o[1] < 0 then
        l = l - o[1]*2
    elseif o[1] > 0 then
        r = r - o[1]*2
    end
    if o[2] < 0 then
        b = b - o[2]*2
    elseif o[2] > 0 then
        u = u - o[2]*2
    end
    return string.format("?crop=%d;%d;%d;%d",l,b,r,u)
end
local stateDirectives
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
    local function bobToCropOffset(l,so)
        local o = {}
        for _,v in next, l do
            table.insert(o,cropOffset({0,-v-(so or 0)}))
        end
        return o
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
    stateDirectives={
        walk=bobToCropOffset(baseHumanoidConfig.walkBob),
        run=bobToCropOffset(baseHumanoidConfig.runBob,baseHumanoidConfig.runFallOffset),
        swim=bobToCropOffset(baseHumanoidConfig.swimBob),
        jump=cropOffset({0,-baseHumanoidConfig.jumpBob}),
        fall=cropOffset({0,-baseHumanoidConfig.runFallOffset}),
        duck=cropOffset({0,-baseHumanoidConfig.duckOffset}),
        sit=cropOffset({0,-baseHumanoidConfig.sitOffset}),
        lay=cropOffset({0,-baseHumanoidConfig.layOffset})
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
        if mcontroller.anchorState() then
            state = "sit"
        elseif mcontroller.zeroG() then
            if mcontroller.flying() then
                state = "swim"
            else
                state = "swimIdle"
            end
        elseif not mcontroller.groundMovement() then
            if mcontroller.liquidMovement() then
                state = "swimIdle"
                if mcontroller.jumping() then
                    state = "swim"
                end
            elseif mcontroller.yVelocity() > 0 then
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
        setArmFrame(player.humanoidIdentity().personalityArmIdle)
    elseif state == "sit" and player.getProperty("abyss_sitArmOverride") then
        -- optionally override the sit frame for arms when the item is held
        local o = player.getProperty("abyss_sitArmOverride")
        if type(o) == "table" then
            activeItem.setFrontArmFrame(o[1])
            activeItem.setBackArmFrame(o[2])
        else
            setArmFrame(o)
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
        
        local frameN = frame
        if anim.sequence then
            frameN = anim.sequence[frame]
        end
        local directives = ""
        if stateDirectives[state] then
            if type(stateDirectives[state]) == "table" then
                directives = stateDirectives[state][frame]
            else
                directives = stateDirectives[state]
            end
        end
        local frameName = string.format("%s.%d%s",state,frameN,directives)
        setArmFrame(frameName)
    end
end

function uninit()
end
