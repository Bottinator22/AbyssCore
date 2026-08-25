
local interests = {}

local function saveInterests()
    if root.setConfiguration then
        root.setConfiguration("abyss_radarInterests",interests)
    else
        player.setProperty("radarInterests",interests)
    end
end
local function newInterestColour()
    local interestN = 0
    for k,v in next, interests do
        interestN = interestN + 1
    end
    local n = #radarColours
    local i = ((interestN-1)%n)+1
    return radarColours[i]
end

radarInterestDefaultNoteDistance = 5

radarInterests = interests
function radarInterestInit()
    interests = (root.getConfiguration and root.getConfiguration("abyss_radarInterests")) or player.getProperty("radarInterests") or {}
    radarInterests = interests
    if root.getConfiguration then
        local pri = player.getProperty("radarInterests")
        if pri then
            for k,v in next, pri do
                interests[k] = v
            end
            player.setProperty("radarInterests",nil)
            saveInterests()
        end
    end
    message.setHandler("/radarInterestColour",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #split < 4 then
            return "Usage: /radarInterestColour <interest> <R> <G> <B> [A]"
        end
        local interest = interests[split[1]]
        if not interest then
            return "No interest detected with that name."
        end
        interest[4].colour = {tonumber(split[2]),tonumber(split[3]),tonumber(split[4]),split[5] and tonumber(split[5])}
        interests[split[1]] = interest
        saveInterests()
        return string.format("Recoloured interest %s",split[1])
    end)
    message.setHandler("/radarCreateInterest",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #split == 0 or #c == 0 then
            return "Usage: /radarCreateInterest <interest>"
        end
        if #split > 1 then
            return "Interest name cannot have spaces."
        end
        local exists = not not interests[c]
        local old = interests[c]
        local interest = mcontroller.position()
        interest[3] = player.worldId()
        interest[4] = old and old[4] or {
            colour=newInterestColour()
        }
        interests[c] = interest
        saveInterests()
        return string.format("%s interest %s",exists and "Moved" or "Created",c)
    end)
    message.setHandler("/radarRemoveInterest",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #split == 0 or #c == 0 then
            return "Usage: /radarRemoveInterest <interest>"
        end
        if #split > 1 then
            return "Interest name cannot have spaces."
        end
        if not interests[c] then
            return "No interest detected with that name."
        end
        interests[c] = nil
        saveInterests()
        return string.format("Deleted interest %s",c)
    end)
    message.setHandler("/radarGotoInterest",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #split == 0 or #c == 0 then
            return "Usage: /radarGotoInterest <interest>"
        end
        if #split > 1 then
            return "Interest name cannot have spaces."
        end
        if not interests[c] then
            return "No interest detected with that name."
        end
        local interest = interests[c]
        if interest[3] == player.worldId() then
            mcontroller.setPosition(interest)
            mcontroller.setVelocity({0,0})
            return string.format("Teleported to interest %s",c)
        else
            player.warp(string.format("%s=%d.%d",interest[3],math.floor(interest[1]),math.floor(interest[2])))
            return string.format("Warping to interest %s",c)
        end
    end)
    message.setHandler("/radarInterestRadius",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #split < 1 or #c == 0 then
            return "Usage: /radarInterestRadius <interest> [radius]"
        end
        if #split > 2 then
            return "Interest name cannot have spaces."
        end
        local i = split[1]
        local interest = interests[i]
        if not interest then
            return "No interest detected with that name."
        end
        if split[2] then
            local n = tonumber(split[2])
            if not n then
                return "Could not parse radius."
            end
            interest[4].radius = n
            saveInterests()
            return string.format("Set interest %s radius to %.1f.",i,n)
        else
            interest[4].radius = nil
            saveInterests()
            return string.format("Reset interest %s radius.",i)
        end
    end)
    message.setHandler("/radarInterestBox",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #split < 1 or #c == 0 or (#split >= 2 and #split < 5) then
            return "Usage: /radarInterestBox <interest> [<x1> <y1> <x2> <y2>]"
        end
        if #split > 5 then
            return "Interest name cannot have spaces."
        end
        local i = split[1]
        local interest = interests[i]
        if not interest then
            return "No interest detected with that name."
        end
        if split[2] then
            local n = {tonumber(split[2]),tonumber(split[3]),tonumber(split[4]),tonumber(split[5])}
            for k,v in next, n do
                if not v then
                    return string.format("Could not parse rect component %d.",k)
                end
            end
            interest[4].box = n
            saveInterests()
            return string.format("Set interest %s to use box [%.1f,%.1f,%.1f,%.1f].",i,n[1],n[2],n[3],n[4])
        else
            interest[4].box = nil
            saveInterests()
            return string.format("Removed box of interest %s.",i)
        end
    end)
    message.setHandler("/radarListInterests",function(_,l)
        if not l then return "no" end
        local str = ""
        for k,v in next, interests do
            if #str ~= 0 then
                str = str..", "
            end
            str = string.format("%s^#%s;%s^reset;",str,renderutil.toHexColour(v[4].colour),k)
        end
        if #str == 0 then
            return "There are no interests to list."
        else
            return str
        end
    end)
end


function radarBlipInterests()
    for k,v in next, interests do
        if v[3] == player.worldId() then
            radarLineTowardsPos(v,v[4].colour,2)
            radarIndicatePosition(v,radarIndicAlpha(v[4].colour),2,k,"interest")
        end
    end
end

function radarDescribeInterest(other)
    local r = radarRenderData()
    local i = interests[other]
    local rel = world.distance(i, mcontroller.position())
    if i[4].box then
        local t = rect.translate(i[4].box,rel)
        radarDrawBox(t,i[4].colour,r.scale,"Overlay+32001")
    else
        local rad = i[4].radius or radarInterestDefaultNoteDistance
        drawCircle(rad,rel,{
            color=i[4].colour,
            width=r.scale,
            fullbright=true
        },"Overlay+32001")
    end
    return other
end
