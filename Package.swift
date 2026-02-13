// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Listen",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.1"),
    ],
    targets: [
        .executableTarget(
            name: "Listen",
            dependencies: ["FluidAudio"],
            path: "Listen",
            exclude: [
                "Resources/Listen.entitlements",
                "Resources/Info.plist",
                "Resources/AppIcon.icns",
                "Resources/MenuBarIconTemplate.png",
                "Resources/MenuBarIconTemplate@2x.png",
                "Resources/Listen icon.png",
                "Resources/Listen transparent.png",
            ],
            resources: [
                .process("Resources/Assets.xcassets"),
            ]
        ),
    ]
)
