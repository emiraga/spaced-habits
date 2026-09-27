// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HabitUI",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "HabitUI", targets: ["HabitUI"]),
    ],
    dependencies: [
        .package(path: "../HabitCore"),
    ],
    targets: [
        .target(
            name: "HabitUI",
            dependencies: ["HabitCore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "HabitUITests",
            dependencies: ["HabitUI"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
