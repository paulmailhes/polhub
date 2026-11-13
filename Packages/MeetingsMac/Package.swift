// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MeetingsMac",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "AudioCapture", targets: ["AudioCapture"]),
        .library(name: "MeetingDetection", targets: ["MeetingDetection"]),
        .library(name: "MeetingsUI", targets: ["MeetingsUI"]),
        .library(name: "Recording", targets: ["Recording"]),
        .library(name: "Pipeline", targets: ["Pipeline"]),
        .library(name: "ProbeKit", targets: ["ProbeKit"]),
        .library(name: "Transcription", targets: ["Transcription"]),
        .library(name: "Compute", targets: ["Compute"]),
        .library(name: "ReadingKit", targets: ["ReadingKit"]),
        .library(name: "VaultImport", targets: ["VaultImport"]),
        .library(name: "ProjectsUI", targets: ["ProjectsUI"]),
        .executable(name: "transcriptor-calcul", targets: ["TranscriptorCalcul"]),
        .executable(name: "transcriptor", targets: ["TranscriptorCLI"]),
    ],
    dependencies: [
        .package(path: "../Kernel"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.1"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
        // Speech detection only: no speech synthesis, no diarization, no prebuilt binary.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.18.3", traits: []),
    ],
    targets: [
        .target(name: "AudioCapture"),
        .target(name: "Transcription", dependencies: [.product(name: "Domain", package: "Kernel")]),
        // The projects module: board, views, project page.
        .target(name: "ProjectsUI", dependencies: [
            "VaultImport",
            .product(name: "Domain", package: "Kernel"),
            .product(name: "Persistence", package: "Kernel"),
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        // Reads the Obsidian vault for the import of the projects: read-only, never writes.
        .target(name: "VaultImport", dependencies: [
            .product(name: "Domain", package: "Kernel"),
            .product(name: "Persistence", package: "Kernel"),
            .product(name: "Yams", package: "Yams"),
        ]),
        // The models live only in `transcriptor-calcul`: the app never loads them.
        .target(name: "Compute", dependencies: [
            "Transcription",
            "Recording",
            .product(name: "Domain", package: "Kernel"),
            .product(name: "WhisperKit", package: "WhisperKit"),
            .product(name: "FluidAudio", package: "FluidAudio"),
        ]),
        .executableTarget(name: "TranscriptorCalcul", dependencies: ["Compute", "Transcription"]),
        // Claude Code reads the meetings through these, read-only.
        .target(name: "ReadingKit", dependencies: [
            .product(name: "Domain", package: "Kernel"),
            .product(name: "Persistence", package: "Kernel"),
        ]),
        .executableTarget(name: "TranscriptorCLI", dependencies: ["ReadingKit", .product(name: "Persistence", package: "Kernel")]),
        .target(name: "MeetingDetection", dependencies: ["AudioCapture", .product(name: "Domain", package: "Kernel"), .product(name: "Observability", package: "Kernel")]),
        .target(name: "MeetingsUI", dependencies: [
            "Recording",
            "Pipeline",
            "Transcription",
            "ProjectsUI",
            .product(name: "Domain", package: "Kernel"),
            .product(name: "Persistence", package: "Kernel"),
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .target(name: "Recording", dependencies: [
            "AudioCapture",
            "MeetingDetection",
            .product(name: "Domain", package: "Kernel"),
            .product(name: "Observability", package: "Kernel"),
        ]),
        .target(name: "Pipeline", dependencies: [
            "MeetingDetection",
            "Recording",
            "Transcription",
            .product(name: "Domain", package: "Kernel"),
            .product(name: "Persistence", package: "Kernel"),
            .product(name: "Observability", package: "Kernel"),
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .target(name: "ProbeKit", dependencies: [
            "AudioCapture",
            "Recording",
            "Pipeline",
            .product(name: "Persistence", package: "Kernel"),
            "MeetingDetection",
            "MeetingsUI",
            .product(name: "Domain", package: "Kernel"),
            .product(name: "Observability", package: "Kernel"),
        ]),
        .testTarget(name: "AudioCaptureTests", dependencies: ["AudioCapture"]),
        .testTarget(name: "ComputeTests", dependencies: ["Compute", "Transcription", "Recording", .product(name: "Domain", package: "Kernel")], resources: [.copy("Fixtures")]),
        .testTarget(name: "ReadingKitTests", dependencies: ["ReadingKit", .product(name: "Domain", package: "Kernel"), .product(name: "Persistence", package: "Kernel")]),
        .testTarget(name: "VaultImportTests", dependencies: ["VaultImport", .product(name: "Domain", package: "Kernel"), .product(name: "Persistence", package: "Kernel")], resources: [.copy("Fixtures")]),
        .testTarget(name: "ProjectsUITests", dependencies: ["ProjectsUI", "VaultImport", .product(name: "Domain", package: "Kernel"), .product(name: "Persistence", package: "Kernel")]),
        .testTarget(name: "TranscriptionTests", dependencies: ["Transcription", .product(name: "Domain", package: "Kernel")]),
        .testTarget(name: "MeetingDetectionTests", dependencies: ["MeetingDetection"], resources: [.copy("Fixtures")]),
        .testTarget(name: "MeetingsUITests", dependencies: ["MeetingsUI", "ProjectsUI", "Pipeline", "Recording", "AudioCapture", .product(name: "Domain", package: "Kernel"), .product(name: "Persistence", package: "Kernel")]),
        .testTarget(name: "RecordingTests", dependencies: ["Recording", "AudioCapture", "MeetingDetection", .product(name: "Observability", package: "Kernel"), .product(name: "Domain", package: "Kernel")]),
        .testTarget(name: "PipelineTests", dependencies: ["Pipeline", "MeetingDetection", "Recording", "Transcription", .product(name: "Domain", package: "Kernel"), .product(name: "Persistence", package: "Kernel")]),
        .testTarget(name: "ProbeKitTests", dependencies: ["ProbeKit", "Recording", "AudioCapture", "MeetingDetection", .product(name: "Domain", package: "Kernel"), .product(name: "Observability", package: "Kernel")]),
    ]
)
