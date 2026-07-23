// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GTARadioKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "GTARadioKit", targets: ["GTARadioKit"])
    ],
    targets: [
        .target(name: "GTARadioKit"),
        .testTarget(name: "GTARadioKitTests", dependencies: ["GTARadioKit"])
    ]
)
