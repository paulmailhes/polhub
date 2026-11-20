// swift-tools-version: 6.2
import PackageDescription

/// What Polhub on the Mac and Polhub on the iPhone say to each other (20/11): the API's addresses, the pairing link and
/// the JSON types. Foundation only, for both platforms.
let package = Package(
    name: "Link",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "PolhubLink", targets: ["PolhubLink"]),
    ],
    targets: [
        .target(name: "PolhubLink"),
        .testTarget(name: "PolhubLinkTests", dependencies: ["PolhubLink"]),
    ]
)
