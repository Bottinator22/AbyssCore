require "/scripts/vec2.lua"

function buildHolder(i,owner,core)
    local id = i
    if type(i) == "string" then
        id = {name=i,count=1,parameters={}}
    end
    local params = sb.jsonMerge(root.assetJson("/scripts/abyssBasicParams.json"), root.assetJson("/scripts/abyssholder/params.json"))
    local partBase = {
        properties={
            anchorPart="itemAnchor",
            zLevel=41,
            image="/assetmissing.png"
        }
    }
    local size = 0
    local extraParts = {}
    local itemConfig = root.itemConfig(i)
    local completeItemConfig = sb.jsonMerge(itemConfig.config, itemConfig.parameters)
    local icon = completeItemConfig.inventoryIcon or "/assetmissing.png"
    if type(icon) == "string" then
        -- just a path to an image
        if string.sub(icon,1,1) ~= "/" then
            icon = itemConfig.directory..icon
        end
        local imgSize = root.imageSize(icon)
        size = math.max(imgSize[1],imgSize[2])/8
        partBase.properties.image = icon
        extraParts.item = partBase
    else
--[[ example advanced inventory icon, list of drawables
[{
"image" : "/items/active/weapons/ranged/machinepistol/butt/14.png?replace=808080=787784?replace=e35f5d=cb13ff?replace=404040=33343c?replace=b22042=9b1dcf?replace=606060=4f545a?replace=871132=580682?replace=808080=787784?replace=e35f5d=cb13ff?replace=404040=33343c?replace=b22042=9b1dcf?replace=606060=4f545a?replace=871132=580682",
"position" : [2, 0]
}, {
"image" : "/items/active/weapons/ranged/machinepistol/middle/13.png?replace=808080=787784?replace=e35f5d=cb13ff?replace=404040=33343c?replace=b22042=9b1dcf?replace=606060=4f545a?replace=871132=580682?replace=808080=787784?replace=e35f5d=cb13ff?replace=404040=33343c?replace=b22042=9b1dcf?replace=606060=4f545a?replace=871132=580682",
"position" : [8.5, 0]
}, {
"image" : "/items/active/weapons/ranged/machinepistol/barrel/15.png?replace=808080=787784?replace=e35f5d=cb13ff?replace=404040=33343c?replace=b22042=9b1dcf?replace=606060=4f545a?replace=871132=580682?replace=808080=787784?replace=e35f5d=cb13ff?replace=404040=33343c?replace=b22042=9b1dcf?replace=606060=4f545a?replace=871132=580682",
"position" : [17, 0]
}]

being drawables, they can most likely also accept transformations
but no
--]]
        local iconRect = {0,0,1,1}
        for k,v in next, icon do
            local img = v.image
            if string.sub(img,1,1) ~= "/" then
                img = itemConfig.directory..img
            end
            v.img = img
            local rect = root.nonEmptyRegion(img)
            if rect then
                local rectOffset = {(rect[3]+rect[1])*-0.5,(rect[4]+rect[2])*-0.5}
                if v.position then
                    rect[1] = rect[1] + v.position[1]
                    rect[2] = rect[2] + v.position[2]
                    rect[3] = rect[3] + v.position[1]
                    rect[4] = rect[4] + v.position[2]
                end
                iconRect[1] = math.min(iconRect[1],rect[1]+rectOffset[1])
                iconRect[2] = math.min(iconRect[2],rect[2]+rectOffset[2])
                iconRect[3] = math.max(iconRect[3],rect[3]+rectOffset[1])
                iconRect[4] = math.max(iconRect[4],rect[4]+rectOffset[2])
            end
        end
        -- center rect
        local iconSize = {iconRect[3]-iconRect[1],iconRect[4]-iconRect[2]}
        local centerOffset = {(iconRect[3]+iconRect[1])*-0.5,(iconRect[4]+iconRect[2])*-0.5}
        for k,v in next, icon do
            local part = sb.jsonMerge({},partBase)
            part.properties.image = v.img
            part.properties.centered = true
            part.properties.zLevel = 40+k
            if v.position then
                part.properties.offset = vec2.div(vec2.add(v.position,centerOffset),8)
            end
            extraParts[string.format("itemPart%.0f",k)] = part
        end
        size=math.max(iconSize[1],iconSize[2])/8
    end
    params = sb.jsonMerge(params, {
        ownerId=owner or entity.id(),
        coreId=core or entity.id(),
        heldItem=id,
        itemSize=size,
        animationCustom={
            animatedParts={
                parts=extraParts
            }
        }
    })
    return params
end
