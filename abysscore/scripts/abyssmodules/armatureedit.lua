require "/scripts/abyssmodules/modules.lua"
require "/scripts/abyssarmatureedit/editor.lua"

-- armature editor module, targets the nearest editable entity
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
        if mode then
            local e = world.entityQuery(tech.aimPosition(),300,{callScript="armature_editable",order="nearest"})[1] or module.entity
            if not e or not world.entityExists(e) then
                localAnimator.playAudio("/sfx/interface/clickon_error.ogg")
                module.entity = nil
            else
                editor = true
                module.entity = e
                armatureedit.init(e)
            end
        else
            editor = false
            armatureedit.uninit()
        end
    end
end
armatureEditModule = module
function module.isBindHeld(args)
    return safeBindHeld("abysscore","toggleArmatureEdit")
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
