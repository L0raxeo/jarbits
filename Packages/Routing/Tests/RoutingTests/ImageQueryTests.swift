import Foundation
import Testing
@testable import Routing

@Suite struct ImageQueryTests {
    @Test(arguments: [
        ("show me a picture of the eiffel tower", "eiffel tower"),
        ("Show me a picture of the Eiffel Tower", "Eiffel Tower"),
        ("what does a capybara look like", "capybara"),
        ("what do capybaras look like", "capybaras"),
        ("how does the dominican flag look", "dominican flag"),
        ("show me the eiffel tower", "eiffel tower"),
        ("picture of the mona lisa please", "mona lisa"),
        ("pull up a photo of the dominican flag", "dominican flag"),
        ("find me pics of saturn", "saturn"),
        ("can you show me an image of the nvidia logo", "nvidia logo"),
        ("a photograph of starry night", "starry night"),
        ("get me some pictures of the aston martin db5 for me", "aston martin db5"),
    ])
    func theAskingComesOffAroundTheSubject(query: String, subject: String) {
        #expect(ImageQuery.parse(query)?.subject == subject, "\(query)")
        #expect(ImageQuery.subject(for: query) == subject, "\(query)")
    }

    @Test(arguments: ["dominican flag", "eiffel tower", "mona lisa", "starry night painting", "picture of", "show me", "please"])
    func aBareSubjectIsLeftAlone(query: String) {
        #expect(ImageQuery.parse(query) == nil, "\(query)")
        #expect(ImageQuery.subject(for: query) == query)
    }
}
