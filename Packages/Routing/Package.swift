// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Routing",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "Routing", targets: ["Routing"]),
    ],
    targets: [
        .target(name: "Routing"),
        .testTarget(name: "RoutingTests", dependencies: ["Routing"]),
    ],
    swiftLanguageModes: [.v6]
)
