require "/scripts/vec2.lua"
require "/scripts/poly.lua"

abyssutil = {}
function abyssutil.calculateEntitySize(e, mode)
    -- uses queries to figure out an entity's size
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
