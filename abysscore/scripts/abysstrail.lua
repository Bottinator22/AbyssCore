require "/scripts/terra_vec2ref.lua" 

-- Not ideal.

trail = {}
local lastPos
local workingVec21 = {0,0}
local workingVec22 = {0,0}
local workingVec23 = {0,0}
local workingVec24 = {0,0}
local mtrails = {}
function trail.init(trails)
    mtrails = trails
end
function trail.update(trails, renderThreshold, predictMult, renderThresholdMax, noLead)
    predictMult=predictMult or 1
    trails = trails or mtrails
    renderThreshold = renderThreshold or 0
    renderThresholdMax = renderThresholdMax or 10
    local actions = {}
    local mainPos = vec2.addToRef(noLead and mcontroller.position() or vec2.addToRef(mcontroller.position(), vec2.divToRef(mcontroller.velocity(), 60,workingVec21),workingVec21), vec2.mulToRef(world.distance(mcontroller.position(), lastPos or mcontroller.position()),predictMult,workingVec22),workingVec21)
    for k,v in next, trails do
        local pos = mainPos
        if v.part then
            pos = vec2.addToRef(mainPos, animator.partPoint(v.part, v.point),workingVec22)
        elseif v.pos then
            pos = vec2.addToRef(mainPos,v.pos,workingVec22)
        end
        local lastPos = v.lastPos or pos
        local mag = world.magnitude(lastPos, pos)
        if mag > renderThreshold and mag < renderThresholdMax then
            local particleConfig = {
                type = "streak",
                size = v.size,
                color = v.color,
                fade = 1.0,
                length=mag*8+1,
                position = world.distance(pos, mainPos),
                destructionAction = "shrink",
                destructionTime = v.time or 1.0,
                initialVelocity = vec2.mul(vec2.normToRef(world.distance(pos, lastPos),workingVec23),0.00001),
                approach = {0, 0},
                timeToLive = 0.1,
                layer = v.layer or "front",
                fullbright = true,
                variance = {
                    size = 0.0,
                    length=0.0
                }
            }
            local action = {
                action="particle",
                time=0,
                ["repeat"]=false,
                rotate=false,
                specification=particleConfig
            }
            table.insert(actions, action)
        end
        v.lastPos = v.lastPos and vec2.copyToRef(pos, v.lastPos) or {pos[1],pos[2]}
    end
    if #actions > 0 then
        world.spawnProjectile("invisibleprojectile", mainPos, entity.id(), {0,0}, false, {
            damageTeam = {type="ghostly"},
            movementSettings={collisionEnabled=false},
            periodicActions=actions,
            timeToLive=0,
            speed=0
        })
    end
    lastPos = mcontroller.position()
end
