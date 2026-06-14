-- module system for techs that use Abysscore features
-- allows stacking several toggleable modules on one tech with very little connecting logic required
-- (notably, radar, command.)

-- modules are allocated into the necessary slots, they don't necessarily have to be enabled

enabledModules = {
    special=false,
    movement=false,
    fire=false
}
presentModules = {}
modules = {}
function modules.init()
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
function modules.addPressCommand(c,m)
    message.setHandler(c,function(_,l)
        enableModule(m)
        modules.pressModule(m)
    end)
end
local function disableModule(m)
    if not m.enabled then
        return
    end
    if m.disable then
        m.disable()
    end
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
        if enabledModules[s] ~= m then
            disableModule(enabledModules[s])
        end
        enabledModules[s] = m
    end
    m.enabled = true
    if m.enable then
        m.enable()
    end
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
    for k,m in next, presentModules do
        m.updated = false
        local bindHeld = m.isBindHeld(args)
        if bindHeld and not m.wasBindHeld then
            modules.pressModule(m,args)
        end
        if m.update then
            m.update(args)
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
    return enabledModules.movement and enabledModules.movement.isActive()
end
function modules.suppressSpecial()
    return enabledModules.special and enabledModules.special.isActive()
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
end
