

local portals = {}

local function savePortals()
    if root.setConfiguration then
        root.setConfiguration("abyss_radarPortals",portals)
    else
        player.setProperty("radarPortals",portals)
    end
end
local portalColours = {
    {255,127,0}, -- orange/blue
    {0,255,0}, -- green/magenta
    {255,0,0}, -- red/cyan
    {255,255,0}, -- yellow/deep blue
    {127,255,0}, -- chartreuse/violet
    {0,255,127} -- blue-green/rose
}
local function newPortalColour()
    local interestN = 0
    for k,v in next, portals do
        interestN = interestN + 1
    end
    local n = #portalColours
    local i = ((interestN-1)%n)+1
    return portalColours[i]
end
local function portalOtherColour(c)
    return vec3.sub({255,255,255},c)
end

local showAllPortals = false

function radarPortalsTransfers(p)
    local out = {}
    for k,v in next, portals do
        if v.world == player.worldId() then
            local dis1 = world.distance(p,v.pos1)
            if rect.contains(v.rect,dis1) then
                -- move from pos1 to pos2
                table.insert(out,vec2.add(v.pos2,vec2.mul(dis1,v.scale)))
            end
            
            local dis2 = world.distance(p,v.pos2)
            if rect.contains(rect.scale(v.rect,v.scale),dis2) then
                -- move from pos2 to pos1
                table.insert(out,vec2.add(v.pos1,{dis2[1]/v.scale[1],dis2[2]/v.scale[2]}))
            end
        end
    end
    return out
end

