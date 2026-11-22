// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LififyCore",
    platforms: [.iOS(.v17)],
    products: [.library(name: "LififyCore", targets: ["LififyCore"])],
    dependencies: [

    ],
    targets: [
        .target(name: "LififyCore", dependencies: [])
    ]
)
