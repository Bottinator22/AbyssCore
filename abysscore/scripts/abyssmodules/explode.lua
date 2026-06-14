require "/scripts/abyssmodules/modules.lua"

-- explode...
local module = {
    moduleSlots={},
    passive=true,
    directives=""
}
local function playSound(pool)
    world.spawnProjectile("invisibleprojectile",mcontroller.position(),entity.id(),{1,0},true,{
        timeToLive=0.1,
        power=0,
        damageTeam = { type = "ghostly" },
        damageKind = NoDamage,
        periodicActions = {
            {
                time=0,
                ["repeat"]=false,
                action = "sound",
                options = pool
            }
        }
    })
end
local explodeTimer
function module.isBindHeld(args)
    return false--input.bindHeld("abysscore","explode")
end
function module.init()
    modules.addPressCommand("/explode",module)
    radarInit()
end
function module.isActive()
    return false
end
function module.bindPressed()
    if explodeTimer then
        explodeTimer = nil
        module.directives = ""
        return "Un-exploding."
    else
        playSound({"/sfx/tech/mech_explosion_windup.ogg"})
        explodeTimer = 0.5
        return "Exploding."
    end
end
function module.update(args)
    if explodeTimer then
        local explodeDirectives = ""
        if explodeTimer > 0 then
            explodeTimer = explodeTimer - args.dt
            if explodeTimer <= 0 then
                local params = {
                    --[[damageTeam = {
                    type = "enemy",
                    team = 9001
                    }]]
                }
                world.spawnProjectile("mechexplosion", mcontroller.position(), nil, nil, false, params)
                playSound({"/sfx/tech/mech_explosion.ogg"})
                explodeDirectives = "?multiply=00000000"
                explodeTimer = -1
            else
                local fade = 1 - (explodeTimer / 0.5)
                explodeDirectives = string.format("?fade=fcc93c;%.1f", fade)
            end
        else
            explodeDirectives = "?multiply=00000000"
        end
        module.directives = explodeDirectives
    end
end
presentModules.explode = module
