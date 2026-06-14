require "/scripts/abyssutil.lua"

-- module system for techs that use Abysscore features
-- allows stacking several toggleable modules on one tech with very little connecting logic required
-- (notably, radar, command.)

-- modules are allocated into the necessary slots, they don't necessarily have to be enabled
-- most modules can be fully set up by simply requiring them, they define the binds themselves and should by default use their own binds

-- TODO:
-- system for stuff that touches tech.setParentState maybe?

enabledModules = {
    special=false,
    movement=false,
    fire=false
}
presentModules = {}
modules = {
    directives="",
    parentState=nil
}
function modules.init()
    if not input then
        return
    end
    ensureBasicProxies()
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
    if m.enabled or m.passive then
        m.bindPressed(args)
    end
end
function modules.update(args)
    if not input or not ensureBasicProxies() then
        return
    end
    modules.directives = ""
    modules.parentState = nil
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
function modules.applySuppression()
    -- applies suppression.
    -- techs should implement this their own way if they do anything that might overlap with this
    usingApplyFunc = true
    local toolSuppressed = modules.suppressToolUsage()
    local moveSuppressed = modules.suppressMovement()
    local specialSuppressed = modules.suppressSpecial()
    tech.setToolUsageSuppressed(toolSuppressed)
    tech.setParentDirectives(modules.directives)
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
