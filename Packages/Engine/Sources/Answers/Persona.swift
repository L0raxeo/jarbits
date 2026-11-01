import Foundation

/// Who the assistant is and who it assists. The assistant is Jarbits; the
/// user is the person holding the phone, by name once they have given it.
/// Every Gemini instruction Jarbits sends opens with one of two lines, so
/// no model mistakes the speaker for itself: `identityLine` where he writes
/// or answers (the fact reader, the answers, the planner), so a fact is
/// kept from his point of view ("Lorcan's friend Noah is vegan");
/// `readerLine` where he only reads (the reading, the value reader), so the
/// user's words come back as the user's, never recast in his. Jev never
/// sees either.
public struct Persona: Sendable, Equatable {
    public static let assistant = "Jarbits"

    /// The user's name; nil until asked and given.
    public var userName: String?

    public init(userName: String? = nil) {
        let trimmed = userName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.userName = trimmed?.isEmpty == false ? trimmed : nil
    }

    /// For reports and tests.
    public static let example = Persona(userName: "Lorcan")

    /// How the prompts refer to the user.
    public var user: String { userName ?? "the person you assist" }

    /// The possessive: "Lorcan's", or "the person's" when the name is not known.
    public var users: String { userName.map { $0 + "'s" } ?? "the person's" }

    /// The first line of the instructions where Jarbits writes or answers.
    public var identityLine: String {
        if let userName {
            return "You are \(Self.assistant), the assistant in \(userName)'s phone browser. \(userName) is the person speaking to you; you are not \(userName). Speak of \(userName) by name and of yourself as \(Self.assistant)."
        }
        return "You are \(Self.assistant), the assistant in a phone browser. The person speaking to you is the person you assist, whose name you do not know yet; you are not them. Speak of them as the person and of yourself as \(Self.assistant)."
    }

    /// The first line of the instructions where Jarbits speaks to the user
    /// (both answer formats, the planner, the closing line): who he is and
    /// whom he speaks to, as "you", with `Voice.guide` for how. It leaves
    /// out `identityLine`'s "speak of them by name", which is for the facts
    /// he writes and which made every reply open with the name.
    public var speakerLine: String {
        if let userName {
            return "You are \(Self.assistant), \(userName)'s own assistant, on \(userName)'s phone. \(userName) is the person speaking to you; you are not \(userName). You speak to \(userName) directly: \"you\" for them, \"I\" for yourself."
        }
        return "You are \(Self.assistant), the assistant of the person holding this phone. The person speaking to you is the person you assist, whose name you do not know yet; you are not them. You speak to them directly: \"you\" for them, \"I\" for yourself."
    }

    /// The first line of the instructions where Jarbits only reads: the
    /// words he hands back are the user's, in the user's own voice.
    public var readerLine: String {
        if let userName {
            return "You are \(Self.assistant), the assistant in \(userName)'s phone browser. \(userName) is the person speaking to you; you are not \(userName). What you hand back is \(userName)'s request in \(userName)'s own words, not your words about it."
        }
        return "You are \(Self.assistant), the assistant in a phone browser. The person speaking to you is the person you assist, whose name you do not know yet; you are not them. What you hand back is their request in their own words, not your words about it."
    }
}

extension String {
    /// "the person you assist" → "The person you assist"; a name is unchanged.
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
