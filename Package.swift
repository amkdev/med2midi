// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "med2midi",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MEDKit", targets: ["MEDKit"]),
        .executable(name: "medprobe", targets: ["medprobe"]),
    ],
    targets: [
        .target(name: "MEDKit"),
        .executableTarget(name: "medprobe", dependencies: ["MEDKit"]),
        .testTarget(name: "MEDKitTests", dependencies: ["MEDKit"]),
    ]
)
