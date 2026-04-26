-- Should be imported by a status script and have adaptStats called.
-- Attempts to figure out this minion's owner and apply stat changes in a few stats from it.
-- Requires the owner to respond to the abyssStatChanges entity message with the necessary data.

local trackedStats = {
    "maxHealth",
    "maxEnergy",
    "powerMultiplier"
}
local stats = {}
function adaptStats(tracked)
    tracked = tracked or trackedStats
    local ownerId = status.statusProperty("playerId") or status.statusProperty("headId") or status.statusProperty("head2Id")
    if not ownerId then return end
    local p = world.sendEntityMessage(ownerId,"abyssStatChanges")
    if not p:succeeded() then return end
    local ownerStats = p:result()
    if not ownerStats then return end
    local i = 0
    for k,v in next, trackedStats do
        i = i + 1
        stats[i] = stats[i] or {stat=v}
        stats[i].effectiveMultiplier = ownerStats[v] or 1
    end
    status.setPersistentEffects("abyssStatChanges",stats)
end
