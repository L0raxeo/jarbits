import Foundation

/// Who the assistant is and who it assists. The assistant is Jarvits; the
/// user is the person holding the phone, by name once they have given it.
/// Every Gemini instruction Jarvits sends opens with `identityLine`, so no
/// model mistakes the speaker for itself, and a fact is kept from Jarvits's
/// point of view ("Lorcan's friend Noah is vegan"). Jev never sees it.
public struct Persona: Sendable, Equatable {
    public static let assistant = "Jarvits"

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

    /// The first line of every system instruction Jarvits sends.
    public var identityLine: String {
        if let userName {
            return "You are \(Self.assistant), the assistant in \(userName)'s phone browser. \(userName) is the person speaking to you; you are not \(userName). Speak of \(userName) by name and of yourself as \(Self.assistant)."
        }
        return "You are \(Self.assistant), the assistant in a phone browser. The person speaking to you is the person you assist, whose name you do not know yet; you are not them. Speak of them as the person and of yourself as \(Self.assistant)."
    }
}

extension String {
    /// "the person you assist" → "The person you assist"; a name is unchanged.
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
