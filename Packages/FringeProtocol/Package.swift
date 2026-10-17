// swift-tools-version: 6.0
import PackageDescription

/// Shared wire format between Fringe and Switchboard (Context Desk). Switchboard pins a tagged version.
let package = Package(
    name: "FringeProtocol",
    platforms: [.macOS(.v14)],
    products: [.library(name: "FringeProtocol", targets: ["FringeProtocol"])],
    targets: [
        .target(name: "FringeProtocol"),
        .testTarget(name: "FringeProtocolTests", dependencies: ["FringeProtocol"])
    ]
)
