
local objs = assets.byExtension("object")
local uniqueObjects = {}
local collisionNames = {}
for _,v in next, objs do
  local obj = assets.json(v)
  if obj.uniqueId then
    local k = obj.uniqueId
    local existingName = uniqueObjects[k]
    local name = obj.shortdescription
    if existingName then
        collisionNames[k] = collisionNames[k] or {[existingName]=1}
        if collisionNames[k][name] then
            collisionNames[k][name] = collisionNames[k][name] + 1
        else
            collisionNames[k][name] = 1
        end
    else
        uniqueObjects[k] = name
    end
  end
end
for k,l in next, collisionNames do
    local highestName
    local highestNameAmount = 0
    for name,num in next, l do
        if num > highestNameAmount then
            highestName = name
            highestNameAmount = num
        end
    end
    uniqueObjects[k] = highestName
end
assets.add("/scripts/abyssUniqueObjects.json", uniqueObjects)
 
