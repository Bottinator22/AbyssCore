require "/scripts/vec2.lua"
require "/scripts/terra_vec2ref.lua"
-- Probably not the best way to do this... animator exists...
-- This script handles all the particle effects, such as shield particles, spawn particles, firing particles, etc.

local vec2working1 = {0,0}
local vec2working2 = {0,0}
local particleActions = {}
abyssParticles = {} 
function abyssParticles.execute()
      if #particleActions > 0 then
        world.spawnProjectile("invisibleprojectile", entity.position(), entity.id(), {0,0}, false, {
            damageTeam = {type="ghostly"},
            movementSettings={collisionEnabled=false},
            periodicActions=particleActions,
            timeToLive=0.1,
            speed=0
        })
        particleActions = {}
      end
end
function abyssParticles.beamParticles(pos, direction, intensity)
--[[
      for i=1,intensity do
            local duration = 0.5
            local angle = math.random()*math.pi*2
            local particleConfig = {
                    type = "ember",
                    size = 1.0,
                    color = {255,127,127,255},
                    fade = 0.9,
                    destructionAction = "fade",
                    destructionTime = 1.0,
                    initialVelocity = vec2.rotate(vec2.mulToRef(vec2.withAngleToRef(angle, math.random()*10/duration, vec2working1), {0.5,1}, vec2working2), direction),
                    finalVelocity = {0,0},
                    approach={5/duration,5/duration},
                    timeToLive = duration+1,
                    collidesLiquid = false,
                    layer = "front",
                    position = world.distance(pos, entity.position()),
                    variance = {
                        finalVelocity=vec2.rotate({0.5,5},direction),
                        approach={20/duration,20/duration},
                        size = 0.5
                    }
            }
            table.insert(particleActions, {
                action="particle",
                time=0,
                ["repeat"]=false,
                rotate=false,
                specification=particleConfig
            })
      end]]
end
function abyssParticles.shootParticles(pos, intensity, colour)
      for i=1,intensity do
            local duration = 0.5
            local angle = math.random()*math.pi*2
            local particleConfig = {
                    type = "ember",
                    size = 1.0,
                    color = colour,
                    fade = 0.9,
                    destructionAction = "fade",
                    destructionTime = 1.0,
                    initialVelocity = vec2.withAngle(angle, math.random()*10/duration),
                    finalVelocity = {0,0},
                    approach={5/duration,5/duration},
                    timeToLive = duration+1,
                    collidesLiquid = false,
                    layer = "front",
                    position = world.distance(pos, entity.position()),
                    variance = {
                        finalVelocity={5,5},
                        approach={20/duration,20/duration},
                        size = 0.5
                    }
            }
            table.insert(particleActions, {
                action="particle",
                time=0,
                ["repeat"]=false,
                rotate=false,
                specification=particleConfig
            })
      end
end
function abyssParticles.cloudParticles(pos, radius, intensity)
      for i=1,intensity do
            local duration = 0.5
            local angle = math.random()*math.pi*2
            local particleConfig = {
                    type = "textured",
                    image = "/projectiles/status/jumpgas/jumpgas.png:2?setcolor=000000",
                    color = {0,0,0,255},
                    size = 1.0,
                    fade = 0.9,
                    destructionAction = "fade",
                    destructionTime = 1.0,
                    initialVelocity = vec2.withAngle(angle, math.random()*radius/duration),
                    finalVelocity = {0,0},
                    approach={0,0},
                    timeToLive = duration+1,
                    collidesLiquid = false,
                    layer = "back",
                    position = world.distance(pos, entity.position()),
                    variance = {
                    }
            }
            table.insert(particleActions, {
                action="particle",
                time=0,
                ["repeat"]=false,
                rotate=false,
                specification=particleConfig
            })
      end
end
function abyssParticles.healPulseParticles(pos, radius, intensity)
      for i=1,intensity do
            local duration = 0.5
            local angle = math.random()*math.pi*2
            local particleConfig = {
                    type = "ember",
                    size = 1.0,
                    color = {127, 255, 127, 255},
                    fade = 0.9,
                    destructionAction = "fade",
                    destructionTime = 1.0,
                    initialVelocity = vec2.withAngle(angle, math.random()*radius/duration),
                    finalVelocity = {0,0},
                    approach={5/duration,5/duration},
                    timeToLive = duration+1,
                    collidesLiquid = false,
                    layer = "front",
                    position = world.distance(pos, entity.position()),
                    variance = {
                        finalVelocity={5,5},
                        approach={20/duration,20/duration},
                        size = 0.5
                    }
            }
            table.insert(particleActions, {
                action="particle",
                time=0,
                ["repeat"]=false,
                rotate=false,
                specification=particleConfig
            })
      end
