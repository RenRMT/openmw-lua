-- The travel network as one directed graph.
-- A point is one end of a leg and looks like:
--   { cellId, cellName, isInterior, position = {x=, y=, z=}, gridX, gridY, region }
-- An operator is `{ id, name, class, place = point|nil, destinations = {point} }`.

local config = require('scripts.TravelAgents.config')
local modesData = require('scripts.TravelAgents.data.modes')

local M = {}

local function lower(text)
    return type(text) == 'string' and string.lower(text) or nil
end

local function isBlank(text)
    return text == nil or text == ''
end

--- Sorted list of modes (needed for stable comparing, concatenating, showing).
local function sorted(set)
    local list = {}
    for key in pairs(set) do
        list[#list + 1] = key
    end
    table.sort(list)
    return list
end

--- Horizontal distance (height is ignored when merging).
local function planarDistance(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- The key a point belongs to, or nil if only proximity can decide.
-- Interiors key on cell, named exteriors on name.
local function directKey(point)
    if point.isInterior then
        return 'cell:' .. (lower(point.cellId) or lower(point.cellName) or '?')
    end
    if not isBlank(point.cellName) then
        return 'place:' .. lower(point.cellName)
    end
    return nil
end

--- Name for an unnamed stop: shipped name, then region and grid.
local function fallbackName(point)
    local where = ''
    if point.gridX and point.gridY then
        local named = modesData.places[string.format('%d,%d', point.gridX, point.gridY)]
        if named then
            return named
        end
        where = string.format(' (%d, %d)', point.gridX, point.gridY)
    end
    if not isBlank(point.region) then
        return point.region .. where
    end
    return 'Wilderness' .. where
end

local function nodeName(point)
    if not isBlank(point.cellName) then
        return point.cellName
    end
    return fallbackName(point)
end

--- The key a point belongs to, resolved against a graph that already has nodes
-- in it: named things key directly, anything else joins the nearest stop
-- within the merge radius or stands alone.
local function resolveKey(graph, point, mergeRadius)
    local key = directKey(point)
    if key then
        return key
    end
    local bestKey, bestDistance = nil, mergeRadius
    for _, existing in ipairs(graph.order) do
        local candidate = planarDistance(point.position, graph.nodes[existing].position)
        if candidate <= bestDistance then
            bestKey, bestDistance = existing, candidate
        end
    end
    if bestKey then
        return bestKey
    end
    return string.format('at:%d,%d', point.position.x, point.position.y)
end

local function newNode(key, point)
    return {
        key = key,
        name = nodeName(point),
        cellId = point.cellId,
        isExterior = not point.isInterior,
        position = { x = point.position.x, y = point.position.y, z = point.position.z },
        modes = {},
    }
end

--- The mode an operator's legs are labelled with.
-- An id override beats the class, because four vanilla operators are authored
-- with a class that describes the person rather than the vehicle.
--
-- A class nobody has declared becomes a mode of its own rather than joining
-- a shared "unknown" bucket. Otherwise every modded vehicle in a load order
-- collapses into one heap: a guar caravan, a river strider and a carriage
-- would be indistinguishable, and a journey by any of them would read as
-- "Unknown". Deriving the mode from the class means a landmass mod that
-- invents a vehicle is named after it without anyone authoring an entry.
-- `unknown` is left for an operator with no class at all.
local function modeFor(operator, modes)
    local override = modes.overrides[lower(operator.id) or '']
    if override then
        return override
    end
    local class = lower(operator.class)
    local byClass = modes.classes[class or '']
    if byClass then
        return byClass.id
    end
    if class and class ~= '' then
        return class
    end
    return modes.unknown.id
end

-- undeclared mode label: class titlecased (reads better than "Unknown")
local function titleCase(text)
    return (text:gsub('^%l', string.upper))
end

function M.modeLabel(modeId, modes)
    modes = modes or modesData
    for _, mode in pairs(modes.classes) do
        if mode.id == modeId then
            return mode.label
        end
    end
    if modeId == modes.unknown.id then
        return modes.unknown.label
    end
    -- A mode id nothing declares: either an override naming one the class
    -- table also defines, or a class derived by modeFor above.
    return titleCase(modeId)
end

--- Build the graph.
-- @param operators list of operators, see the header
-- @param opts optional { modes = <modes table>, mergeRadius = <number> }
function M.build(operators, opts)
    opts = opts or {}
    local modes = opts.modes or modesData
    local mergeRadius = opts.mergeRadius or config.NODE_MERGE_RADIUS

    local graph = {
        nodes = {},
        order = {},
        edges = {},
        operators = {},
        -- Record ids found standing in more than one cell. See below.
        duplicated = {},
        mergeRadius = mergeRadius,
        stats = { operators = 0, excluded = 0, unplaced = 0, selfEdges = 0, edges = 0, nodes = 0 },
    }

    local function addNode(key, point)
        local node = graph.nodes[key]
        if not node then
            node = newNode(key, point)
            graph.nodes[key] = node
            graph.order[#graph.order + 1] = key
        end
        return node
    end

    -- Pass one: named things. Deferred are collected for pass two.
    local deferred = {}
    local function classify(point)
        if not point or not point.position then
            return
        end
        local key = directKey(point)
        if key then
            addNode(key, point)
            point._key = key
        else
            deferred[#deferred + 1] = point
        end
    end

    local usable = {}
    for _, operator in ipairs(operators) do
        if modes.exclude[lower(operator.id) or ''] then
            graph.stats.excluded = graph.stats.excluded + 1
        elseif not operator.place then
            -- Cut: a record with destinations but no placement.
            graph.stats.unplaced = graph.stats.unplaced + 1
        else
            usable[#usable + 1] = operator
            graph.stats.operators = graph.stats.operators + 1
            classify(operator.place)
            for _, destination in ipairs(operator.destinations) do
                classify(destination)
            end
        end
    end

    -- Pass two (must be separate: inline, a point outside a city could key
    -- before that city's node exists).
    for _, point in ipairs(deferred) do
        local key = resolveKey(graph, point, mergeRadius)
        addNode(key, point)
        point._key = key
    end

    for _, operator in ipairs(usable) do
        local fromKey = operator.place._key
        local mode = modeFor(operator, modes)
        -- Which stop an operator stands at. The planner opens from the
        -- caravaner you are talking to, so it needs to get from that actor to
        -- their place in the network without measuring anything.
        --
        -- One record standing in two cells is the case this cannot answer:
        -- `stopOf` is asked by record id and both instances give the same
        -- one, so the planner opens from whichever was found last whoever is
        -- being talked to. Nothing shipped does it. Named rather than
        -- overwritten in silence, so a load order that does has a thread to
        -- pull.
        local id = lower(operator.id) or operator.id
        local standing = graph.operators[id]
        if standing and standing.key ~= fromKey then
            graph.duplicated[#graph.duplicated + 1] = operator.id
        end
        graph.operators[id] = {
            key = fromKey,
            name = operator.name,
            mode = mode,
            -- Raw class alongside resolved mode; class is what other mods read.
            class = operator.class,
        }
        for _, destination in ipairs(operator.destinations) do
            local toKey = destination._key
            if toKey == fromKey then
                -- Vanilla lists a few operators as serving their own stop.
                graph.stats.selfEdges = graph.stats.selfEdges + 1
            else
                M.addEdge(graph, fromKey, toKey, mode,
                    distance(graph.nodes[fromKey].position, graph.nodes[toKey].position),
                    operator.id, operator.name)
                graph.nodes[fromKey].modes[mode] = true
                graph.nodes[toKey].modes[mode] = true
            end
        end
    end

    M.sort(graph)
    return graph
end

--- Re-sort and recount, after anything adds a stop.
function M.sort(graph)
    table.sort(graph.order, function(a, b)
        return graph.nodes[a].name:lower() < graph.nodes[b].name:lower()
    end)
    graph.stats.nodes = #graph.order
    return graph
end

--- One directed leg. Walk legs come through here too, which is what saves a
-- router from having to know they are different.
function M.addEdge(graph, fromKey, toKey, mode, legDistance, operator, operatorName)
    local edges = graph.edges[fromKey]
    if not edges then
        edges = {}
        graph.edges[fromKey] = edges
    end
    edges[#edges + 1] = {
        from = fromKey,
        to = toKey,
        mode = mode,
        operator = operator,
        operatorName = operatorName,
        distance = legDistance,
    }
    graph.stats.edges = graph.stats.edges + 1
    return edges[#edges]
end

--- Join stops inside buildings to the streets outside.
-- Walk legs are edges with distance but no fare. `modesAt` stays vehicles
-- at one place; `modesWithinWalk` is the wider view.
-- @param links from walk.links -- { cellId, point, walked }
function M.link(graph, links)
    for _, link in ipairs(links) do
        local fromKey = 'cell:' .. (lower(link.cellId) or '?')
        if graph.nodes[fromKey] then
            local toKey = resolveKey(graph, link.point, graph.mergeRadius or 0)
            local to = graph.nodes[toKey]
            if not to then
                -- A stop no vehicle serves: Caldera has a guild hall and
                -- nothing else, and is reachable only this way.
                to = newNode(toKey, link.point)
                graph.nodes[toKey] = to
                graph.order[#graph.order + 1] = toKey
            end
            if toKey ~= fromKey then
                -- The last stretch is on the far side of the door: from where
                -- it drops you to wherever the stop out there actually is.
                local total = link.walked + distance(link.point.position, to.position)
                M.addEdge(graph, fromKey, toKey, 'walk', total)
                M.addEdge(graph, toKey, fromKey, 'walk', total)
                graph.stats.walkLegs = (graph.stats.walkLegs or 0) + 2
                -- Where this stop stands in the world. An interior's own
                -- coordinates are cell-local and cannot be compared with
                -- anything outside it; the street it opens onto can.
                graph.nodes[fromKey].anchor = {
                    x = to.position.x, y = to.position.y, z = to.position.z,
                }
            end
        end
    end
    M.remeasure(graph)
    return M.sort(graph)
end

--- Re-measure vehicle legs against stop positions in the world.
function M.remeasure(graph)
    local anchored = 0
    for _, edges in pairs(graph.edges) do
        for _, edge in ipairs(edges) do
            local from, to = graph.nodes[edge.from], graph.nodes[edge.to]
            if edge.mode ~= 'walk' and (from.anchor or to.anchor) then
                edge.distance = distance(from.anchor or from.position, to.anchor or to.position)
                anchored = anchored + 1
            end
        end
    end
    graph.stats.remeasured = anchored
    return graph
end

--- The modes meeting at a stop, sorted. More than one means you can change
-- vehicles there, which is the whole question the mod exists to answer.
function M.modesAt(graph, key)
    local node = graph.nodes[key]
    if not node then
        return {}
    end
    return sorted(node.modes)
end

--- Can you change vehicle here?
-- `modesAt` remains the narrower fact -- what meets on this exact spot -- for
-- anything that needs to tell the two apart.
function M.isTransfer(graph, key)
    return #M.modesWithinWalk(graph, key) > 1
end

--- Every stop reachable from this one on foot, including itself.
function M.walkGroup(graph, key)
    local seen = { [key] = true }
    local group = { key }
    local index = 1
    while index <= #group do
        for _, edge in ipairs(M.edgesFrom(graph, group[index])) do
            if edge.mode == 'walk' and not seen[edge.to] then
                seen[edge.to] = true
                group[#group + 1] = edge.to
            end
        end
        index = index + 1
    end
    table.sort(group)
    return group
end

--- Every vehicle meeting here or one walk leg away.
function M.modesWithinWalk(graph, key)
    local found = {}
    for _, mode in ipairs(M.modesAt(graph, key)) do
        found[mode] = true
    end
    for _, edge in ipairs(M.edgesFrom(graph, key)) do
        if edge.mode == 'walk' then
            for _, mode in ipairs(M.modesAt(graph, edge.to)) do
                found[mode] = true
            end
        end
    end
    return sorted(found)
end

--- Legs leaving a stop.
function M.edgesFrom(graph, key)
    return graph.edges[key] or {}
end

--- The stop an operator stands at, by record id.
function M.stopOf(graph, recordId)
    if type(recordId) ~= 'string' then
        return nil
    end
    return graph.operators[string.lower(recordId)]
end

--- Which stop names its walk group: exterior first, then most vehicles, alphabetically.
local function namesTheGroup(graph, candidate, incumbent)
    if incumbent == nil then
        return true
    end
    local outside, alsoOutside = graph.nodes[candidate].isExterior, graph.nodes[incumbent].isExterior
    if outside ~= alsoOutside then
        return outside
    end
    local here, there = #M.modesAt(graph, candidate), #M.modesAt(graph, incumbent)
    if here ~= there then
        return here > there
    end
    return graph.nodes[candidate].name:lower() < graph.nodes[incumbent].name:lower()
end

--- A place: stop itself plus everything a walk away, under one name.
function M.place(graph, key)
    if graph.nodes[key] == nil then
        return nil
    end
    local group = M.walkGroup(graph, key)
    local best = nil
    for _, member in ipairs(group) do
        if namesTheGroup(graph, member, best) then
            best = member
        end
    end
    return { key = best, name = graph.nodes[best].name, stops = group }
end

--- The interchanges, counted as places rather than as stops.
-- `onFoot` says whether the change costs a walk: false at Khuul, where boat
-- and strider meet on the spot, true at Balmora, where they do not.
function M.interchanges(graph)
    local claimed = {}
    local found = {}

    for _, key in ipairs(graph.order) do
        if not claimed[key] and M.isTransfer(graph, key) then
            local group = M.walkGroup(graph, key)
            local modes, best, spot = {}, nil, false
            for _, member in ipairs(group) do
                claimed[member] = true
                local here = M.modesAt(graph, member)
                if #here > 1 then
                    spot = true
                end
                if namesTheGroup(graph, member, best) then
                    best = member
                end
                for _, mode in ipairs(here) do
                    modes[mode] = true
                end
            end

            found[#found + 1] = {
                key = best,
                name = graph.nodes[best].name,
                stops = group,
                modes = sorted(modes),
                onFoot = not spot,
            }
        end
    end

    table.sort(found, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return found
end

return M
