import Foundation
import Testing
@testable import Engine

@Suite struct ScreenTests {
    private let link = ScreenItem(title: "Rick Steves' Europe: Lisbon", address: URL(string: "https://m.youtube.com/watch?v=abc")!)

    @Test func theBlockReadsTopDownAndLeavesEmptyPartsOut() {
        let screen = Screen(kind: .page, title: "Dyson PencilVac | Dyson", address: URL(string: "https://www.dyson.com/pencilvac"), visible: "Dyson PencilVac\n  $449.99  \nAdd to basket", rest: "Specifications\nWeight 1.8 kg", selection: " $449.99 ", items: [link])
        #expect(screen.described == "On screen: the page \"Dyson PencilVac | Dyson\" at https://www.dyson.com/pencilvac")
        #expect(screen.block(whole: false) == "On screen: the page \"Dyson PencilVac | Dyson\" at https://www.dyson.com/pencilvac\nSelected on it: \"$449.99\"\nVisible:\nDyson PencilVac\n$449.99\nAdd to basket", "the reader gets the selection and the visible text, spaces settled")
        #expect(screen.block(whole: true, handles: ["s1"]) == "On screen: the page \"Dyson PencilVac | Dyson\" at https://www.dyson.com/pencilvac\nSelected on it: \"$449.99\"\nVisible now:\nDyson PencilVac\n$449.99\nAdd to basket\nFurther down the page:\nSpecifications\nWeight 1.8 kg\nLinks in view, in order:\n- s1: \"Rick Steves' Europe: Lisbon\" \u{2192} https://m.youtube.com/watch?v=abc")
        let withData = Screen(kind: .page, title: "Lisbon in 4K", address: URL(string: "https://m.youtube.com/watch?v=def"), visible: "Lisbon in 4K\n2.1M views", data: "canonical: https://www.youtube.com/watch?v=def\nduration: PT12M4S\nuploadDate: 2024-05-01")
        #expect(withData.block(whole: false) == "On screen: the page \"Lisbon in 4K\" at https://m.youtube.com/watch?v=def\nVisible:\nLisbon in 4K\n2.1M views", "the reader does not get the data")
        #expect(withData.block(whole: true) == "On screen: the page \"Lisbon in 4K\" at https://m.youtube.com/watch?v=def\nVisible now:\nLisbon in 4K\n2.1M views\nThe page's own data (what it publishes, not what it shows):\ncanonical: https://www.youtube.com/watch?v=def\nduration: PT12M4S\nuploadDate: 2024-05-01", "the planner and an answer do, before the rest")
        #expect(!Screen(kind: .page, title: "t", data: "duration: PT1M").isEmpty)
        let bare = Screen(kind: .note, title: "Packing list", visible: "passport")
        #expect(bare.block(whole: true) == "On screen: my note \"Packing list\"\nVisible now:\npassport")
        #expect(!bare.isEmpty && Screen(kind: .answer, title: "q").isEmpty)
        #expect(Screen(kind: .page, title: "t", selection: "  \n").selection == nil)
    }

    @Test func theCapsHold() {
        let long = String(repeating: "word ", count: 3_000)
        let screen = Screen(kind: .page, title: "t", visible: long, rest: long, items: Array(repeating: link, count: 60))
        #expect(screen.visible.count == Screen.visibleLimit + 1 && screen.visible.hasSuffix("…"))
        #expect(screen.rest.count == Screen.restLimit + 1)
        #expect(screen.restCut && screen.block(whole: true).contains("Further down the page (cut at 8000 characters; the page has more, which a look reads):"), "a cut is said, not left to the ellipsis")
        #expect(!Screen(kind: .page, title: "t", rest: "short").restCut)
        #expect(screen.items.count == Screen.itemLimit)
        #expect(Screen(kind: .page, title: "t", data: long).data.count == Screen.dataLimit + 1)
        #expect(Screen.trimmed("a\n\n\n  b  \t c", to: 100) == "a\nb c", "blank runs settle; a line break stays a line break")
    }

    @Test func aLinkInViewIsAThingWithAHandle() {
        let page = Exchange.page(query: "lisbon", title: "YouTube", address: URL(string: "https://m.youtube.com/results?q=lisbon")!)
        var table = ThingTable(exchanges: [page], items: [link, ScreenItem(title: " Lisbon in 4K ", address: URL(string: "https://m.youtube.com/watch?v=def")!)])
        #expect(table.handles == ["p1", "s1", "s2"])
        #expect(table.itemHandles == ["s1", "s2"])
        #expect(ThingTable.line(table.entries[2], now: .now) == "s2: \"Lisbon in 4K\" \u{2192} https://m.youtube.com/watch?v=def")
        let reference = Reference(table["s1"]!)
        #expect(reference.kind == .page && reference.address == link.address && reference.title == link.title, "the device knows the address; the planner only named s1")
        #expect(table.mint(items: [link]) == ["s3"], "an item is never merged: it is the link at that place on the screen")
        #expect(table.mint(notes: []).isEmpty)
    }

    @Test func theScreenClauseIsInJevsReasoningQuestion() {
        #expect(EngineRequest.reasoningLevels[2].contains("the words point at something on the screen that must be looked at before any format can act: this one, the second video, the blue button, the price shown"), "the top level: no extractor can read the screen, so the planner must")
        #expect(!EngineRequest.reasoningLevels[1].contains("screen"))
        #expect(Screen.rule.hasPrefix("The screen is what the user sees now. Fold it in only where the words point at it"))
    }
}
