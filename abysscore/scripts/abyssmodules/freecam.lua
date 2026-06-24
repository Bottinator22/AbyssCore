require "/scripts/abyssmodules/modules.lua"

-- simple freecam module

local module = {
    moduleSlots={
        movement=true
    }
}
local freecamStagehand = nil
local function stagehandExists()
    return not not (freecamStagehand and world.entityExists(freecamStagehand))
end
local function setEnabled(mode)
    local exists = stagehandExists()
    if mode and not exists then
        if world.entity then
            local params = root.assetJson("/scripts/abyssBasicStagehandParams.json")
            freecamStagehand = world.spawnStagehand(mcontroller.position(),"mailbox",params)
            player.setCameraFocusEntity(freecamStagehand)
        end
    elseif exists then
        world.callScriptedEntity(freecamStagehand,"stagehand.die")
    end
end
function module.isBindHeld(args)
    return safeBindHeld("abysscore","toggleFreecam")
end
function module.init()
    modules.addPressCommand("/freecam",module)
end
function module.enable()
end
--[[
function module.isActive()
    return stagehandExists()
end]]
module.isActive = stagehandExists
freecamModule = module
function module.bindPressed()
    setEnabled(not stagehandExists())
end
function module.disable()
    setEnabled(false)
end
function module.updateEnabled(args)
    if stagehandExists() then
        world.callScriptedEntity(freecamStagehand,"keepAlive")
        
        local pos = world.entityPosition(freecamStagehand)
        
        local s = 200*args.dt
        if args.moves.run   then s = 40*args.dt end
        if args.moves.right then pos[1] = pos[1] + s end
        if args.moves.left  then pos[1] = pos[1] - s end
        if args.moves.up    then pos[2] = pos[2] + s end
        if args.moves.down  then pos[2] = pos[2] - s end
        
        world.callScriptedEntity(freecamStagehand,"stagehand.setPosition",pos)
    end
end
function module.cameraToPos(pos)
    modules.enableModule(module)
    setEnabled(true)
    if stagehandExists() then
        world.callScriptedEntity(freecamStagehand,"stagehand.setPosition",pos)
    end
end
presentModules.freecam = module
