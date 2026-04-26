-- Script that integrates energy with the command mode.

function command_energy()
    return status.resource("energy")
end
function command_energyMax()
    return status.resourceMax("energy")
end
function command_energyLocked()
    return status.resourceLocked("energy")
end
function command_energyRegenDelayPerc()
    return status.resourcePercentage("energyRegenBlock")
end
