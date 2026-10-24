import Foundation
import Testing
@testable import Routing

@Suite struct AnswerQueryTests {
    @Test(arguments: [
        ("Can you ask AI what are some alternatives to Dyson", "what are some alternatives to Dyson"),
        ("ask ai what does gdp mean", "what does gdp mean"),
        ("hey could you ask the AI to tell me what GDP means please", "what GDP means"),
        ("Ask an AI about the French Revolution.", "the French Revolution"),
        ("ask chatgpt why the sky is blue, thanks", "why the sky is blue"),
        ("yo ask ai how long cold sores last for me", "how long cold sores last"),
    ])
    func theQuestionIsWhatFollowsTheAsk(query: String, question: String) {
        #expect(AnswerQuery.parse(query)?.question == question, Comment(rawValue: query))
        #expect(AnswerQuery.question(for: query) == question)
    }

    @Test(arguments: ["ask ai", "please ask the AI", "what does gdp mean", "ask my mom", "task ai to do it", "ai alternatives to dyson"])
    func nothingToAskOrNoAskIsNotOne(query: String) {
        #expect(AnswerQuery.parse(query) == nil, Comment(rawValue: query))
        #expect(AnswerQuery.question(for: query) == query)
    }
}
