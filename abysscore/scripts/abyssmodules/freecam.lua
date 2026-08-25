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
            freecamStagehand = world.spawnStagehand(mcontroller.position(),"abyss_basic")
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
    if radarFindPlayer then
        message.setHandler("/freecam",function(_,l,c)
            if not l then return "no" end
            local split = {}
            for v in string.gmatch(c,"([^ ]+)") do
                table.insert(split, v)
            end
            if #split <= 0 then
                modules.enableModule(module)
                modules.pressModule(module)
                return
            end
            local targetPos = nil
            local i = split[2]
            if split[1] == "self" then
                targetPos = mcontroller.position()
            elseif split[1] == "interest" then
                if not i then
                    return "Need an interest."
                end
                local interest = radarInterests[i]
                if not interest then
                    return "Can't find an interest of that name."
                end
                if interest[3] ~= player.worldId() then
                    return "That interest isn't on-world."
                end
                targetPos = interest
            elseif split[1] == "player" then
                if not i then
                    return "Need a player."
                end
                local p = radarFindPlayer(i)
                if not p then
                    return "Couldn't find any players of that name."
                end
                if type(p) == "number" then
                    return string.format("There are %d players that fit that name.",p)
                end
                targetPos = p.pos
            else
                return "Not a valid focus type."
            end
            if targetPos then
                if not stagehandExists() then
                    modules.enableModule(module)
                    setEnabled(true)
                end
                world.callScriptedEntity(freecamStagehand,"stagehand.setPosition",targetPos)
            end
        end)
    else
        modules.addPressCommand("/freecam",module)
    end
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
