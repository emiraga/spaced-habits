// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HabitStore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "HabitStore", targets: ["HabitStore"]),
    ],
    dependencies: [
        .package(path: "../HabitCore"),
    ],
    targets: [
        .target(
            name: "HabitStore",
            dependencies: ["HabitCore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "HabitStoreTests",
            dependencies: ["HabitStore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
