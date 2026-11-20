// swift-tools-version: 6.2
import PackageDescription

/// What Polhub on the Mac and Polhub on the iPhone say to each other (20/11): the API's addresses, the pairing link and
/// the JSON types. Foundation only, for both platforms; and the copy in iCloud (`HubCloud`).
let package = Package(
    name: "Link",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "HubLink", targets: ["HubLink"]),
        .library(name: "HubCloud", targets: ["HubCloud"]),
    ],
    targets: [
        .target(name: "HubLink"),
        // The copy in the user's iCloud (20/11), for the Mac which writes it and the iPhone which reads it.
        .target(name: "HubCloud", dependencies: ["HubLink"]),
        .testTarget(name: "HubLinkTests", dependencies: ["HubLink"]),
        .testTarget(name: "HubCloudTests", dependencies: ["HubCloud", "HubLink"]),
    ]
)
