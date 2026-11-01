import Foundation
import Testing
@testable import Engine

@Suite struct ThingsTests {
    private let now = Date(timeIntervalSince1970: 1_792_600_000)

    @Test func handlesAreMintedInOrderAndNeverRenumbered() {
        let page = Exchange.page(query: "dyson", title: "Dyson PencilVac", address: URL(string: "https://www.dyson.com/pencilvac")!)
        let search = Exchange.search(query: "google steve jobs", term: "steve jobs")
        let old = Webpage(kind: .page, address: URL(string: "https://www.hennesseyperformance.com/")!, title: "Hennessey Performance", query: "hennessey", opened: now.addingTimeInterval(-86_400))
        var table = ThingTable(exchanges: [page, search], webpages: [old])
        #expect(table.handles == ["p1", "p2", "w1"])
        let found = Webpage(kind: .search, address: QueryParser.searchURL(for: "venom f5 price"), query: "venom f5 price", opened: now)
        #expect(table.mint(webpages: [found, old]) == ["w2", "w1"], "a webpage already listed keeps its handle")
        #expect(table.handles == ["p1", "p2", "w1", "w2"])
        #expect(table[" W2 "] == .webpage(found), "a handle reads loosely")
        #expect(table["w3"] == nil && table["x1"] == nil)
        #expect(ThingTable.line(table.entries[0], now: now) == "p1: Read \"Dyson PencilVac\" (www.dyson.com)")
        #expect(ThingTable.line(table.entries[1], now: now) == "p2: Searched \"steve jobs\"")
        #expect(ThingTable.line(table.entries[2], now: now) == "w1: A page open since yesterday (www.hennesseyperformance.com): \"Hennessey Performance\"")
        #expect(ThingTable.line(table.entries[3], now: now) == "w2: A search for \"venom f5 price\", open since today")
        let dyson = Webpage(kind: .page, address: URL(string: "https://www.dyson.com/pencilvac?utm_source=x")!, title: "Dyson PencilVac", query: "dyson", opened: now)
        #expect(ThingTable.line(table.entries[0], now: now, webpageHandles: [dyson.address: "w5"]) == "p1: Read \"Dyson PencilVac\" (www.dyson.com) (w5)", "a page the user saw points at the open webpage it is")
        // A page a step opened on Jarbits's own screen: the next p, listed as read there.
        let own = Exchange.search(query: "lehigh pizza hours", term: "lehigh pizza hours", own: true)
        #expect(table.mint(exchange: own) == "p3")
        #expect(table.mint(exchange: own) == "p3", "the same exchange keeps its handle")
        #expect(table.mint(exchange: search) == "p2", "one the plan began with too")
        #expect(ThingTable.line(table.entries[4], now: now) == "p3: Searched \"lehigh pizza hours\" on my screen")
        let ownPage = Exchange.page(query: "q", title: "Lehigh Pizza", address: URL(string: "https://www.lehighpizza.com/hours")!, own: true)
        #expect(ownPage.described == "Read \"Lehigh Pizza\" (www.lehighpizza.com) on my screen")
        #expect(ThingTable.line(.init(handle: "p9", thing: .exchange(ownPage)), now: now, webpageHandles: [URL(string: "https://www.lehighpizza.com/hours")!: "w1"]) == "p9: Read \"Lehigh Pizza\" (www.lehighpizza.com) on my screen", "a page on Jarbits's screen is no open webpage")
    }

    @Test func aReferenceKnowsWhatEachThingIs() {
        let address = URL(string: "https://www.dyson.com/pencilvac")!
        let page = Reference(.exchange(.page(query: "dyson", title: "Dyson PencilVac", address: address)))
        #expect(page.kind == .page && page.address == address && page.title == "Dyson PencilVac")
        #expect(page.asExchange(query: "q") == .page(query: "q", title: "Dyson PencilVac", address: address))
        let search = Reference(.exchange(.search(query: "google steve jobs", term: "steve jobs")))
        #expect(search.kind == .search && search.term == "steve jobs")
        let answer = Reference(.exchange(.answer(query: "capital of peru", text: "Lima")))
        #expect(answer.kind == .answer && answer.text == "Lima" && answer.asExchange(query: "q") == .answer(query: "capital of peru", text: "Lima"))
        let webpage = Webpage(kind: .search, address: QueryParser.searchURL(for: "dyson pencilvac"), query: "dyson pencilvac")
        let open = Reference(.webpage(webpage))
        #expect(open.kind == .search && open.term == "dyson pencilvac" && open.webpageID == webpage.id && open.address == webpage.address)
        let pictures = Reference(.webpage(Webpage(kind: .images, address: QueryParser.imageSearchURL(for: "capybara"), query: "capybara")))
        #expect(pictures.kind == .images && pictures.asExchange(query: "q") == .search(query: "q", term: "capybara"))
    }

    @Test func aThingFieldIsNeitherFreeFormNorClosedSetAndIsAHandleInTheSchema() throws {
        let field = ArgumentSchema.Field(name: "about", kind: .thing, description: "the thing this is about", required: false)
        let schema = ArgumentSchema(fields: [field, .init(name: "term", kind: .text, description: "t"), .init(name: "fan", kind: .boolean, description: "f")])
        #expect(schema.freeForm.map(\.name) == ["term"])
        #expect(schema.closedSet.map(\.name) == ["fan"])
        #expect(schema.things.map(\.name) == ["about"])
        let json = schema.jsonSchema()
        #expect(json["properties"]?["about"]?["description"]?.stringValue?.contains("such as p1 or w2") == true)
        #expect(json["properties"]?["about"]?["type"]?.arrayValue?.first?.stringValue == "string")
        #expect(schema.validate(["about": .string(" P1 ")]) == ["about": .string("p1")])
        #expect(InstinctSpec.spec(for: .narrative).arguments.things.map(\.name) == ["about"])
        #expect(InstinctSpec.spec(for: .oneLine).arguments.things.map(\.name) == ["about"])
        #expect(InstinctSpec.spec(for: .narrative).arguments.freeForm.isEmpty, "the extractor is never asked for a thing")
    }
}
