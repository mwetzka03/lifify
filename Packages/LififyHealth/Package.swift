// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LififyHealth",
    platforms: [.iOS(.v17)],
    products: [.library(name: "LififyHealth", targets: ["LififyHealth"])],
    dependencies: [
        .package(path: "../LififyCore"),
        .package(path: "../LififyChallenges")
    ],
    targets: [
        .target(name: "LififyHealth", dependencies: ["LififyCore", "LififyChallenges"])
    ]
)
