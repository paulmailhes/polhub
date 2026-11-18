import os
import PolhubDesign
import SwiftUI

/// The Claude accounts Vigie knows (0.36.0, 18/11), read once a minute while the Accueil shows. The app alone makes one:
/// a window made without it (a capture, a test) never reads Vigie.
@MainActor public final class ClaudeAccountsModel: ObservableObject {
    @Published private(set) var accounts: [ClaudeAccount]?
    private let reader: VigieAccountsReader?
    private var reading: VigieReading?
    private static let log = Logger(subsystem: "fr.paulmailhes.polhub", category: "vigie")

    public init() {
        reader = VigieAccountsReader()
    }

    /// Accounts given (the captures): nothing is read.
    init(accounts: [ClaudeAccount]?) {
        reader = nil
        self.accounts = accounts
    }

    /// Reads now, then every minute, until the Accueil goes.
    func watch() async {
        guard let reader else { return }
        while !Task.isCancelled {
            let (accounts, reading) = await reader.read()
            if accounts != self.accounts { self.accounts = accounts }
            if reading != self.reading {
                self.reading = reading
                Self.log.notice("Vigie : \(reading.said, privacy: .public)")
            }
            try? await Task.sleep(for: .seconds(60))
        }
    }
}

/// « Comptes Claude »: a line per account — its name, a bar of the tightest quota, how much is used —, and under it
/// whether it holds until the reset or when it fills, in the accent then. Nothing at all without Vigie.
struct ClaudeAccountsCard: View {
    @ObservedObject var model: ClaudeAccountsModel

    var body: some View {
        if let accounts = model.accounts, !accounts.isEmpty {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                HomeCard("Comptes Claude") {
                    ForEach(accounts) { account in
                        row(ClaudeAccountsText.row(account, now: context.date, calendar: CalendarView.calendar))
                            .homeRow(first: account.id == accounts.first?.id)
                    }
                }
            }
        }
    }

    private static let labelWidth: CGFloat = 80

    private func row(_ row: ClaudeAccountsText.Row) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: Space.s) {
                Text(row.label).font(.rowBody).lineLimit(1).frame(width: Self.labelWidth, alignment: .leading)
                bar(row.fraction)
                Text(row.percent).font(.meta.monospacedDigit()).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
            }
            HStack(spacing: Space.xs) {
                Text(row.verdict)
                    .foregroundStyle(row.alarming ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .fontWeight(row.alarming ? .semibold : .regular)
                if let model = row.model { Text("· \(model)").foregroundStyle(.secondary) }
                if let session = row.session { Text("· \(session)").foregroundStyle(.secondary) }
            }
            .font(.meta)
            .lineLimit(1)
            .padding(.leading, Self.labelWidth + Space.s)
        }
        .accessibilityElement(children: .combine)
    }

    private func bar(_ fraction: Double?) -> some View {
        GeometryReader { space in
            Capsule().fill(Surface.fill)
                .overlay(alignment: .leading) {
                    if let fraction {
                        Capsule().fill(Color.primary.opacity(0.5)).frame(width: max(6, space.size.width * fraction))
                    }
                }
        }
        .frame(height: 6)
    }
}
