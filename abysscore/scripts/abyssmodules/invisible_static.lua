require "/scripts/abyssmodules/modules.lua"

-- invisibility toggle module. forbids movement while active
local module = {
    moduleSlots={
        movement=true
    },
    enableMoveKey=nil,
    parentHidden=false
}
local cloakActive = false
invisibleModule = module
local m = module
function module.isBindHeld(args)
    return safeBindHeld("abysscore","toggleInvisible") or (m.enableMoveKey and args.moves[m.enableMoveKey] and not modules.suppressSpecial())
end
function module.isActive()
    return module.parentHidden
end
function module.shouldEnable(args)
    return module.parentHidden
end
function module.bindPressed()
    module.parentHidden = not module.parentHidden
end
presentModules.invisible = module
