
function generateLineDrawable(s, t) -- does not fill in all the data
    return {line={s, t}}
end
function generateLineDrawable_absolute(s, t) -- relative to self, for localAnimator stuff in things like techs
    return {position=vec2.mul(posWithVel(),-1),line={s, t}}
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

function velOffset()
    return vec2.mul(mcontroller.velocity(),script.updateDt())
end
function posWithVel()
    return vec2.add(mcontroller.position(),velOffset())
end
function posWithoutVel()
    return vec2.sub(mcontroller.position(),velOffset())
end
