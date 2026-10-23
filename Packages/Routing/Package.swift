// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Routing",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "Routing", targets: ["Routing"]),
        .library(name: "Answers", targets: ["Answers"]),
        .library(name: "Images", targets: ["Images"]),
        .library(name: "Sites", targets: ["Sites"]),
        .executable(name: "report", targets: ["ReportCLI"]),
    ],
    targets: [
        .target(name: "Routing"),
        .target(name: "Answers", dependencies: ["Routing"]),
        .target(name: "Images", dependencies: ["Routing"]),
        .target(name: "Sites", dependencies: ["Routing"]),
        .executableTarget(name: "ReportCLI", dependencies: ["Routing", "Answers", "Images", "Sites"]),
        .testTarget(name: "RoutingTests", dependencies: ["Routing"]),
        .testTarget(name: "AnswersTests", dependencies: ["Answers"]),
        .testTarget(name: "ImagesTests", dependencies: ["Images", "Answers"]),
        .testTarget(name: "SitesTests", dependencies: ["Sites", "Answers", "Images"]),
    ],
    swiftLanguageModes: [.v6]
)
