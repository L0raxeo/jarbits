import Foundation
import Testing
@testable import Engine

@Suite struct ConversationMemoryTests {
    private let launch = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func anHourOfSteadyTalkStaysWhole() {
        var memory = ConversationMemory(started: launch)
        for minute in stride(from: 0, through: 60, by: 5) {
            memory.heard(at: launch.addingTimeInterval(TimeInterval(minute * 60)))
        }
        #expect(memory.started == launch)
        #expect(memory.keeps(launch.addingTimeInterval(60)))
    }

    @Test func twentyOneMinutesOfSilenceStartAgain() {
        var memory = ConversationMemory(started: launch)
        memory.heard(at: launch)
        let later = launch.addingTimeInterval(21 * 60)
        memory.heard(at: later)
        #expect(memory.started == later)
        #expect(!memory.keeps(launch.addingTimeInterval(60)), "what came before the silence is gone")
        #expect(memory.keeps(later))
    }

    @Test func exactlyTwentyMinutesDoesNot() {
        var memory = ConversationMemory(started: launch)
        memory.heard(at: launch)
        memory.heard(at: launch.addingTimeInterval(ConversationMemory.silence))
        #expect(memory.started == launch)
    }

    @Test func aDateBeforeTheStartIsNotKept() {
        let memory = ConversationMemory(started: launch)
        #expect(!memory.keeps(launch.addingTimeInterval(-1)))
        #expect(memory.keeps(launch))
    }

    @Test func theThreadGrowsOnlyWhenTheChainEndsOnScreen() {
        let shown = UUID()
        #expect(Pick.continuesOnScreen(chainEndsOn: shown, current: shown))
        #expect(!Pick.continuesOnScreen(chainEndsOn: shown, current: UUID()), "an archived answer is context, not the thread")
        #expect(!Pick.continuesOnScreen(chainEndsOn: nil, current: shown))
    }
}
