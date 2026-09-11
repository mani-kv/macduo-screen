// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacFold",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "lid-angle", targets: ["LidAngleCLI"]),
        .executable(name: "MacFold", targets: ["MacFold"])
    ],
    targets: [
        .target(name: "LidSensor", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "FoldCore"),
        .executableTarget(name: "LidAngleCLI", dependencies: ["LidSensor"]),
        .executableTarget(name: "MacFold", dependencies: ["LidSensor", "FoldCore"],
                          resources: [.copy("Rendering/FoldShader.metal")],
                          linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("MetalKit"),
                                           .linkedFramework("MetalPerformanceShaders"),
                                           .linkedFramework("ScreenCaptureKit"), .linkedFramework("ServiceManagement")]),
        .testTarget(name: "LidSensorTests", dependencies: ["LidSensor"]),
        .testTarget(name: "FoldCoreTests", dependencies: ["FoldCore"])
    ]
)
