function init()
    -- some utility commands
    message.setHandler("/abyssplush", function(_,isLocal)
        if not isLocal then return end
        player.giveItem(root.assetJson("/abyssplush.json"))
    end)
    
    message.setHandler("/nickfromname", function(_,isLocal)
        if not isLocal then return end
        chat.command(string.format("/nick %s",player.name()))
    end)
    
    message.setHandler("/back", function(_,isLocal)
        if not isLocal then return end
        player.warp("Return")
        return "Warping back."
    end)
end

function postUpdate()
    if player.getProperty("abyss_configKey") then
        world.sendEntityMessage(player.id(),"abyss_updateFlip")
    end
end
