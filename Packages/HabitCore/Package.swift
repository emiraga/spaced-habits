// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HabitCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "HabitCore", targets: ["HabitCore"]),
    ],
    targets: [
        .target(
            name: "HabitCore",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "HabitCoreTests",
            dependencies: ["HabitCore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
