require "/scripts/abyssmodules/modules.lua"

-- automatic walking and ducking.
local module = {
    moduleSlots={},
    passive=true
}
local duckMode = false
local walkMode = false

function module.isBindHeld(args)
    return false
end
function module.init()
    message.setHandler("/duck",function(_,l)
        if not l then return "no" end
        duckMode = not duckMode
    end)
    message.setHandler("/walk",function(_,l)
        if not l then return "no" end
        walkMode = not walkMode
    end)
end
function module.isActive()
    return false
end
function module.update(args)
    if duckMode then
        mcontroller.controlCrouch()
    end
    if walkMode then
        mcontroller.controlModifiers({
            runningSuppressed=true
        })
    end
end
presentModules.autoDuckWalk = module
