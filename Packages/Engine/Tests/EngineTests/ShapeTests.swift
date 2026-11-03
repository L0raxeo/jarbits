import Foundation
import Testing
@testable import Engine

@Suite struct ShapeTests {
    @Test func aLineIsOneRowOfAtMostTwelveWords() {
        #expect(Shape.of("Lima") == .line)
        #expect(Shape.of("==May== 2028") == .line)
        #expect(Shape.of("Very well, thank you. And yourself, sir?") == .line)
        #expect(Shape.of("one two three four five six seven eight nine ten eleven twelve") == .line)
        #expect(Shape.of("one two three four five six seven eight nine ten eleven twelve thirteen") == .prose)
        #expect(Shape.of("Short.\nBut two rows.") == .prose)
        #expect(Shape.of("  ") == .prose, "nothing is not a line")
        #expect(Shape.of("**bold** __caveat__ _name_ ==key==") == .line, "markers are not words")
    }

    @Test func whileStreamingALineHoldsUntilItOutgrowsOne() {
        let text = "It's due to Rayleigh scattering, sir. Sunlight reaching the atmosphere is scattered in all directions"
        var seen: [Shape] = []
        for end in stride(from: 1, through: text.count, by: 7) {
            seen.append(Shape.streaming(String(text.prefix(end))))
        }
        #expect(seen.first == .line && seen.last == .prose)
        #expect(seen == seen.sorted { $0 == .line && $1 == .prose } || !seen.contains(.prose) || seen.firstIndex(of: .prose).map { index in seen[index...].allSatisfy { $0 == .prose } } == true, "never back to a line")
        #expect(Shape.streaming("May") == .line)
        #expect(Shape.streaming("May\n") == .prose)
        let turn = AnswerTurn(query: "capital of peru", answer: "Lima", format: .narrative)
        #expect(turn.shape == .line, "the shape is read off the text, whatever the format")
    }
}
