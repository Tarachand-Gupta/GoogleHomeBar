// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GoogleHomeBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GoogleHomeBar", targets: ["GoogleHomeBar"])
    ],
    targets: [
        .target(
            name: "GoogleHomeBarCore",
            path: "Sources/GoogleHomeBarCore"
        ),
        .executableTarget(
            name: "GoogleHomeBar",
            dependencies: ["GoogleHomeBarCore"],
            path: "Sources/GoogleHomeBar"
        ),
        .testTarget(
            name: "GoogleHomeBarTests",
            dependencies: ["GoogleHomeBarCore"],
            path: "Tests/GoogleHomeBarTests"
        )
    ]
)
