import Foundation
import Testing
@testable import Engine

@Suite struct ThingsTests {
    private let now = Date(timeIntervalSince1970: 1_792_600_000)

    @Test func handlesAreMintedInOrderAndNeverRenumbered() {
        let page = Exchange.page(query: "dyson", title: "Dyson PencilVac", address: URL(string: "https://www.dyson.com/pencilvac")!)
        let search = Exchange.search(query: "google steve jobs", term: "steve jobs")
        let old = MemoryRecord(date: now.addingTimeInterval(-86_400), kind: .page, query: "hennessey", title: "Hennessey Performance", url: URL(string: "https://www.hennesseyperformance.com/"))
        var table = ThingTable(exchanges: [page, search], memories: [old])
        #expect(table.handles == ["p1", "p2", "m1"])
        let found = MemoryRecord(date: now, kind: .narrative, query: "what is a venom f5", text: "A car.")
        #expect(table.mint([found, old]) == ["m2", "m1"], "a record already listed keeps its handle")
        #expect(table.handles == ["p1", "p2", "m1", "m2"])
        #expect(table[" M2 "] == .memory(found), "a handle reads loosely")
        #expect(table["m3"] == nil && table["x1"] == nil)
        #expect(ThingTable.line(table.entries[0], now: now) == "p1: Read \"Dyson PencilVac\" (www.dyson.com)")
        #expect(ThingTable.line(table.entries[1], now: now) == "p2: Searched \"steve jobs\"")
        #expect(ThingTable.line(table.entries[2], now: now) == "m1: A page from yesterday (www.hennesseyperformance.com): \"Hennessey Performance\"")
        #expect(ThingTable.line(table.entries[3], now: now) == "m2: An answer from today: \"what is a venom f5\"")
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
        let record = MemoryRecord(kind: .search, query: "dyson pencilvac")
        let memory = Reference(.memory(record))
        #expect(memory.kind == .search && memory.term == "dyson pencilvac" && memory.memoryID == record.id)
        let picture = Reference(.memory(MemoryRecord(kind: .image, query: "capybara")))
        #expect(picture.kind == .picture)
    }

    @Test func aThingFieldIsNeitherFreeFormNorClosedSetAndIsAHandleInTheSchema() throws {
        let field = ArgumentSchema.Field(name: "about", kind: .thing, description: "the thing this is about", required: false)
        let schema = ArgumentSchema(fields: [field, .init(name: "term", kind: .text, description: "t"), .init(name: "fan", kind: .boolean, description: "f")])
        #expect(schema.freeForm.map(\.name) == ["term"])
        #expect(schema.closedSet.map(\.name) == ["fan"])
        #expect(schema.things.map(\.name) == ["about"])
        let json = schema.jsonSchema()
        #expect(json["properties"]?["about"]?["description"]?.stringValue?.contains("such as p1 or m2") == true)
        #expect(json["properties"]?["about"]?["type"]?.arrayValue?.first?.stringValue == "string")
        #expect(schema.validate(["about": .string(" P1 ")]) == ["about": .string("p1")])
        #expect(InstinctSpec.spec(for: .narrative).arguments.things.map(\.name) == ["about"])
        #expect(InstinctSpec.spec(for: .oneLine).arguments.things.map(\.name) == ["about"])
        #expect(InstinctSpec.spec(for: .narrative).arguments.freeForm.isEmpty, "the extractor is never asked for a thing")
    }
}
