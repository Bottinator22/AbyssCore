require "/scripts/vec2.lua"
require "/scripts/poly.lua"
require "/scripts/terra_proxy.lua"

local function imagePath(i)
    return string.match(i,"([^?]*)")
end
local function pathFName(p)
    local out = ""
    for v in string.gmatch(p,"([^/]*)") do
        out = v
    end
    return out
end
local lastEmoteIndex
function getActiveEmote(e)
    -- idk if I'll ever use this. it's there, ig
    local portrait = world.entityPortrait(e or entity.id(),"head")
    if lastEmoteIndex then
        local fname = pathFName(imagePath(portrait[lastEmoteIndex].image))
        if string.match(fname,"([^:]*)") == "emote.png" then
            return string.sub(fname,string.find(fname,":")+1,#fname)
        else
            lastEmoteIndex = nil
        end
    end
    for k,v in next, portrait do
        local fname = pathFName(imagePath(v.image))
        if string.match(fname,"([^:]*)") == "emote.png" then
            lastEmoteIndex = k
            return string.sub(fname,string.find(fname,":")+1,#fname)
        end
    end
end
function ensureBasicProxies()
    -- ensures the presence of my most commonly used two proxies
    -- returns false if they are not present (and updating should be delayed)
    if not localAnimator then
        localAnimator = terra_proxy.setupProxy("localAnimator",entity.id())
    end
    if not player then
        player = terra_proxy.setupProxy("player",entity.id())
    end
    return not not (player or localAnimator)
end

local entityTrackerMT = {
    __index={
        exists=function(t) 
            t:update() 
            return (t.id and world.entityExists(t.id)) or (t.uid and t.found)
        end,
        position=function(t)
            t:update()
            return t.lastSeenPos
        end,
        update=function(t)
            if t.id and world.entityExists(t.id) then
                t.promise = nil
                t.found = true
                t.lastSeenPos = world.entityPosition(t.id)
            elseif t.uid then
                if not t.promise then
                    -- local master entities will resolve this instantly
                    -- ...though local master entities also won't start re-existing
                    t.promise = world.findUniqueEntity(t.uid)
                end
                if t.promise then
                    if t.promise:finished() then
                        t.found = t.promise:succeeded()
                        if t.found then
                            t.lastSeenPos = t.promise:result()
                            
                            -- try and relocate the entity in case it's loaded
                            local es = world.entityQuery(t.lastSeenPos,10,{includedTypes={t.type}})
                            for k,v in next, es do
                                if world.entityUniqueId(v) == t.uid then
                                    t.id = v
                                    break
                                end
                            end
                        end
                        t.promise = nil
                    end
                end
            end
        end
    }
}
function entityTracker(e)
    local out = {
        id=e,
        found=true,
        type=world.entityType(e),
        lastSeenPos=world.entityPosition(e),
        promise=nil,
        uid=world.entityUniqueId(e)
    }
    setmetatable(out,entityTrackerMT)
    return out
end

function calculateEntitySize(e, mode)
    -- uses queries to figure out an entity's size as a rect
    -- unnecessary if world.entity is present, since that can be used to get it directly
    local t = world.entityType(e)
    local epos = world.entityPosition(e)
    local bbox = {0,0,0,0}
    local a = {
        {
        index=1,
        mult=-1,
        rindex=1
        },
        {
        index=2,
        mult=-1,
        rindex=2
        },
        {
        index=1,
        mult=1,
        rindex=3
        },
        {
        index=2,
        mult=1,
        rindex=4
        }
    }
    for i=1,4 do
        local axis = a[i]
        local highestPr = 1
        local function calc(pr, axis, iterations)
            if iterations >= 10 then
                return
            end
            highestPr = math.max(highestPr, pr)
            local qa
            local qb
            if axis.index == 1 then
                qa = {0,-1*axis.mult}
                qb = {pr*axis.mult,1*axis.mult}
            else
                qa = {-1*axis.mult,0}
                qb = {1*axis.mult,pr*axis.mult}
            end
            local has = true
            local i2 = 0
            while has and i2 <= 10 do
                qa[axis.index] = bbox[axis.rindex]
                qb[axis.index] = qa[axis.index]+pr*axis.mult
                local es
                if axis.mult < 0 then
                    es = world.entityQuery(vec2.add(epos, qb),vec2.add(epos, qa),{includedTypes={t},boundMode=mode,order="nearest"})
                else
                    es = world.entityQuery(vec2.add(epos, qa),vec2.add(epos, qb),{includedTypes={t},boundMode=mode,order="nearest"})
                end
                i2 = i2 + 1
                has = false
                for k,v in next, es do
                    if v == e then
                        has = true
                        break
                    end
                end
                if has then
                    --world.debugPoly(poly.translate({{qa[1],qa[2]},{qb[1],qa[2]},{qb[1],qb[2]},{qa[1],qb[2]}}, epos), "green")
                    bbox[axis.rindex] = bbox[axis.rindex]+pr*axis.mult
                else
                    --world.debugPoly(poly.translate({{qa[1],qa[2]},{qb[1],qa[2]},{qb[1],qb[2]},{qa[1],qb[2]}}, epos), "red")
                end
            end
            if i2 > 10 then
                if pr == highestPr then
                    bbox[axis.rindex] = 0
                end
                calc(pr*10,axis,iterations+1)
            else
                bbox[axis.rindex] = bbox[axis.rindex]-pr*axis.mult
                calc(pr/10,axis,iterations+1)
            end
        end
        calc(1,axis,0)
    end
    --world.debugText(sb.printJson(bbox), epos, "cyan")
    --world.debugPoly(poly.translate({{bbox[1],bbox[2]},{bbox[1],bbox[4]},{bbox[3],bbox[4]},{bbox[3],bbox[2]}}, epos), "cyan")
    return bbox
end
