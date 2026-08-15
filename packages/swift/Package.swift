// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Baseline",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AthleteCore", targets: ["AthleteCore"]),
        .library(name: "AthleteSensors", targets: ["AthleteSensors"]),
        .library(name: "AthleteStore", targets: ["AthleteStore"]),
        .library(name: "AthleteNutrition", targets: ["AthleteNutrition"]),
        .library(name: "AthletePersonalization", targets: ["AthletePersonalization"]),
        .library(name: "AthleteIntelligence", targets: ["AthleteIntelligence"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        .target(name: "AthleteCore"),
        .target(name: "AthleteSensors", dependencies: ["AthleteCore"]),
        .target(name: "AthleteNutrition", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "AthletePersonalization"),
        .target(name: "AthleteIntelligence", dependencies: ["AthleteCore"]),
        .target(
            name: "AthleteStore",
            dependencies: ["AthleteCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "AthleteCoreTests", dependencies: ["AthleteCore"]),
        .testTarget(name: "AthleteSensorsTests", dependencies: ["AthleteSensors", "AthleteStore"]),
        .testTarget(name: "AthleteNutritionTests", dependencies: ["AthleteNutrition"]),
        .testTarget(name: "AthletePersonalizationTests", dependencies: ["AthletePersonalization"]),
        .testTarget(name: "AthleteIntelligenceTests", dependencies: ["AthleteIntelligence"]),
        .testTarget(
            name: "AthleteStoreTests",
            dependencies: ["AthleteStore", "AthleteCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
    ]
)
