require "/scripts/abyssutil.lua"

-- module system for techs that use Abysscore features
-- allows stacking several toggleable modules on one tech with very little connecting logic required
-- (notably, radar, command.)

-- modules are allocated into the necessary slots, they don't necessarily have to be enabled
-- most modules can be fully set up by simply requiring them, they define the binds themselves and should by default use their own binds

function safeBindHeld(...)
    return input and input.bindHeld(...)
end

enabledModules = {
    special=false,
    movement=false,
    fire=false
}
presentModules = {}
modules = {
    directives="",
    parentState=nil,
    parentHidden=false
}
function modules.init()
    ensureBasicProxies()
    mcontroller.setAutoClearControls(true)
    -- message handlers for interaction by other techs and items
    message.setHandler("abyssModules_suppressToolUsage",function(_,l)
        if l then return modules.suppressToolUsage() end
    end)
    message.setHandler("abyssModules_suppressMovement",function(_,l)
        if l then return modules.suppressMovement() end
    end)
    message.setHandler("abyssModules_suppressSpecial",function(_,l)
        if l then return modules.suppressSpecial() end
    end)
    
    message.setHandler("/modules",function(_,l)
        if not l then return "nuh uh" end
        local out = "Loaded modules:"
        for k,m in next, presentModules do
            local status
            if m.passive then
                status = "passive"
            elseif m.enabled then
                status = "active ("
                local f = true
                for s,_ in next, m.moduleSlots do
                    if f then
                        f = false
                    else
                        status = status..","
                    end
                    status = status..s
                end
                status = status..")"
            else
                status = "inactive"
            end
            out = out..string.format("\n%s (%s)",k,status)
        end
        return out
    end)
    
    for k,m in next, presentModules do
        if m.init then
            m.init()
        end
    end
end
function modules.loadModule(p)
    -- loads a new module, allows adding new modules after init.
    local oldModules = {}
    for k,v in next, presentModules do
        oldModules[k] = true
    end
    require(p)
    for k,v in next, presentModules do
        if v.init and not oldModules[k] then
            v.init()
        end
    end
end
local function disableModule(m)
    if not m.enabled then
        return
    end
    if m.disable then
        m.disable()
    end
    m.enabled = false
    for s,_ in next, m.moduleSlots do
        enabledModules[s] = false
    end
end
local function enableModule(m)
    -- force enables a module
    -- also disables all modules overlapping this one
    if m.enabled or m.passive then
        return
    end
    for s,_ in next, m.moduleSlots do
        if enabledModules[s] ~= m and enabledModules[s] then
            disableModule(enabledModules[s])
        end
        enabledModules[s] = m
    end
    m.enabled = true
    if m.enable then
        m.enable()
    end
end
function modules.addPressCommand(c,m)
    message.setHandler(c,function(_,l)
        enableModule(m)
        modules.pressModule(m)
    end)
end
modules.enableModule = enableModule
function modules.tryEnableModule(m)
    -- check if it overlaps an existing, active module, enable it if it does, do nothing if it doesn't
    if m.passive then
        return true
    end
    local valid = true
    for s,_ in next, m.moduleSlots do
        if enabledModules[s] and enabledModules[s].isActive() then
            valid = false
            break
        end
    end
    m.enabled = false
    if valid then
        enableModule(m)
    end
    return valid
end

function modules.pressModule(m,args)
    if not m.enabled then
        modules.tryEnableModule(m)
    end
    if (m.enabled or m.passive) and m.bindPressed then
        m.bindPressed(args)
    end
end
function modules.update(args)
    if not ensureBasicProxies() then
        return
    end
    modules.directives = ""
    modules.parentState = nil
    modules.parentHidden = false
    for k,m in next, presentModules do
        m.updated = false
        local bindHeld = m.isBindHeld and m.isBindHeld(args)
        local shouldEnable = m.shouldEnable and m.shouldEnable(args)
        if bindHeld and not m.wasBindHeld then
            modules.pressModule(m,args)
        elseif shouldEnable and not m.enabled then -- for things such as a 'sit mode' module which needs to re-enable when sitting and trying to move.
            modules.tryEnableModule(m)
        end
        if m.update then
            m.update(args)
        end
        if m.directives then
            modules.directives = modules.directives..m.directives
        end
        if m.parentState then
            modules.parentState = m.parentState
        end
        if m.parentHidden then
            modules.parentHidden = true
        end
        m.wasBindHeld = bindHeld
    end
    for s,m in next, enabledModules do
        if m and not m.updated then
            if m.updateEnabled then
                m.updateEnabled(args)
            end
            m.updated = true
        end
    end
end
function modules.suppressToolUsage()
    return enabledModules.fire and enabledModules.fire.isActive() and (not enabledModules.fire.suppressToolUsage or enabledModules.fire.suppressToolUsage())
end
function modules.suppressCustomFire()
    return enabledModules.fire and enabledModules.fire.isActive()
end
function modules.suppressMovement()
    return enabledModules.movement and enabledModules.movement.isActive() and (not enabledModules.movement.suppressMovement or enabledModules.movement.suppressMovement())
end
function modules.suppressCustomMovement()
    return enabledModules.movement and enabledModules.movement.isActive()
end
function modules.suppressSpecial()
    return enabledModules.special and enabledModules.special.isActive()
end
local usingApplyFunc = false
local lastParentState
local lastParentHidden
local lastToolSuppressed
local lastDirectives
function modules.applySuppression()
    -- applies suppression.
    -- techs should implement this their own way if they do anything that might overlap with this
    if not usingApplyFunc then
        usingApplyFunc = true
        message.setHandler("abyss_parentState",function(_,l)
            if not l then return "nuh uh" end
            return modules.parentState
        end)
    end
    local toolSuppressed = modules.suppressToolUsage()
    local moveSuppressed = modules.suppressMovement()
    if toolSuppressed ~= lastToolSuppressed then
        tech.setToolUsageSuppressed(toolSuppressed)
        lastToolSuppressed = toolSuppressed
    end
    if modules.directives ~= lastDirectives then
        tech.setParentDirectives(modules.directives)
        lastDirectives = modules.directives
    end
    if modules.parentHidden ~= lastParentHidden then
        tech.setParentHidden(modules.parentHidden)
        lastParentHidden = modules.parentHidden
    end
    if modules.parentState ~= lastParentState then
        tech.setParentState(modules.parentState)
        lastParentState = modules.parentState
    end
    if moveSuppressed then
        mcontroller.controlModifiers({
            movementSuppressed=true
        })
    end
end
function modules.uninit()
    for s,m in next, enabledModules do
        if m then
            disableModule(m)
        end
    end
    for k,m in next, presentModules do
        if m.uninit then
            m.uninit()
        end
    end
    if usingApplyFunc then
        tech.setToolUsageSuppressed(false)
        tech.setParentDirectives()
        tech.setParentState()
    end
end
