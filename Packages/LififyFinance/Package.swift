// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LififyFinance",
    platforms: [.iOS(.v17)],
    products: [.library(name: "LififyFinance", targets: ["LififyFinance"])],
    dependencies: [
        .package(path: "../LififyCore")
    ],
    targets: [
        .target(name: "LififyFinance", dependencies: ["LififyCore"])
    ]
)
