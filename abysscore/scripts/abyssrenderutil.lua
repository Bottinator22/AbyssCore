
abyssRenderUtil_useVel = true
function generateLineDrawable(s, t) -- does not fill in all the data
    return {line={s, t}}
end
function generatePointDrawable(s, t) -- also does not fill in all the data
    return {poly={
        {s[1]-t,s[2]-t},{s[1]-t,s[2]+t},{s[1]+t,s[2]+t},{s[1]+t,s[2]-t}
    }}
end

local zeroVec = {0,0}
function generateLineDrawable_absolute(as, at) -- relative to self, for localAnimator stuff in things like techs
    local s = world.distance(as,posWithVel())
    local t = world.distance(at,posWithVel())
    return generateLineDrawable(s, t)
end
function generatePointDrawable_absolute(as, t)
    local s = world.distance(as,posWithVel())
    return generatePointDrawable(s,t)
end

function drawCircle(radius, p, settings, layer)
    local points = 30
    local spacing = (math.pi * 2) / points
    for i = 1, points, 1 do
        local angle = spacing * i
        local angle2 = spacing * (i+1)
        local l = generateLineDrawable(
            vec2.add(vec2.withAngle(angle, radius), p),
            vec2.add(vec2.withAngle(angle2, radius), p)
        )
        for k,v in next, settings do
            l[k] = v
        end
        localAnimator.addDrawable(l, layer)
    end
end

local zeroVec = {0,0}
function velOffset()
    if abyssRenderUtil_useVel then
        return vec2.mul(mcontroller.velocity(),script.updateDt())
    else
        return zeroVec
    end
end
function posWithVel()
    return vec2.add(mcontroller.position(),velOffset())
end
function posWithoutVel()
    return vec2.sub(mcontroller.position(),velOffset())
end
