require "/scripts/abyssmodules/modules.lua"
require "/scripts/abysscommand.lua"

local commandMode = false
local function setCommandEnabled(mode)
    if commandMode ~= mode then
        commandMode = mode
        if commandMode then
            command.init()
        else
            command.uninit()
        end
    end
end
commandModule = {
    moduleSlots={
        special=true,
        fire=true
    },
    enableMoveKey=nil
}
local m = commandModule
function commandModule.isBindHeld(args)
    return safeBindHeld("abysscore","toggleCommand") or (m.enableMoveKey and args.moves[m.enableMoveKey])
end
function commandModule.enable()
end
function commandModule.isActive()
    return commandMode
end
function commandModule.bindPressed(args)
    if args.moves.run or not commandMode then
        setCommandEnabled(not commandMode)
    else
        command.togglePause()
    end
end
function commandModule.disable()
    setCommandEnabled(false)
end
function commandModule.updateEnabled(args)
    if commandMode then
        command.update(args)
    end
end
presentModules.command = commandModule
