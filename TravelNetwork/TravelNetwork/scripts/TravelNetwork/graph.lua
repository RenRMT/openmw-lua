-- The travel network as one directed graph.
--
-- Pure: plain tables in, plain tables out, no `openmw.*` package anywhere.
-- Everything that touches the engine is in adapter.lua, which is what lets
-- this run headless against the shipped-data fixture.
--
-- A point is one end of a leg -- where an operator stands, or where they take
-- you -- and looks like:
--
--   { cellId, cellName, isInterior, position = {x=, y=, z=}, gridX, gridY, region }
--
-- An operator is `{ id, name, class, place = point|nil, destinations = {point} }`.

local config = require('scripts.TravelNetwork.config')
local modesData = require('scripts.TravelNetwork.data.modes')

local M = {}

local function lower(text)
    return type(text) == 'string' and string.lower(text) or nil
end

local function isBlank(text)
    return text == nil or text == ''
end

--- Horizontal distance. Merging ignores height on purpose: a stop on the bluff
-- above a dock is the same town, and vanilla's z varies by hundreds of units
-- across one settlement.
local function planarDistance(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- The key a point belongs to, or nil when only proximity can decide.
--
-- Interiors key on the cell, because their coordinates are cell-local and
-- comparing them across cells is meaningless. Named exteriors key on the name,
-- which is what unifies the towns whose stops straddle a grid boundary --
-- Molag Mar's platform and dock are 10896 units apart and both called "Molag
-- Mar". Everything else is left to the second pass.
local function directKey(point)
    if point.isInterior then
        return 'cell:' .. (lower(point.cellId) or lower(point.cellName) or '?')
    end
    if not isBlank(point.cellName) then
        return 'place:' .. lower(point.cellName)
    end
    return nil
end

local function fallbackName(point)
    local where = ''
    if point.gridX and point.gridY then
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
local function modeFor(operator, modes)
    local override = modes.overrides[lower(operator.id) or '']
    if override then
        return override
    end
    local byClass = modes.classes[lower(operator.class) or '']
    if byClass then
        return byClass.id
    end
    return modes.unknown.id
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
    -- An override names a mode the class table also defines, so falling
    -- through here means a mode id nothing declares.
    return modeId
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

    -- Pass one: everything the game named. Deferred points are collected with
    -- their owner so the second pass can key them without walking twice.
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
            -- Cut content: a record with destinations that no cell places.
            -- Nothing can depart from a stop nobody stands at.
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

    -- Pass two, and it has to be a second pass: run inline, a point 396 units
    -- outside Tel Aruhn is keyed before Tel Aruhn's node exists and becomes a
    -- stop of its own.
    for _, point in ipairs(deferred) do
        local key = resolveKey(graph, point, mergeRadius)
        addNode(key, point)
        point._key = key
    end

    for _, operator in ipairs(usable) do
        local fromKey = operator.place._key
        local mode = modeFor(operator, modes)
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

--- Join stops inside buildings to the streets their doors open onto.
--
-- A walk leg is an edge, not a merge: the two ends are genuinely different
-- places, and in one vanilla case -- the guide at Wolverine Hall and the boat
-- at Sadrith Mora -- they are 11593 units apart. It carries a distance and
-- nothing else: no fare, because nobody charges for a door, and no time,
-- because the player really does walk it.
--
-- Walk legs deliberately do **not** register a mode on either stop.
-- `modesAt` stays the list of vehicles meeting in one place, so the count of
-- real interchanges cannot quietly inflate; `modesWithinWalk` is the wider
-- view.
--
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
            end
        end
    end
    return M.sort(graph)
end

--- The modes meeting at a stop, sorted. More than one means you can change
-- vehicles there, which is the whole question the mod exists to answer.
function M.modesAt(graph, key)
    local node = graph.nodes[key]
    if not node then
        return {}
    end
    local list = {}
    for mode in pairs(node.modes) do
        list[#list + 1] = mode
    end
    table.sort(list)
    return list
end

function M.isTransfer(graph, key)
    return #M.modesAt(graph, key) > 1
end

--- Every vehicle meeting here or one walk leg away.
--
-- The honest answer to "can I change here": Balmora's silt strider and its
-- guild guide are one door and 3732 units apart, a change a player makes
-- without thinking and `modesAt` will never show.
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
    local list = {}
    for mode in pairs(found) do
        list[#list + 1] = mode
    end
    table.sort(list)
    return list
end

--- Legs leaving a stop.
function M.edgesFrom(graph, key)
    return graph.edges[key] or {}
end

return M
