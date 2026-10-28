import Foundation

/// Server-sent events, one line at a time: `event:` and `data:` fields, a
/// blank line ends an event. Comments and unknown fields are skipped.
package struct SSEParser: Sendable {
    package struct Event: Sendable, Equatable {
        package var name: String
        package var data: String
    }

    private var name = ""
    private var data: [String] = []

    package init() {}

    /// Feed one line without its newline. Returns the event a blank line completes.
    package mutating func feed(line: String) -> Event? {
        if line.isEmpty {
            guard !name.isEmpty || !data.isEmpty else { return nil }
            defer { name = ""; data = [] }
            return Event(name: name, data: data.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = line[...]
            value = ""
        }
        switch field {
        case "event": name = String(value)
        case "data": data.append(String(value))
        default: break
        }
        return nil
    }

    /// The event in progress when the stream ends without a final blank line.
    package mutating func flush() -> Event? {
        feed(line: "")
    }
}
