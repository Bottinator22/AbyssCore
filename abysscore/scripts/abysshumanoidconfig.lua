
local lastMergedConfigName
local function mergeConfigs(iocfg,key)
    local cfg = player.getProperty(key)
    if cfg then
        if cfg.parent then
            iocfg = mergeConfigs(iocfg,cfg.parent)
        end
        iocfg = sb.jsonMerge(iocfg,cfg)
    end
    return iocfg
end
function mergeAbyssConfig()
    local keys = player.getProperty("abyss_configKeys")
    if keys then
        local sorted = {}
        for k,v in next, keys do
            table.insert(sorted,v)
        end
        table.sort(sorted,function(a,b)
            return a.priority < b.priority
        end)
        local merged = {}
        for _,v in next, sorted do
            if v.key then
                merged = mergeConfigs(merged,v.key)
            end
        end
        player.setProperty("abyss_mergedConfig",merged)
    else
        player.setProperty("abyss_mergedConfig",nil)
    end
end

function getAbyssConfig()
    local name = getAbyssConfigName()
    if name ~= lastMergedConfigName then
        lastMergedConfigName = name
        mergeAbyssConfig()
    end
    return player.getProperty("abyss_mergedConfig")
end

-- a hash might work better, but whatever
function getAbyssConfigName()
    if player.getProperty("abyss_configKey") and not player.getProperty("abyss_configKeys") then
        sb.logInfo("Abysscore: updating old character to multi-key system")
        player.setProperty("abyss_configKeys",{
            main={key=player.getProperty("abyss_configKey"),priority=0}
        })
        player.setProperty("abyss_configKey")
    end
    local keys = player.getProperty("abyss_configKeys")
    if keys then
        -- don't like doing this multiple times a frame... at least it's not likely to be TOO much work, this list is most likely just going to be under 10 things
        local sorted = {}
        for k,v in next, keys do
            table.insert(sorted,v)
        end
        table.sort(sorted,function(a,b)
            return a.priority < b.priority
        end)
        local out = ""
        local first = true
        for _,v in next, sorted do
            if v.key then
                if first then
                    first = false
                else
                    out = out..";"
                end
                out = out..v.key
            end
        end
        return out
    end
end

local lastFacing
local lastConfigName
function updateConfigAndFlip()
    local configName = getAbyssConfigName()
    local facing = (player.facingDirection or mcontroller.facingDirection)()
    if configName and (configName ~= lastConfigName or lastFacing ~= facing) then
        local cfg = getAbyssConfig()
        local identityOverride = nil
        if cfg then
            if facing < 0 then
                identityOverride = cfg.flip
            else
                identityOverride = cfg.base
            end
            if cfg.both then
                if identityOverride then
                    identityOverride = sb.jsonMerge(cfg.both,identityOverride)
                else
                    identityOverride = cfg.both
                end
            end
        end
        if identityOverride then
            player.setHumanoidIdentity(sb.jsonMerge(player.humanoidIdentity(),identityOverride))
        end
    end
    lastConfigName = configName
    lastFacing = facing
end

local function keysUpdated()
    world.sendEntityMessage(player.id(),"abyssbasic_updateLight")
    local cfg = getAbyssConfig()
    if cfg and cfg.name then
        player.setName(cfg.name)
    end
end

function initConfigKeyCommands()
    local aliases = player.getProperty("abyss_configAliases")
    if aliases then
        for k,v in next, aliases do
            message.setHandler(k,function(_,l,c)
                if not l then
                    return "Unauthorized"
                end
                local key = v.key
                local value
                local out
                if #c > 0 then
                    value = v.prefix..c
                    if player.getProperty(value) then
                        out = string.format("Set aliased config key '%s' to '%s'.",key,c)
                    else
                        return string.format("No data defined at alias '%s' key for '%s'. (%s)",key,c,value)
                    end
                else
                    value = v.default
                    out = string.format("Reset aliased config key '%s' to default.",key)
                end
                local keys = player.getProperty("abyss_configKeys") or {}
                keys[key].key = value
                player.setProperty("abyss_configKeys",keys)
                keysUpdated()
                return out
            end)
            if v.resetOnInit then
                local key = v.key
                local value = v.default
                local keys = player.getProperty("abyss_configKeys") or {}
                keys[key].key = value
                player.setProperty("abyss_configKeys",keys)
            end
        end
    end
    message.setHandler("/abyssConfigKey", function(_,l,c) 
        if not l then
            return "Unauthorized"
        end
        if #c == 0 then
            return "Need a key and a priority or value."
        end
        local identity = player.getProperty("abyss_origIdentity")
        if not identity then
            return "Need to define an original identity first before config keys can be used."
        end
        local keys = player.getProperty("abyss_configKeys") or {}
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        local key = "main"
        local value = nil
        if #split > 1 then
            key = split[1]
            value = split[2]
        else
            return "Need a key and a priority or value."
        end
        player.setHumanoidIdentity(player.getProperty("abyss_origIdentity"))
        if value and tonumber(value) then
            local priority = tonumber(value)
            if not keys[key] then
                keys[key] = {priority=priority}
                player.setProperty("abyss_configKeys",keys)
                keysUpdated()
                return string.format("Defined a new config key %s with priority %s.",key,priority)
            else
                keys[key].priority = priority
                player.setProperty("abyss_configKeys",keys)
                keysUpdated()
                return string.format("Set config key %s to priority %s.",key,priority)
            end
        else
            if not keys[key] then
                return string.format("Config key %s not defined, need to define one manually.",key)
            end
            keys[key].key = value
        end
        player.setProperty("abyss_configKeys",keys)
        keysUpdated()
        if not value then
            return string.format("Reset config key %s.",key)
        else
            if player.getProperty(value) then
                return string.format("Set config key %s to '%s'.",key,value)
            else
                return string.format("Set config key %s to '%s'. Nothing defined at this key.",key,value)
            end
        end
    end)
    message.setHandler("/abyssRefreshConfig",function(_,l)
        if not l then return end
        keysUpdated()
        lastMergedConfigName = nil
        lastConfigName = nil
    end)
    keysUpdated()
end
