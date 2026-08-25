local timer = 0
local block
function init()
    block = config.getParameter("block")
    object.setMaterialSpaces({})
end
function update()
    object.setMaterialSpaces({{{0,0},"metamaterial:lockedDoor"}})
    timer = timer + 1
    if timer > 60 or world.material(block.pos, block.pos[3]) == block.mat then
        object.smash(true)
    end
end
