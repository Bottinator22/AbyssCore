require "/scripts/terra_vec2ref.lua"
require "/scripts/abyssutil.lua"
require "/scripts/abysshumanoidconfig.lua"

require "/scripts/abyssmodules/command.lua"
require "/scripts/abyssmodules/radar.lua"
require "/scripts/abyssmodules/freecam.lua"
require "/scripts/abyssmodules/explode.lua"
require "/scripts/abyssmodules/faceandteleport.lua"
require "/scripts/abyssmodules/sitandlock.lua"
require "/scripts/abyssmodules/misccommands.lua"
require "/scripts/abyssmodules/autoduckwalk.lua"
require "/scripts/abyssmodules/vehicle.lua"

function init()
    if not input then
        return
    end
    
    local ignoreSpecial = config.getParameter("ignoreSpecial",false)
    if not ignoreSpecial then
        commandModule.enableMoveKey = "special1"
        radarModule.enableMoveKey = "special3"
    end
    modules.init()
end

local lastParentState
local lastToolSuppressed
local lastDirectives
function update(args)
    modules.update(args)
    modules.applySuppression()
end
function uninit()
    modules.uninit()
end
 
