// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Engine",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "Engine", targets: ["Engine"]),
        .library(name: "Answers", targets: ["Answers"]),
        .library(name: "Images", targets: ["Images"]),
        .library(name: "Sites", targets: ["Sites"]),
        .library(name: "Evals", targets: ["Evals"]),
        .executable(name: "report", targets: ["ReportCLI"]),
    ],
    targets: [
        .target(name: "Engine"),
        .target(name: "Answers", dependencies: ["Engine"]),
        .target(name: "Images", dependencies: ["Engine"]),
        .target(name: "Sites", dependencies: ["Engine"]),
        .target(name: "Evals", dependencies: ["Engine"]),
        .executableTarget(name: "ReportCLI", dependencies: ["Engine", "Answers", "Images", "Sites", "Evals"]),
        .testTarget(name: "EngineTests", dependencies: ["Engine"]),
        .testTarget(name: "AnswersTests", dependencies: ["Answers"]),
        .testTarget(name: "ImagesTests", dependencies: ["Images", "Answers"]),
        .testTarget(name: "SitesTests", dependencies: ["Sites", "Answers", "Images"]),
        .testTarget(name: "EvalsTests", dependencies: ["Evals", "Engine"]),
    ],
    swiftLanguageModes: [.v6]
)