end
function abyssParticles.targetedHealParticles(pos, targetpos, radius, intensity)
      local particleConfig2 = {
            type = "ember",
            size = 1.0,
            color = {127, 255, 127, 255},
            fade = 0.9,
            initialVelocity = vec2.mul(vec2.normToRef(world.distance(targetpos, pos), vec2working1), 15),
            finalVelocity = {0.0, 0.0},
            approach = {5.0,5.0},
            destructionAction = "fade",
            destructionTime = 1.0,
            timeToLive = 1,
            collidesLiquid = false,
            layer = "front",
            position = world.distance(pos, entity.position()),
            variance = {
                initialVelocity = {5.0, 5.0},
                finalVelocity = {2.0, 2.0},
                size = 0.5
            }
      }
      for i=1,intensity do
            local duration = 0.5
            local angle = math.random()*math.pi*2
            local particleConfig = {
                    type = "ember",
                    size = 1.0,
                    color = {127, 255, 127, 255},
                    fade = 0.9,
                    destructionAction = "fade",
                    destructionTime = duration/0.9*0.1,
                    initialVelocity = vec2.withAngle(angle, -radius/duration),
                    timeToLive = duration*0.9,
                    collidesLiquid = false,
                    layer = "front",
                    position = vec2.add(world.distance(targetpos, entity.position()),vec2.withAngleToRef(angle, radius, vec2working1)),
                    variance = {
                        size = 0.5
                    }
            }
            table.insert(particleActions, {
                action="particle",
                time=0,
                ["repeat"]=false,
                rotate=false,
                specification=particleConfig2
            })
            table.insert(particleActions, {
                action="particle",
                time=0,
                ["repeat"]=false,
                rotate=false,
                specification=particleConfig
            })
      end
end
function abyssParticles.crackParticles(pos, radius, intensity, positionVariance)
      for i=1,intensity do
            local duration = 0.5
            local angle = math.random()*math.pi*2
            local particleConfig = {
                    type = "ember",
                    size = 1.0,
                    color = {255, 255, 255, 255},
                    fade = 0.9,
                    destructionAction = "fade",
                    destructionTime = 1.0,
                    initialVelocity = vec2.withAngle(angle, math.random()*radius/duration),
                    finalVelocity = vec2.withAngle(angle, math.random()*radius/duration*0.1),
                    approach={5/duration,5/duration},
                    timeToLive = duration+1,
                    collidesLiquid = false,
                    layer = "middle",
                    position = world.distance(pos, entity.position()),
                    variance = {
                        finalVelocity={0,0},
                        position=positionVariance,
                        approach={20/duration,20/duration},
                        size = 0.5
                    }
            }
            table.insert(particleActions, {
                action="particle",
                time=0,
                ["repeat"]=false,
                rotate=false,
                specification=particleConfig
            })
      end
end
function abyssParticles.spawnParticles(pos, radius, intensity)
      for i=1,intensity do
            local duration = 0.5
            local angle = math.random()*math.pi*2
            local particleConfig = {
                    type = "ember",
                    size = 0.1*intensity,
                    color = {0, 0, 0, 255},
                    fade = 0.9,
                    destructionAction = "fade",
                    destructionTime = 1.0,
                    initialVelocity = vec2.withAngle(angle, math.random()*radius/duration),
                    finalVelocity = vec2.withAngle(angle, math.random()*radius/duration*0.1),
                    approach={5/duration,5/duration},
                    timeToLive = duration+1,
                    collidesLiquid = false,
                    layer = "middle",
                    position = world.distance(pos, entity.position()),
                    variance = {
                        finalVelocity={10,10},
                        approach={20/duration,20/duration},
                        size = 0.1*intensity
                    }
            }
            table.insert(particleActions, {
                action="particle",
                time=0,
                ["repeat"]=false,
                rotate=false,
                specification=particleConfig
            })
      end
end
function abyssParticles.despawnParticles(pos, size, radius, intensity)
      for i=1,intensity do
            local duration = 0.5
            local angle = math.random()*math.pi*2
            local particleConfig = {
                    type = "ember",
                    size = 0.1*intensity,
                    color = {0, 0, 0, 255},
                    fade = 0.9,
                    destructionAction = "fade",
                    destructionTime = 1.0,
                    initialVelocity = vec2.withAngle(angle, math.random()*radius/duration),
                    finalVelocity = vec2.withAngle(angle, math.random()*radius/duration*0.1),
                    approach={5/duration,5/duration},
                    timeToLive = duration+1,
                    collidesLiquid = false,
                    layer = "middle",
                    position = world.distance(pos, entity.position()),
                    variance = {
                        finalVelocity={2,2},
                        position={size,size},
                        approach={20/duration,20/duration},
                        size = 0.1*intensity
                    }
            }
            table.insert(particleActions, {
                action="particle",
                time=0,
                ["repeat"]=false,
                rotate=false,
                specification=particleConfig
            })
      end
end
function abyssParticles.shieldParticles(pos, size, radius, intensity)
      for i=1,intensity do
            local duration = 0.5
            local angle = math.random()*math.pi*2
            local particleConfig = {
                    type = "ember",
                    size = 0.1*intensity,
                    color = {255, 0, 0, 127},
                    fade = 0.9,
                    destructionAction = "fade",
                    destructionTime = 1.0,
                    initialVelocity = vec2.withAngle(angle, math.random()*radius/duration),
                    finalVelocity = vec2.withAngle(angle, math.random()*radius/duration*0.1),
                    approach={5/duration,5/duration},
                    timeToLive = duration+1,
                    collidesLiquid = false,
                    layer = "middle",
                    position = world.distance(pos, entity.position()),
                    variance = {
                        finalVelocity={5,5},
                        initialVelocity={1,1},
                        position={size,size},
                        approach={20/duration,20/duration},
                        size = 0.1*intensity
                    }
            }
            table.insert(particleActions, {
                action="particle",
                time=0,
                ["repeat"]=false,
                rotate=false,
                specification=particleConfig
            })
      end
