require "/scripts/abyssmodules/modules.lua"

-- invisibility toggle module. may forbid movement while active
local module = {
    moduleSlots={},
    passive=true,
    enableMoveKey=nil,
    parentHidden=false
}
local wasStatic = false
local cloakActive = false
invisibleModule = module
local m = module
function module.isBindHeld(args)
    return safeBindHeld("abysscore","toggleInvisible") or (m.enableMoveKey and args.moves[m.enableMoveKey] and not modules.suppressSpecial())
end
function module.isActive()
    return module.parentHidden and not module.passive
end
function module.shouldEnable(args)
    return module.parentHidden and not module.passive
end
function module.bindPressed()
    module.parentHidden = not module.parentHidden
end
function module.setStatic(s)
    if s ~= wasStatic then
        wasStatic = s
    else
        return
    end
    modules.disableModule(module)
    if s then
        module.moduleSlots.movement = true
        module.passive = false
    else
        module.moduleSlots.movement = nil
        module.passive = true
    end
end
presentModules.invisible = module
