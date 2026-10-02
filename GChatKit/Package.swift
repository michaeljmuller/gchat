// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GChatKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "GChatKit", targets: ["GChatKit"]),
    ],
    targets: [
        .target(name: "GChatKit"),
        .testTarget(name: "GChatKitTests", dependencies: ["GChatKit"]),
    ]
)
