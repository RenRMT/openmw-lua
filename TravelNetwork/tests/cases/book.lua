-- Selling a journey: what it costs, where it leaves you, and when the answer
-- is no.
--
-- The teleport and the gold are not tested -- they are two engine calls in
-- adapter.lua and money.lua. Everything deciding whether those calls happen
-- is here, which is the reason book.lua takes a number for the player's purse
-- rather than reading one.

local book = require('scripts.TravelNetwork.book')
local expect = require('support.expect')
local fixture = require('support.fixture')
local graph = require('scripts.TravelNetwork.graph')
local plan = require('scripts.TravelNetwork.plan')
local walk = require('scripts.TravelNetwork.walk')

local M = {}

local function linked()
    local g = graph.build(fixture.operators())
    local stops = {}
    for _, key in ipairs(g.order) do
        if not g.nodes[key].isExterior then
            stops[#stops + 1] = { cellId = g.nodes[key].cellId, position = g.nodes[key].position }
        end
    end
    graph.link(g, walk.links(stops, fixture.doorsFor))
    return g
end

function M.aQuoteNamesTheFareTheHoursAndWhereYouEndUp()
    local quote = book.quote(linked(), 'place:balmora', 'place:ald-ruhn')

    expect.truthy(quote.ok, 'Balmora to Ald-ruhn can be bought')
    expect.greater(quote.fare, 0, 'the fare')
    expect.greater(quote.hours, 0, 'the journey takes time')
    expect.equal(quote.arrival.name, 'Ald-ruhn', 'where it leaves you')
end

function M.theArrivalCarriesWhatATeleportNeeds()
    -- The global script hands this straight to the engine, so a quote missing
    -- a cell or a position is a booking that charges and does not move you.
    local arrival = book.quote(linked(), 'place:balmora', 'cell:caldera, guild of mages').arrival

    expect.truthy(arrival.cellId, 'a cell to arrive in')
    expect.truthy(arrival.position and arrival.position.x, 'a position to arrive at')
    expect.falsy(arrival.isExterior, 'and it knows the guild hall is indoors')
end

function M.anEmptyPurseIsToldWhatItIsShortOf()
    local g = linked()
    local fare = book.quote(g, 'place:balmora', 'place:ald-ruhn').fare
    local refused = book.quote(g, 'place:balmora', 'place:ald-ruhn', { gold = fare - 10 })

    expect.falsy(refused.ok, 'refused')
    expect.equal(refused.reason, 'gold', 'because of the money')
    expect.equal(refused.short, 10, 'and by this much')
    expect.equal(refused.fare, fare, 'the refusal still quotes the fare')
end

function M.theExactFareIsEnough()
    local g = linked()
    local fare = book.quote(g, 'place:balmora', 'place:ald-ruhn').fare
    expect.truthy(book.quote(g, 'place:balmora', 'place:ald-ruhn', { gold = fare }).ok,
        'paying to the last coin buys the journey')
end

function M.aJourneyThroughADoorCostsTimeButNoMoney()
    -- Balmora's guild hall is one door off the street. The mod moves the
    -- player through it rather than leaving them to walk, and charges for it
    -- in hours only -- nobody sells passage through a door.
    local quote = book.quote(linked(), 'place:balmora', 'cell:balmora, guild of mages', { gold = 0 })

    expect.truthy(quote.ok, 'affordable with nothing in the purse')
    expect.equal(quote.fare, 0, 'the fare')
    expect.greater(quote.hours, 0, 'the time it takes')
    expect.greater(quote.walked, 0, 'and it is walked, not ridden')
end

function M.aTicketCostsMoreThanTheLegsItIsMadeOf()
    -- Balmora to Caldera is a guide leg with a door at each end -- one ride,
    -- so no surcharge -- while Balmora to Vos changes vehicle on the way and
    -- is charged for the convenience of being sold in one piece.
    local g = linked()
    local direct = book.quote(g, 'place:balmora', 'cell:caldera, guild of mages')
    expect.equal(direct.surcharge, 0, 'one ride, whatever it walks through')

    local changing = nil
    for _, key in ipairs(g.order) do
        local quote = book.quote(g, 'place:balmora', key)
        if quote.ok and (quote.surchargePercent or 0) > 0 then
            changing = changing or quote
        end
    end

    expect.truthy(changing, 'somewhere from Balmora asks for a change of vehicle')
    expect.greater(changing.fare, changing.baseFare, 'the ticket costs more than the legs')
    expect.equal(changing.surcharge, changing.fare - changing.baseFare, 'and says by how much')
end

function M.theSurchargeIsSetByTheCallerNotBakedIn()
    local g = linked()
    local plain = book.quote(g, 'place:balmora', 'place:vivec, foreign quarter',
        { legSurcharge = 0, modeChangeSurcharge = 0 })
    local steep = book.quote(g, 'place:balmora', 'place:vivec, foreign quarter',
        { legSurcharge = 0.5, modeChangeSurcharge = 0.5 })

    expect.equal(plain.surcharge, 0, 'nothing added when nothing is asked for')
    expect.truthy(steep.fare >= plain.fare, 'and more when more is')
end

function M.aStopThatCannotBeReachedIsNotSold()
    local refused = book.quote(linked(), 'place:balmora', 'place:nowhere')
    expect.falsy(refused.ok, 'refused')
    expect.equal(refused.reason, 'route', 'for want of a route')
    expect.isNil(refused.fare, 'and quotes nothing')
end

function M.youCannotBuyPassageToWhereYouAreStanding()
    local refused = book.quote(linked(), 'place:balmora', 'place:balmora')
    expect.falsy(refused.ok, 'refused')
    expect.equal(refused.reason, 'route', 'a journey to here is not a journey')
end

function M.nonsenseIsRefusedRatherThanRaising()
    -- The keys come across an event boundary, so they are whatever the other
    -- side sent. A bad one must not take the global script down with it.
    local g = linked()
    expect.falsy(book.quote(g, 'place:balmora', nil).ok, 'no destination')
    expect.falsy(book.quote(g, nil, 'place:balmora').ok, 'no origin')
    expect.falsy(book.quote(g, 'place:balmora', 42).ok, 'a destination that is not a key')
end

function M.theFareMatchesWhatThePlannerShowed()
    -- The window quotes from route.destinations and the booking quotes from
    -- route.find. Two paths to the same number, and a player who is charged
    -- more than the list said would rightly call it a swindle.
    local g = linked()
    local built = plan.build(g, 'place:balmora')

    for _, stop in ipairs(built.stops) do
        local quote = book.quote(g, 'place:balmora', stop.key)
        expect.equal(quote.fare, stop.fare, 'fare to ' .. stop.name)
        expect.equal(quote.arrival.key, stop.key, 'arrival at ' .. stop.name)
    end
end

return M
