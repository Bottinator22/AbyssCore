require "/scripts/rect.lua"

local deathTimer = 1
function init()
end
function keepAlive()
    deathTimer = 1
end
function update(dt)
    deathTimer = deathTimer - dt
    if deathTimer < 0 then
        stagehand.die()
        return
    end
end
