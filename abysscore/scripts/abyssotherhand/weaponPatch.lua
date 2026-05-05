local oldFireMode = activeItem.fireMode
local altHeld = false
local swapFireMode = activeItem.hand() == "alt"
function possiblySwappedFireMode(f)
    if swapFireMode then
        if f == "primary" then
            return "alt"
        elseif f == "alt" then
            return "primary"
        else
            return "none"
        end
    else
        return f
    end
end
function activeItem.fireMode()
    if altHeld then
        return possiblySwappedFireMode("alt")
    else
        return possiblySwappedFireMode(oldFireMode())
    end
end
local oldCfgParam = config.getParameter
function config.getParameter(c,d)
    if c == "twoHanded" then
        return true
    else
        return oldCfgParam(c,d)
    end
end
local oldActivate = activate or function() end
function activate(fireMode,shifting,moves)
    oldActivate(dt,possiblySwappedFireMode(fireMode),shifting,moves)
end
local oldUpdate = update or function() end
function update(dt,fireMode,shifting,moves)
    if altHeld then
        fireMode = "alt"
    end
    oldUpdate(dt,possiblySwappedFireMode(fireMode),shifting,moves)
end
local oldSetTwoHandedGrip = activeItem.setTwoHandedGrip
local twoHandedGrip = false
local forcedOneHandedGrip = false
local function updateGrip()
    if forcedOneHandedGrip then
        oldSetTwoHandedGrip(false)
    else
        oldSetTwoHandedGrip(twoHandedGrip)
    end
end
function activeItem.setTwoHandedGrip(h)
    twoHandedGrip = h
    updateGrip()
end
function setForcedOneHandedGrip(h)
    forcedOneHandedGrip = h
    updateGrip()
end
function setAltHeld(h)
    altHeld = h
    return true
end
