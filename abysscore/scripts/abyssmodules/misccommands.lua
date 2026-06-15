require "/scripts/abyssmodules/modules.lua"

-- module with a bunch of miscellaneous commands.
-- also aliases some abyssgeneric commands for easier usage
local module = {
    moduleSlots={},
    passive=true
}

function module.isBindHeld(args)
    return false
end
function module.init()
    message.setHandler("/deploy", function(_,l) 
        if not l then
            return "Unauthorized"
        end
        world.sendEntityMessage(entity.id(), "deployMech")
    end)
    message.setHandler("/antinude",function(_,l)
        if not l then return "no" end
        if #status.getPersistentEffects("noNude") > 0 then
            status.clearPersistentEffects("noNude")
            return "No longer blocking nude."
        else
            status.setPersistentEffects("noNude",{{stat="nude",effectiveMultiplier=0}})
            return "Now blocking nude."
        end
    end)
    message.setHandler("/antifalldamage",function(_,l)
        if not l then return "no" end
        if #status.getPersistentEffects("noFallDamage") > 0 then
            status.clearPersistentEffects("noFallDamage")
            return "No longer blocking fall damage."
        else
            status.setPersistentEffects("noFallDamage",{{stat="fallDamageMultiplier",effectiveMultiplier=0}})
            return "Now blocking fall damage."
        end
    end)
    message.setHandler("/antilava",function(_,l)
        if not l then return "no" end
        if #status.getPersistentEffects("noLava") > 0 then
            status.clearPersistentEffects("noLava")
            return "No longer blocking lava."
        else
            status.setPersistentEffects("noLava",{{stat="lavaImmunity",amount=1}})
            return "Now blocking lava."
        end
    end)
    message.setHandler("/antistatus",function(_,l)
        if not l then return "no" end
        if #status.getPersistentEffects("noStatus") > 0 then
            status.clearPersistentEffects("noStatus")
            return "No longer blocking all status effects."
        else
            status.setPersistentEffects("noStatus",{{stat="statusImmunity",amount=1}})
            return "Now blocking all status effects."
        end
    end)
    local function commandAlias(a,b)
        message.setHandler(a,function(_,l,...)
            if not l then return "Unauthorized" end
            return world.sendEntityMessage(entity.id(),b,...):result()
        end)
    end
    commandAlias("/bossbar","/abyssBossbar")
    commandAlias("/emote","/abyssEmote")
    commandAlias("/minion","/abyssMinion")
    commandAlias("/personality","/abyssPersonality")
    commandAlias("/configKey","/abyssConfigKey")
end
function module.isActive()
    return false
end
function module.update(args)
end
presentModules.miscCommands = module
