import Foundation
import Engine

/// Appends every routing decision (and, once Gemini has answered, the answer
/// summary) to a JSON Lines file on the device. The file is the raw material
/// for the eval set; nothing leaves the phone unless the user exports it
/// from the debug ribbon.
actor DecisionLog {
    static let shared = DecisionLog()

    nonisolated let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            // "Browser" is the project's old name, kept: the files already on the phone are there.
            let support = URL.applicationSupportDirectory.appending(path: "Browser", directoryHint: .isDirectory)
            self.fileURL = support.appending(path: "decisions.jsonl")
        }
    }

    func append(_ record: DecisionRecord) {
        do {
            var line = try DecisionRecord.encoder.encode(record)
            line.append(UInt8(ascii: "\n"))

            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // `path(percentEncoded: false)`: the encoded form has
            // "Application%20Support", which never exists, and the empty
            // write below would wipe the file before every line.
            if !FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                try Data().write(to: fileURL)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            // A failed log line must never affect the search itself.
            print("DecisionLog: \(error)")
        }
    }
}
