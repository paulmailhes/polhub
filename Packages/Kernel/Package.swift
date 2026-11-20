// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kernel",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "Observability", targets: ["Observability"]),
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Persistence", targets: ["Persistence"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "Observability"),
        .target(name: "Domain"),
        .target(name: "Persistence", dependencies: ["Domain", "Observability", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "ObservabilityTests", dependencies: ["Observability"]),
        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence", "Domain", .product(name: "GRDB", package: "GRDB.swift")]),
    ]
)
