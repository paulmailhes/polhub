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
        .library(name: "ProjectsUI", targets: ["ProjectsUI"]),
        .library(name: "Updates", targets: ["Updates"]),
        .library(name: "Agenda", targets: ["Agenda"]),
        .library(name: "GoogleKit", targets: ["GoogleKit"]),
        .library(name: "Mail", targets: ["Mail"]),
        .library(name: "MailFormat", targets: ["MailFormat"]),
        .library(name: "Summarization", targets: ["Summarization"]),
        .library(name: "PolhubDesign", targets: ["PolhubDesign"]),
        .library(name: "Notifications", targets: ["Notifications"]),
        .library(name: "Inspiration", targets: ["Inspiration"]),
        .library(name: "Colin", targets: ["Colin"]),
        .executable(name: "polhub-calcul", targets: ["PolhubCalcul"]),
        .executable(name: "polhub", targets: ["PolhubCLI"]),
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
        // Updates from the versions published on GitHub, never during a meeting.
        .target(name: "Updates"),
        // Google calendars, contacts, and the automatic links between events, meetings, contacts and projects.
        // The design system: tokens and components every screen uses (14/11, docs/design-system.md).
        // Its icons are Phosphor's, duotone weight (MIT, the license beside them in Icons/) (15/11).
        .target(name: "PolhubDesign", resources: [.copy("Icons")]),
        // Polhub's notifications: reminders, new events, meetings not recorded, summaries (14/11).
        .target(name: "Notifications", dependencies: [
            .product(name: "Domain", package: "Kernel"),
            .product(name: "Persistence", package: "Kernel"),
        ]),
        // The meetings' summaries, by the model built into macOS: nothing to download, nothing leaves the Mac (14/11).
        .target(name: "Summarization", dependencies: [
            .product(name: "Domain", package: "Kernel"),
            .product(name: "Persistence", package: "Kernel"),
        ]),
        // What every Google service shares: sign-in, Keychain, one session per app (14/11).
        .target(name: "GoogleKit"),
        .target(name: "Agenda", dependencies: [
            "GoogleKit",
            .product(name: "Domain", package: "Kernel"),
            .product(name: "Persistence", package: "Kernel"),
        ]),
        // Gmail, spoken to directly: the client and the measures of step 0 (14/11).
        // What a mail is made of when it leaves: MIME, replies, quotes. Pure, no network (14/11).
        .target(name: "MailFormat", dependencies: [.product(name: "Persistence", package: "Kernel")]),
        .target(name: "Mail", dependencies: ["GoogleKit", "MailFormat", .product(name: "Domain", package: "Kernel"), .product(name: "Persistence", package: "Kernel")]),
        // The projects module: board, views, project page.
        .target(name: "ProjectsUI", dependencies: [
            "PolhubDesign",
            "Summarization",
            .product(name: "Domain", package: "Kernel"),
            .product(name: "Persistence", package: "Kernel"),
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        // « Inspiration » (16/11): the sites, the branding and the mock-ups. The images made light, the vocabularies
        // of the categories (Yams keeps their order), the collection and the tagger. No UI here. The vault's import is
        // gone with the vault (16/11).
        .target(name: "Inspiration", dependencies: [
            .product(name: "Domain", package: "Kernel"),
            .product(name: "Persistence", package: "Kernel"),
            .product(name: "Yams", package: "Yams"),
        ], resources: [.copy("Vocabulary/Resources")]),
        // Colin, the agent of the home page (17/11): how Polhub finds Claude Code on this Mac, starts it alone and reads
        // what it answers. No dependency: the probe of step 0 uses it first, the home page later.
        // Colin (17/11): the engine that launches Claude Code, and the rules of the Accueil, which read the base.
        .target(name: "Colin", dependencies: [.product(name: "Domain", package: "Kernel"), .product(name: "Persistence", package: "Kernel")]),
        // The models live only in `polhub-calcul`: the app never loads them.
        .target(name: "Compute", dependencies: [
            "Transcription",
            "Recording",
            .product(name: "Domain", package: "Kernel"),
            .product(name: "WhisperKit", package: "WhisperKit"),
            .product(name: "FluidAudio", package: "FluidAudio"),
        ]),
        .executableTarget(name: "PolhubCalcul", dependencies: ["Compute", "Transcription"]),
        // Claude Code reads the meetings through these, read-only.
        .target(name: "ReadingKit", dependencies: [
            "MailFormat",
            .product(name: "Domain", package: "Kernel"),
            .product(name: "Persistence", package: "Kernel"),
        ]),
        .executableTarget(name: "PolhubCLI", dependencies: ["ReadingKit", .product(name: "Persistence", package: "Kernel")]),
        .target(name: "MeetingDetection", dependencies: ["AudioCapture", .product(name: "Domain", package: "Kernel"), .product(name: "Observability", package: "Kernel")]),
        .target(name: "MeetingsUI", dependencies: [
            "Recording",
            "MeetingDetection",
            "Pipeline",
            "Transcription",
            "ProjectsUI",
            "Updates",
            "Agenda",
            "GoogleKit",
            "Mail",
            "MailFormat",
            "Summarization",
            "PolhubDesign",
            "Colin",
            "Notifications",
            "Inspiration",
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
            "Colin",
            .product(name: "Domain", package: "Kernel"),
            .product(name: "Observability", package: "Kernel"),
        ]),
        .testTarget(name: "AudioCaptureTests", dependencies: ["AudioCapture"]),
        .testTarget(name: "ComputeTests", dependencies: ["Compute", "Transcription", "Recording", .product(name: "Domain", package: "Kernel")], resources: [.copy("Fixtures")]),
        .testTarget(name: "ReadingKitTests", dependencies: ["ReadingKit", "MailFormat", .product(name: "Domain", package: "Kernel"), .product(name: "Persistence", package: "Kernel")]),
        .testTarget(name: "InspirationTests", dependencies: ["Inspiration", .product(name: "Domain", package: "Kernel"), .product(name: "Persistence", package: "Kernel")], resources: [.copy("Fixtures")]),
        .testTarget(name: "ProjectsUITests", dependencies: ["ProjectsUI", "PolhubDesign", .product(name: "Domain", package: "Kernel"), .product(name: "Persistence", package: "Kernel")]),
        .testTarget(name: "UpdatesTests", dependencies: ["Updates"]),
        .testTarget(name: "NotificationsTests", dependencies: ["Notifications", .product(name: "Domain", package: "Kernel"), .product(name: "Persistence", package: "Kernel")]),
        .testTarget(name: "SummarizationTests", dependencies: ["Summarization", .product(name: "Domain", package: "Kernel"), .product(name: "Persistence", package: "Kernel")]),
        .testTarget(name: "AgendaTests", dependencies: ["Agenda", "GoogleKit", .product(name: "Domain", package: "Kernel"), .product(name: "Persistence", package: "Kernel")]),
        .testTarget(name: "GoogleKitTests", dependencies: ["GoogleKit"]),
        .testTarget(name: "MailTests", dependencies: ["Mail", "GoogleKit", "MailFormat", .product(name: "Domain", package: "Kernel"), .product(name: "Persistence", package: "Kernel"),
                                                      .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "MailFormatTests", dependencies: ["MailFormat", .product(name: "Persistence", package: "Kernel")]),
        .testTarget(name: "TranscriptionTests", dependencies: ["Transcription", .product(name: "Domain", package: "Kernel")]),
        .testTarget(name: "MeetingDetectionTests", dependencies: ["MeetingDetection"], resources: [.copy("Fixtures")]),
        .testTarget(name: "MeetingsUITests", dependencies: ["MeetingsUI", "Colin", "ProjectsUI", "PolhubDesign", "Notifications", "Inspiration", "Agenda", "GoogleKit", "Mail", "MailFormat", "Updates", "Pipeline", "Recording", "AudioCapture", .product(name: "Domain", package: "Kernel"), .product(name: "Persistence", package: "Kernel")]),
        .testTarget(name: "RecordingTests", dependencies: ["Recording", "AudioCapture", "MeetingDetection", .product(name: "Observability", package: "Kernel"), .product(name: "Domain", package: "Kernel")]),
        .testTarget(name: "PipelineTests", dependencies: ["Pipeline", "MeetingDetection", "Recording", "Transcription", .product(name: "Domain", package: "Kernel"), .product(name: "Persistence", package: "Kernel")]),
        .testTarget(name: "ProbeKitTests", dependencies: ["ProbeKit", "Colin", "Recording", "AudioCapture", "MeetingDetection", .product(name: "Domain", package: "Kernel"), .product(name: "Observability", package: "Kernel")]),
        .testTarget(name: "PolhubDesignTests", dependencies: ["PolhubDesign"]),
        .testTarget(name: "ColinTests", dependencies: ["Colin", .product(name: "Domain", package: "Kernel"), .product(name: "Persistence", package: "Kernel")]),
    ]
)
