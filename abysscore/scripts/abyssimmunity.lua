require "/scripts/util.lua"

-- Intended to filter out non-positive status effects.
-- Should take as many mods into account as possible.
-- The config includes both a generic whitelist that directly specifies status effects considered positive,
-- and a list of strings that, if present in a status effect's internal name, makes it considered positive.
 
abyssStatusImmunity = {}
local asconfig
local whitelist
local finds
local function isImmune(effect)
    if not asconfig then
        asconfig = root.assetJson("/abyssimmunity.config")
        whitelist = {}
        for k,v in next, asconfig.whitelist do
            whitelist[v] = true
        end
        finds = asconfig.finds
    end
    if whitelist[effect] then
        return false
    end
    for k,v in next, finds do
        if type(v) == "string" then
            if string.find(effect,v) then
                return false
            end
        elseif type(v) == "table" then
            local d = true
            for k2,v2 in next, v do
                if not string.find(effect,v2) then
                    d = false
                    break
                end
            end
            if d then
                return false
            end
        end
    end
    return true
end
function abyssStatusImmunity.isImmune(effect)
    if type(effect) == "string" then
        return isImmune(effect)
    elseif type(effect) == "table" then
        if effect.effect then
            return isImmune(effect.effect)
        elseif effect.stat then
            -- check if we should resist this stat change
            local val = effect.amount or effect.baseMultiplier-1 or effect.effectiveMultiplier-1
            -- ignore negative or invalid stat changes
            if val > 0 and val < 10^15 then
                return false
            else
                return true
            end
        else
            return true
        end
    else
        return true -- may prevent errors
    end
end
function abyssStatusImmunity.filter(effects)
    local out = {}
    for k,v in next, effects do
        if not abyssStatusImmunity.isImmune(v) then
            table.insert(out, v)
        end
    end
    return out
end
function abyssStatusImmunity.update()
    for k,v in next, status.activeUniqueStatusEffectSummary() do
        if isImmune(v[1]) then
            status.removeEphemeralEffect(v[1])
        end
    end
end
