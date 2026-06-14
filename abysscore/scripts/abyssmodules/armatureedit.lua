require "/scripts/abyssmodules/modules.lua"
require "/scripts/abyssarmatureedit/editor.lua"

local module = {
    moduleSlots={
        special=true,
        fire=true
    },
    entity=nil
}
local editor = false
local function setEnabled(mode)
    if editor ~= mode then
        editor = mode
        if editor then
            armatureedit.init(module.entity)
        else
            armatureedit.uninit()
        end
    end
end
armatureEditModule = module
function module.isBindHeld(args)
    return input.bindHeld("abysscore","toggleArmatureEdit")
end
function module.enable()
end
function module.isActive()
    return editor
end
function module.bindPressed(args)
    setEnabled(not editor)
end
function module.disable()
    setEnabled(false)
end
function module.updateEnabled(args)
    if editor then
        armatureedit.update(args)
    end
end
presentModules.armatureEditor = module
