require "/scripts/abyssmodules/modules.lua"

-- invisibility toggle module
local module = {
    moduleSlots={},
    passive=true,
    enableMoveKey=nil,
    parentHidden=false
}
local cloakActive = false
invisibleModule = module
local m = module
function module.isBindHeld(args)
    return input.bindHeld("abysscore","toggleInvisible") or (m.enableMoveKey and args.moves[m.enableMoveKey] and not modules.suppressSpecial())
end
function module.isActive()
    return false
end
function module.bindPressed()
    module.parentHidden = not module.parentHidden
end
presentModules.invisible = module
