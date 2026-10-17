// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fringe",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Fringe", targets: ["FringeApp"])],
    dependencies: [.package(path: "Packages/FringeProtocol")],
    targets: [
        .target(name: "FringeCore"),
        .target(name: "FringeNotch", dependencies: ["FringeCore"]),
        .target(name: "FringeAgents", dependencies: ["FringeCore", "FringeNotch", .product(name: "FringeProtocol", package: "FringeProtocol")]),
        .target(name: "FringeMail", dependencies: ["FringeCore", "FringeNotch"]),
        .target(name: "FringeCalendar", dependencies: ["FringeCore", "FringeNotch"]),
        .target(name: "FringeScreenshots", dependencies: ["FringeCore", "FringeNotch"]),
        .target(name: "FringeTranslate", dependencies: ["FringeCore", "FringeNotch"]),
        .executableTarget(name: "FringeApp", dependencies: [
            "FringeCore", "FringeNotch", "FringeAgents", "FringeMail", "FringeCalendar", "FringeScreenshots", "FringeTranslate"
        ]),
        .testTarget(name: "FringeCoreTests", dependencies: ["FringeCore"]),
        .testTarget(name: "FringeAgentsTests", dependencies: ["FringeAgents"]),
        .testTarget(name: "FringeMailTests", dependencies: ["FringeMail"]),
        .testTarget(name: "FringeCalendarTests", dependencies: ["FringeCalendar"]),
        .testTarget(name: "FringeScreenshotsTests", dependencies: ["FringeScreenshots"]),
        .testTarget(name: "FringeTranslateTests", dependencies: ["FringeTranslate"])
    ]
)
