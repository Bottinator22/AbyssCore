require "/scripts/abyssmodules/modules.lua"
require "/scripts/abyssradar.lua"

-- radar is a passive module, it doesn't actually use any controls beyond its mode toggle bind
-- also has loads of commands
local module = {
    moduleSlots={},
    passive=true,
    enableMoveKey=nil,
    enableMoveKey_shift=nil
}
local radarMode = 0
radarModule = module
local m = module
function module.isBindHeld(args)
    return safeBindHeld("abysscore","toggleRadar") or (m.enableMoveKey and args.moves[m.enableMoveKey] and (m.enableMoveKey_shift == nil or ((not args.moves.run) == m.enableMoveKey_shift)) and not modules.suppressSpecial())
end
function module.init()
    radarInit()
end
function module.isActive()
    return false
end
function module.bindPressed()
    radarMode = radarMode + 1
    if radarMode > 2 then
        radarMode = 0
    end
end
function module.update(args)
    radarSetVerbose(not args.moves.run)
    radar(radarMode)
end
presentModules.radar = module