radarPortals = portals
function radarPortalInit()
    portals = (root.getConfiguration and root.getConfiguration("abyss_radarPortals")) or player.getProperty("radarPortals") or {}
    radarPortals = portals
    if root.getConfiguration then
        local pri = player.getProperty("radarPortals")
        if pri then
            for k,v in next, pri do
                portals[k] = v
            end
            player.setProperty("radarPortals",nil)
            savePortals()
        end
    end
    
    message.setHandler("/radarCreatePortal",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #split == 0 or #c == 0 then
            return "Usage: /radarCreatePortal <portal>"
        end
        if #split > 1 then
            return "Portal name cannot have spaces."
        end
        local exists = not not portals[c]
        local pos = mcontroller.position()
        local portal = {
            rect={-1,-1,1,1},
            pos1=pos,
            pos2=pos,
            colour=newPortalColour(),
            scale={1,1}, -- scale from pos1 to pos2
            world=player.worldId()
        }
        portals[c] = portal
        savePortals()
        return string.format("%s portal %s. Use other commands to adjust it.",exists and "Reset" or "Created",c)
    end)
    message.setHandler("/radarPortalColour",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #split < 4 then
            return "Usage: /radarPortalColour <portal> <R> <G> <B> [A]"
        end
        local portal = portals[split[1]]
        if not portal then
            return "No portal detected with that name."
        end
        portal.colour = {tonumber(split[2]),tonumber(split[3]),tonumber(split[4]),split[5] and tonumber(split[5])}
        savePortals()
        return string.format("Recoloured portal %s",split[1])
    end)
    message.setHandler("/radarPortalPos1",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #split < 1 or #c == 0 or (#split >= 2 and #split < 3) then
            return "Usage: /radarPortalPos1 <portal> [<x> <y>]"
        end
        if #split > 3 then
            return "Portal name cannot have spaces."
        end
        local i = split[1]
        local portal = portals[i]
        if not portal then
            return "No portal detected with that name."
        end
        if split[2] then
            local n = {tonumber(split[2]),tonumber(split[3])}
            for k,v in next, n do
                if not v then
                    return string.format("Could not parse vec2 component %d.",k)
                end
            end
            portal.pos1 = n
            savePortals()
            --return string.format("Set portal %s to use first position [%.1f,%.1f].",i,n[1],n[2])
        else
            portal.pos1 = vec2.floor(vec2.add(mcontroller.position(),{0.5,0.5}))
            savePortals()
            --return string.format("Set first position of portal %s to player position.",i)
        end
    end)
    message.setHandler("/radarPortalPos2",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #split < 1 or #c == 0 or (#split >= 2 and #split < 3) then
            return "Usage: /radarPortalPos2 <portal> [<x> <y>]"
        end
        if #split > 3 then
            return "Portal name cannot have spaces."
        end
        local i = split[1]
        local portal = portals[i]
        if not portal then
            return "No portal detected with that name."
        end
        if split[2] then
            local n = {tonumber(split[2]),tonumber(split[3])}
            for k,v in next, n do
                if not v then
                    return string.format("Could not parse vec2 component %d.",k)
                end
            end
            portal.pos2 = n
            savePortals()
            --return string.format("Set portal %s to use second position [%.1f,%.1f].",i,n[1],n[2])
        else
            portal.pos2 = vec2.floor(vec2.add(mcontroller.position(),{0.5,0.5}))
            savePortals()
            --return string.format("Set second position of portal %s to player position.",i)
        end
    end)
    message.setHandler("/radarPortalRect",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #c == 0 or #split < 5 then
            return "Usage: /radarPortalRect <portal> <x1> <y1> <x2> <y2>"
        end
        if #split > 5 then
            return "Portal name cannot have spaces."
        end
        local i = split[1]
        local portal = portals[i]
        if not portal then
            return "No portal detected with that name."
        end
        local n = {tonumber(split[2]),tonumber(split[3]),tonumber(split[4]),tonumber(split[5])}
        for k,v in next, n do
            if not v then
                return string.format("Could not parse rect component %d.",k)
            end
        end
        portal.rect = n
        savePortals()
        --return string.format("Set portal %s to use box [%.1f,%.1f,%.1f,%.1f].",i,n[1],n[2],n[3],n[4])
    end)
    message.setHandler("/radarPortalScale",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #split < 1 or #c == 0 or (#split >= 2 and #split < 3) then
            return "Usage: /radarPortalScale <portal> [<x> <y>]"
        end
        if #split > 3 then
            return "Portal name cannot have spaces."
        end
        local i = split[1]
        local portal = portals[i]
        if not portal then
            return "No portal detected with that name."
        end
        if split[2] then
            local n = {tonumber(split[2]),tonumber(split[3])}
            for k,v in next, n do
                if not v then
                    return string.format("Could not parse vec2 component %d.",k)
                end
            end
            portal.scale = n
            savePortals()
            --return string.format("Set portal %s to use scale [%.4f,%.4f].",i,n[1],n[2])
        else
            portal.scale = {1,1}
            savePortals()
            return string.format("Reset scale of portal %s.",i)
        end
    end)
    message.setHandler("/radarRemovePortal",function(_,l,c)
        if not l then return "no" end
        local split = {}
        for v in string.gmatch(c,"([^ ]+)") do
            table.insert(split, v)
        end
        if #split == 0 or #c == 0 then
            return "Usage: /radarRemovePortal <portal>"
        end
        if #split > 1 then
            return "Portal name cannot have spaces."
        end
        if not portals[c] then
            return "No portal detected with that name."
        end
        portals[c] = nil
        savePortals()
        return string.format("Deleted portal %s",c)
    end)
    message.setHandler("/radarListAllPortals",function(_,l)
        if not l then return "no" end
        local str = ""
        for k,v in next, portals do
            if #str ~= 0 then
                str = str..", "
            end
            str = string.format("%s%s",str,k)
        end
        if #str == 0 then
            return "There are no portals to list."
        else
            return str
        end
    end)
    message.setHandler("/radarListPortals",function(_,l)
        if not l then return "no" end
        local str = ""
        for k,v in next, portals do
            if v.world == player.worldId() then
                if #str ~= 0 then
                    str = str..", "
                end
                str = string.format("%s%s",str,k)
            end
        end
        if #str == 0 then
            return "There are no on-world portals to list."
        else
            return str
        end
    end)
    message.setHandler("/radarPortalsTeleport",function(_,l)
        if not l then return "no" end
        local transfers = radarPortalsTransfers(mcontroller.position())
        
        if transfers[1] then
            -- take a random transfer
            mcontroller.setPosition(transfers[math.random(1,#transfers)])
        else
            return "You are not in any portals."
        end
    end)
    message.setHandler("/radarPortals",function(_,l)
        if not l then return "no" end
        showAllPortals = not showAllPortals
        
        if showAllPortals then
            return "Showing all portals."
        else
            return "Hiding irrelevant portals."
        end
    end)
end
function radarBlipPortals()
    local p = radarDistanceReferencePosition()
    for k,v in next, portals do
        if v.world == player.worldId() then
            local dis1 = world.distance(p,v.pos1)
            local dis2 = world.distance(p,v.pos2)
            if showAllPortals or rect.contains(v.rect,dis1) or rect.contains(rect.scale(v.rect,v.scale),dis2) then
                local c1 = v.colour or portalColours[1]
                local c2 = v.colour2 or portalOtherColour(c1)
                --radarLineTowardsPos(v.pos1,c1,2)
                radarIndicatePosition(v.pos1,radarIndicAlpha(c1),1.5,k,"portal")
                --radarLineTowardsPos(v.pos2,c2,2)
                radarIndicatePosition(v.pos2,radarIndicAlpha(c2),1.5,k,"portal")
            end
        end
    end
end

function radarDescribePortal(other,colour)
    local r = radarRenderData()
    local i = portals[other]
    local rel1 = world.distance(i.pos1, mcontroller.position())
    local rel2 = world.distance(i.pos2, mcontroller.position())
    local t1 = rect.translate(i.rect,rel1)
    local t2 = rect.translate(rect.scale(i.rect,i.scale),rel2)
    local c1 = i.colour or portalColours[1]
    local c2 = i.colour2 or portalOtherColour(c1)
    local ct = vec3.add(c1,c2)
    local c3 = vec3.mul(ct,255/math.max(ct[1],ct[2],ct[3]))
    radarDrawBox(t1,c1,r.scale,"Overlay+32001")
    radarDrawBox(t2,c2,r.scale,"Overlay+32001")
    local l = generateLineDrawable(rel1,rel2)
    l.color = c3
    l.width = r.scale
    l.fullbright = true
    localAnimator.addDrawable(l,"Overlay+32001")
    return "Portal\n"..other
end
