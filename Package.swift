// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "med2midi",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MEDKit", targets: ["MEDKit"]),
        .executable(name: "medprobe", targets: ["medprobe"]),
        .executable(name: "MED2MIDI", targets: ["MED2MIDI"]),
    ],
    targets: [
        .target(name: "MEDKit"),
        .executableTarget(name: "medprobe", dependencies: ["MEDKit"]),
        .executableTarget(name: "MED2MIDI", dependencies: ["MEDKit"]),
        .testTarget(name: "MEDKitTests", dependencies: ["MEDKit"]),
    ]
)
