require "/scripts/abyssmodules/modules.lua"

local module = {
    moduleSlots={
        movement=true
    }
}
local freecamStagehand = nil
local function setEnabled(mode)
    if mode then
        if freecamStagehand and world.entityExists(freecamStagehand) then
            world.callScriptedEntity(freecamStagehand,"stagehand.die")
        else
            local params = root.assetJson("/scripts/abyssBasicStagehandParams.json")
            freecamStagehand = world.spawnStagehand(mcontroller.position(),"mailbox",params)
        end
    end
end
function module.isBindHeld(args)
    return input.bindHeld("abysscore","toggleFreecam")
end
function module.init()
    modules.addPressCommand("/freecam",module)
end
function module.enable()
end
function module.isActive()
    return not not freecamStagehand
end
function module.bindPressed()
    setEnabled(not freecamStagehand)
end
function module.disable()
    setEnabled(false)
end
function module.updateEnabled(args)
    if freecamStagehand and world.entityExists(freecamStagehand) then
        world.callScriptedEntity(freecamStagehand,"keepAlive")
        
        local pos = world.entityPosition(freecamStagehand)
        
        local s = args.dt
        if args.moves.run   then s = 5*args.dt end
        if args.moves.right then pos[1] = pos[1] + s end
        if args.moves.left  then pos[1] = pos[1] - s end
        if args.moves.up    then pos[2] = pos[2] + s end
        if args.moves.down  then pos[2] = pos[2] - s end
        
        world.callScriptedEntity(freecamStagehand,"stagehand.setPosition",pos)
    end
end
presentModules.armatureEditor = module
