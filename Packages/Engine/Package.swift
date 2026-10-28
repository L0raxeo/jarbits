// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Engine",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "Engine", targets: ["Engine"]),
        .library(name: "Answers", targets: ["Answers"]),
        .library(name: "Sites", targets: ["Sites"]),
        .library(name: "Evals", targets: ["Evals"]),
        .executable(name: "report", targets: ["ReportCLI"]),
    ],
    targets: [
        .target(name: "Engine"),
        .target(name: "Answers", dependencies: ["Engine"]),
        .target(name: "Sites", dependencies: ["Engine"]),
        .target(name: "Evals", dependencies: ["Engine", "Answers"]),
        .executableTarget(name: "ReportCLI", dependencies: ["Engine", "Answers", "Sites", "Evals"]),
        .testTarget(name: "EngineTests", dependencies: ["Engine"]),
        .testTarget(name: "AnswersTests", dependencies: ["Answers"]),
        .testTarget(name: "SitesTests", dependencies: ["Sites", "Answers"]),
        .testTarget(name: "EvalsTests", dependencies: ["Evals", "Engine", "Answers"]),
    ],
    swiftLanguageModes: [.v6]
)
