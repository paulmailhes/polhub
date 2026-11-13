import AppKit
import Foundation
import MeetingsUI
import Observability

/// Shows the pop-up the way the real app will: with no window open, eight seconds after the launch, so
/// there is time to put Dia in full screen or to switch desktop. `--variant floating|statusBar|screenSaver`.
/// It records which app was in front before and after, and whether the pop-up took the focus.
public struct HUDProbe: Probe {
    struct Record: Encodable, Sendable {
        let variant: String
        let frontmostBefore: String?
        let frontmostAfter: String?
        /// Whether this app was already the active one before the pop-up was shown.
        let activeBefore: Bool
        let appBecameActive: Bool
        /// Whether the pop-up held the keyboard focus when it was answered.
        let panelWasKey: Bool
        let clicked: String              // "accept" | "decline" | "expired"
        let screenFrame: [Double]
        let panelFrame: [Double]
    }

    public init() {}

    public func run(_ request: ProbeRequest, trace: TraceWriter, directory: URL) async {
        let variant = HUDPanelController.candidates[request.variant ?? ""] == nil ? "statusBar" : (request.variant ?? "statusBar")

        // Same conditions as in real use: no window, no Dock icon.
        await MainActor.run {
            for window in NSApp.windows where window.isVisible && window.styleMask.contains(.titled) {
                window.close()
            }
            NSApp.setActivationPolicy(.accessory)
        }
        guard await Self.pause(8) else { return }

        let record = await Self.present(variant: variant)
        try? await trace.write(kind: "hud", record)
    }

    @MainActor
    private static func present(variant: String) async -> Record {
        let controller = HUDPanelController(style: HUDPanelController.candidates[variant]!)
        let before = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let activeBefore = NSApp.isActive
        var frames: (screen: CGRect, panel: CGRect) = (.zero, .zero)

        let clicked: String = await withCheckedContinuation { continuation in
            controller.show(
                title: "Google Meet · essai",
                subtitle: "Sonde du pop-up (\(variant))",
                countdownSeconds: 10,
                onAccept: { continuation.resume(returning: "accept") },
                onDecline: { continuation.resume(returning: "decline") },
                onExpire: { continuation.resume(returning: "expired") }
            )
            frames = (controller.screenFrame ?? .zero, controller.frame ?? .zero)
        }

        func list(_ rect: CGRect) -> [Double] { [rect.minX, rect.minY, rect.width, rect.height].map(Double.init) }
        return Record(
            variant: variant,
            frontmostBefore: before,
            frontmostAfter: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            activeBefore: activeBefore,
            appBecameActive: NSApp.isActive && !activeBefore,
            panelWasKey: controller.wasKeyWhenClosed,
            clicked: clicked,
            screenFrame: list(frames.screen),
            panelFrame: list(frames.panel)
        )
    }
}
