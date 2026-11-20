// swift-tools-version: 6.2
import PackageDescription

/// What Polhub on the Mac and Polhub on the iPhone say to each other (20/11): the API's addresses, the pairing link and
/// the JSON types. Foundation only, for both platforms; and the copy in iCloud (`PolhubCloud`).
let package = Package(
    name: "Link",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "PolhubLink", targets: ["PolhubLink"]),
        .library(name: "PolhubCloud", targets: ["PolhubCloud"]),
    ],
    targets: [
        .target(name: "PolhubLink"),
        // The copy in the user's iCloud (20/11), for the Mac which writes it and the iPhone which reads it.
        .target(name: "PolhubCloud", dependencies: ["PolhubLink"]),
        .testTarget(name: "PolhubLinkTests", dependencies: ["PolhubLink"]),
        .testTarget(name: "PolhubCloudTests", dependencies: ["PolhubCloud", "PolhubLink"]),
    ]
)
