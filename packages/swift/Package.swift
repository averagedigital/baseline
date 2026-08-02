// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Baseline",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AthleteCore", targets: ["AthleteCore"]),
    ],
    targets: [
        .target(name: "AthleteCore"),
        .testTarget(name: "AthleteCoreTests", dependencies: ["AthleteCore"]),
    ]
)
