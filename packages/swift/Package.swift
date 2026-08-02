// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Baseline",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AthleteCore", targets: ["AthleteCore"]),
        .library(name: "AthleteAgents", targets: ["AthleteAgents"]),
        .library(name: "AthleteStore", targets: ["AthleteStore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        .target(name: "AthleteCore"),
        .target(name: "AthleteAgents", dependencies: ["AthleteCore"]),
        .target(
            name: "AthleteStore",
            dependencies: ["AthleteCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "AthleteCoreTests", dependencies: ["AthleteCore"]),
        .testTarget(name: "AthleteAgentsTests", dependencies: ["AthleteAgents", "AthleteCore"]),
        .testTarget(
            name: "AthleteStoreTests",
            dependencies: ["AthleteStore", "AthleteCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
    ]
)