end
function abyssParticles.beamChargeParticles(pos, radius, intensity)
      for i=1,intensity do
            local duration = 0.5
            local angle = math.random()*math.pi*2
            local particleConfig = {
                    type = "ember",
                    size = 1.0,
                    color = {255, 127, 127, 255},
                    fade = 0.9,
                    destructionAction = "fade",
                    destructionTime = duration/0.9*0.1,
                    initialVelocity = vec2.withAngle(angle, -radius/duration),
                    timeToLive = duration*0.9,
                    collidesLiquid = false,
                    layer = "front",
                    position = vec2.add(world.distance(pos, entity.position()),vec2.withAngleToRef(angle, radius, vec2working1)),
                    variance = {
                        size = 0.5
                    }
            }
            table.insert(particleActions, {
                action="particle",
                time=0,
                ["repeat"]=false,
                rotate=false,
                specification=particleConfig
            })
      end
end
function abyssParticles.shockwaveChargeParticles(pos, radius, intensity)
      for i=1,intensity do
            local duration = 0.5
            local angle = math.random()*math.pi*2
            local particleConfig = {
                    type = "ember",
                    size = 1.0,
                    color = {127, 198, 255, 255},
                    fade = 0.9,
                    destructionAction = "fade",
                    destructionTime = duration/0.9*0.1,
                    initialVelocity = vec2.withAngle(angle, -radius/duration),
                    timeToLive = duration*0.9,
                    collidesLiquid = false,
                    layer = "front",
                    position = vec2.add(world.distance(pos, entity.position()),vec2.withAngleToRef(angle, radius, vec2working1)),
                    variance = {
                        size = 0.5
                    }
            }
            table.insert(particleActions, {
                action="particle",
                time=0,
                ["repeat"]=false,
                rotate=false,
                specification=particleConfig
            })
      end
end
function abyssParticles.shockwaveReleaseParticles(pos, radius, intensity)
      for i=1,intensity do
            local duration = 0.5
            local angle = math.random()*math.pi*2
            local particleConfig = {
                    type = "ember",
                    size = 1.0,
                    color = {127, 198, 255, 255},
                    fade = 0.9,
                    destructionAction = "fade",
                    destructionTime = 1.0,
                    initialVelocity = vec2.withAngle(angle, math.random()*radius/duration),
                    finalVelocity = vec2.withAngle(angle, math.random()*radius/duration*0.1),
                    approach={5/duration,5/duration},
                    timeToLive = duration+1,
                    collidesLiquid = false,
                    layer = "front",
                    position = world.distance(pos, entity.position()),
                    variance = {
                        finalVelocity={10,10},
                        approach={20/duration,20/duration},
                        size = 0.5
                    }
            }
            table.insert(particleActions, {
                action="particle",
                time=0,
                ["repeat"]=false,
                rotate=false,
                specification=particleConfig
            })
      end
end
function abyssParticles.teleTargetParticles(pos)
    local size = 1.5
    local particleConfig = {
            type = "ember",
            size = 8,
            color = {0, 0, 0, 255},
            fade = 0.9,
            destructionAction = "fade",
            destructionTime = 1.0,
            initialVelocity = {0,6},
            finalVelocity = {0,0},
            approach={0.1,0.1},
            timeToLive = 0.5,
            collidesLiquid = false,
            layer = "front",
            position = vec2.add(world.distance(pos, entity.position()),{0,-3}),
            variance = {
                initialVelocity={0,3},
                position={size,0},
                size = 3
            }
    }
    table.insert(particleActions, {
        action="particle",
        time=0,
        ["repeat"]=false,
        rotate=false,
        specification=particleConfig
    })
end
function abyssParticles.teleCircleParticles(pos,radius)
    local size = 1.5
    for i=1,5 do
        local angle = math.random()*math.pi*2
        local particleConfig = {
                type = "ember",
                size = 3,
                color = {0, 0, 0, 255},
                fade = 0.9,
                destructionAction = "fade",
                destructionTime = 1.0,
                initialVelocity = {0,0},
                finalVelocity = {0,0},
                approach={0.5,0.5},
                timeToLive = 0.5,
                collidesLiquid = false,
                layer = "front",
                position = vec2.add(world.distance(pos, entity.position()),vec2.withAngle(angle,radius)),
                variance = {
                    size = 2,
                    initialVelocity={0.5,0.5},
                    finalVelocity={0.5,0.5}
                }
        }
        table.insert(particleActions, {
            action="particle",
            time=0,
            ["repeat"]=false,
            rotate=false,
            specification=particleConfig
        })
    end
end
