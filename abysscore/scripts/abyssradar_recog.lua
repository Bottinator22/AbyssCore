
local function recogEnabled()
    return not root.getConfiguration("abyss_ignoreRecog")
end
local function dpcPresent()
    return not not root.assetOrigin("/interface/scripted/starcustomchat/plugins/dynamicprox/dynamicprox.json")
end

function playerKnown(u)
    if u == entity.uniqueId() then
        return true
    end
    if not recogEnabled() then
        return true
    end
    if dpcPresent() then
        return not not player.getProperty("DPC::recognizedPlayers")[u]
    end
    return true
end
function playerAlias(u)
    if u == entity.uniqueId() then
        return nil
    end
    if not recogEnabled() then
        return nil
    end
    if dpcPresent() then
        local recogCfg = player.getProperty("DPC::recognizedPlayers")[u]
        if recogCfg then
            return recogCfg.savedName
        else
            return root.getConfiguration("abyss_unknownAlias") or "Unknown"
        end
    end
end
