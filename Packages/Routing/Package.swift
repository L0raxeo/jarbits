// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Routing",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "Routing", targets: ["Routing"]),
        .executable(name: "report", targets: ["ReportCLI"]),
    ],
    targets: [
        .target(name: "Routing"),
        .executableTarget(name: "ReportCLI", dependencies: ["Routing"]),
        .testTarget(name: "RoutingTests", dependencies: ["Routing"]),
    ],
    swiftLanguageModes: [.v6]
)
