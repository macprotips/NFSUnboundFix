// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NFSUnboundFix",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "NFSUnboundFix", targets: ["NFSUnboundFix"]),
    ],
    targets: [
        // Finding, checking, backing up, patching and restoring the DLL. No UI, so it is easy to test.
        .target(name: "NFSUnboundFixKit"),
        // The SwiftUI app.
        .executableTarget(name: "NFSUnboundFix", dependencies: ["NFSUnboundFixKit"]),
        .testTarget(name: "NFSUnboundFixKitTests", dependencies: ["NFSUnboundFixKit"]),
    ]
)
