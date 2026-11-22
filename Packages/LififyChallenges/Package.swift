// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LififyChallenges",
    platforms: [.iOS(.v17)],
    products: [.library(name: "LififyChallenges", targets: ["LififyChallenges"])],
    dependencies: [
        .package(path: "../LififyCore")
    ],
    targets: [
        .target(name: "LififyChallenges", dependencies: ["LififyCore"])
    ]
)
