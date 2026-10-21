import Foundation
import Routing

/// Appends every routing decision to a JSON Lines file on the device. The
/// file is the raw material for the eval set; nothing leaves the phone unless
/// the user exports it from the debug ribbon.
actor DecisionLog {
    static let shared = DecisionLog()

    nonisolated let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
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
            if !FileManager.default.fileExists(atPath: fileURL.path()) {
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
