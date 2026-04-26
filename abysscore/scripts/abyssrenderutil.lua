
function generateLineDrawable(s, t) -- does not fill in all the data
    return {line={s, t}}
end
function generateLineDrawable_absolute(s, t) -- relative to self, for localAnimator stuff in things like techs
    return {position=vec2.mul(posWithVel(),-1),line={s, t}}
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
