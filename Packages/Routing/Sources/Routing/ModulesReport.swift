import Foundation

/// Renders `MODULES.md` from the formats' stages. Deterministic: nothing in
/// the output changes unless `ResponseFormat` changes, so a test can compare
/// the committed file byte for byte.
public enum ModulesReport {
    public static let regenerateCommand = "swift run --package-path Packages/Routing report modules > MODULES.md"

    public static func markdown() -> String {
        var lines: [String] = []
        lines.append("# Modules")
        lines.append("")
        lines.append("Generated from `ResponseFormat` in `Packages/Routing`. Do not edit by hand; run:")
        lines.append("")
        lines.append("```")
        lines.append(regenerateCommand)
        lines.append("```")
        lines.append("")
        lines.append("| Module | Jev option | Stage | Renders today | Needs |")
        lines.append("|---|---|---|---|---|")
        for format in ResponseFormat.allCases {
            let renders = format.stage >= .built ? "its own card" : "web results (fallback)"
            lines.append("| \(format.title) | `\(format.rawValue)` | \(format.stage.rawValue) | \(renders) | \(format.needs ?? "") |")
        }
        lines.append("")
        let counts = Dictionary(grouping: ResponseFormat.allCases, by: \.stage).mapValues(\.count)
        lines.append("\(counts[.verified, default: 0]) of \(ResponseFormat.allCases.count) verified, \(counts[.built, default: 0]) built, \(counts[.routed, default: 0]) routed.")
        lines.append("")
        lines.append("## Stages")
        lines.append("")
        lines.append("- **routed**: Jev can pick it; the app shows web results in its place.")
        lines.append("- **built**: a real card renders for it.")
        lines.append("- **verified**: used on a device and accepted.")
        lines.append("")
        lines.append("A module moves stage in `ResponseFormat.stage`, in the same change that adds its card. `JevRouter.plan(for:query:)` asserts the stage and the card agree, and the `ModulesTests` suite fails until this file is regenerated.")
        return lines.joined(separator: "\n") + "\n"
    }
}
