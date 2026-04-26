-- If imported via require, this handles abysscommand shield integration for you conveniently.
-- As long as shield health is shieldHealth.
-- Note that this assumes the shields work like Abyssal Response shields, which do not recharge naturally.

function command_shield()
    return status.resource("shieldHealth")
end
function command_shieldMax()
    return status.resourceMax("shieldHealth")
end
function command_shieldLocked()
    return status.resourceLocked("shieldHealth")
end
function command_shieldRegenDelayPerc()
    return 0
end
