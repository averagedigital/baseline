// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Baseline",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AthleteCore", targets: ["AthleteCore"]),
        .library(name: "AthleteAgents", targets: ["AthleteAgents"]),
    ],
    targets: [
        .target(name: "AthleteCore"),
        .target(name: "AthleteAgents", dependencies: ["AthleteCore"]),
        .testTarget(name: "AthleteCoreTests", dependencies: ["AthleteCore"]),
        .testTarget(name: "AthleteAgentsTests", dependencies: ["AthleteAgents", "AthleteCore"]),
    ]
)
