require "/scripts/terra_armature/armature.lua"

editableBones = {}
function editable_extraBoneUnselectable(bone,bonecfg,withChildren)
    return false
end
local function processBone(bone)
    local cfg = armatureConfig[bone.name]
    if cfg.unselectable or bone.dummyKeys or bone.inactive or editable_extraBoneUnselectable(bone,cfg,true) then
        return
    end
    if not (editable_extraBoneUnselectable(bone,cfg,false)) and not cfg.exclusiveUnselectable then
        bone.editorData = {
            worldPos={0,0},
            rotation=0,
            offset={0,0},
            scale={1,1},
            overridden=false,
            ikLeaveRot=cfg.ikLeaveRot
        }
        editableBones[bone.name] = bone
    end
    for k,v in next, bone.children do
        processBone(v)
    end
end
local callbacks
local usingMessages = false
function editableInit(useMsgs)
    for k,v in next, rootBones do
        processBone(v)
    end
    usingMessages = useMsgs
    if useMsgs then
        for k,v in next, callbacks do
            message.setHandler(k,function(_,l,...)
                if not l then return end
                return v(...)
            end)
        end
    end
end
function editable_getFacing()
    return facing
end
function editable_getRotation()
    return baseRotation or mcontroller.rotation()
end
function editable_updateBone(boneName)
    local bone = editableBones[boneName]
    local e = bone.editorData
    if not e.overridden then
        e.rotation = mat3.angle(bone.transform)
        local unrotated = mat3.rotate(bone.transform,-e.rotation,bone.center)
        e.offset = mat3.translation(unrotated)
        e.scale = mat3.scaling(unrotated)
    end
    return e
end
function editable_getEditableBones()
    for k,v in next, editableBones do
        local e = v.editorData
        e.worldPos = absolutePos(transformedBoneCenter(v))
    end
    if usingMessages then
        -- TODO: sanitize out circular references to be json-safe
        local out = {}
        return out
    else
        return editableBones
    end
end
function editable_setState(boneName,editorData)
    local bone = editableBones[boneName]
    bone.editorData = editorData
end
function editableApply()
    for k,v in next, editableBones do
        local e = v.editorData
        if e.overridden then
            local mat = v.defaultTransform
            mat = mat3.scale(mat,e.scale,v.center)
            mat = mat3.rotate(mat,e.rotation,v.center)
            mat = mat3.translate(mat,e.offset)
            v.transform = mat
        end
    end
end
callbacks = {
    editable_getFacing=editable_getFacing,
    editable_updateBone=editable_updateBone,
    editable_getEditableBones=editable_getEditableBones,
    editable_setState=editable_setState
}
