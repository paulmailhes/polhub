import Persistence
import PolhubDesign
import QuickLook
import SwiftUI

/// What opens over a page that shows mails (18/11): a thread in its floating panel, the new mail, the bar that calls
/// a mail back, the preview of a file and the two dialogs. Mails puts them over its list; the Accueil over itself,
/// with a thread of its own (« Relire », « Ouvrir »), so that reading a draft never leaves the Accueil.
struct MailPanels: ViewModifier {
    @ObservedObject var mails: MailLibrary
    @ObservedObject var router: WindowRouter
    /// The thread open over the page.
    @Binding var thread: String?
    /// Whether the thread opens in a panel over the page; else the page shows it itself (Réglages › Général, in Mails).
    let floating: Bool
    /// The thread leads to its neighbours of the list (Mails), or is one thread alone (the Accueil).
    let browses: Bool
    /// The page behind, in the window's title.
    let title: String
    /// Whether the bar says that a draft an agent prepared waits (Mails), or leaves it to the page's own line (the Accueil).
    let draftNews: Bool
    /// The height of a bar of the page at its bottom: the bar of a sending stays above it.
    var lift: CGFloat = 0

    /// The mail leaving is a reply under the thread open: its own bar says « Envoyé · Annuler » (lot 6, 19/11), and the
    /// bar at the bottom of the page does not say it a second time, over the reply. A new mail closes as it leaves: the
    /// bar at the bottom says it.
    static func sendingInBar(_ sendingDraft: String?, drafts: [MailDraftRow], thread: String?) -> Bool {
        guard let sendingDraft, let thread else { return false }
        return drafts.contains { $0.id == sendingDraft && $0.threadKey == thread }
    }

    /// ✕, Échap, a click beside: back where the thread was opened from, without a step of its own (lot 4, 19/11).
    private func close() {
        if !router.close() { thread = nil }
    }

    /// A draft's bar is fixed at the bottom: a new mail, or an open thread with a reply below.
    private var composeBarShown: Bool {
        mails.composing != nil || thread.map { key in mails.drafts.contains { $0.threadKey == key } } == true
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if floating, let key = thread {
                    FloatingPanel(close: close) {
                        MailThreadView(key: key, mails: mails, router: router, close: close, select: { thread = $0 }, browses: browses, title: title).id(key)
                    }
                }
            }
            .overlay {
                if let draft = mails.composing {
                    FloatingPanel(close: { mails.closeComposer() }) { NewMailPanel(draftID: draft, mails: mails).id(draft) }
                }
            }
            .animation(Motion.standard, value: thread)
            .animation(Motion.standard, value: mails.composing)
            // « Envoyer » closes the thread (`MailLibrary.startSending`, Paul, 20/11); « Annuler » in the pill opens it again
            // on the reply.
            .onChange(of: mails.reopenThread) { _, key in
                guard let key else { return }
                thread = key
                mails.reopenThread = nil
            }
            // Above the bar of a draft fixed at the bottom, never over it (review of 17/11).
            .overlay(alignment: .bottom) {
                MailUndoBar(mails: mails, draftNews: draftNews)
                    .padding(.bottom, composeBarShown ? 80 : lift)
            }
            // One Quick Look for the list's chips and the open thread's files (15/11): two would fight over the
            // window's single preview panel.
            .quickLookPreview($mails.preview)
            .confirmationDialog("Se désabonner \(Words.of(mails.unsubscribeRequest?.name ?? "")) ?",
                                isPresented: Binding(get: { mails.unsubscribeRequest != nil }, set: { if !$0 { mails.unsubscribeRequest = nil } }),
                                presenting: mails.unsubscribeRequest) { request in
                Button("Se désabonner") { mails.unsubscribe(from: request.sender, by: request.method) }
            } message: { request in
                // « Se désabonner », hence « désabonnement », never « désinscription » (lot 10, 20/11).
                switch request.method {
                case .oneClick: Text("La demande part vers \(request.method.domain), le serveur de l'expéditeur. Les mails déjà reçus restent.")
                case .mail(let to, _): Text("Un mail de désabonnement vers \(to) est préparé : tu l'envoies toi-même.")
                case .page: Text("La page de désabonnement \(Words.of(request.method.domain)) s'ouvre dans ton navigateur.")
                }
            }
            .sheet(isPresented: Binding(get: { mails.original != nil }, set: { if !$0 { mails.original = nil } })) {
                if let original = mails.original { MailOriginalSheet(title: original.title, text: original.text) { mails.original = nil } }
            }
    }
}

extension View {
    /// The mails' panels over this page: `thread` is the thread open over it.
    /// `lift`: the height of a bar of the page at its bottom (Colin's), which the bar of a sending stays above.
    func mailPanels(_ mails: MailLibrary, router: WindowRouter, thread: Binding<String?>, floating: Bool = true, browses: Bool = true,
                    title: String = "Mails", draftNews: Bool = true, lift: CGFloat = 0) -> some View {
        modifier(MailPanels(mails: mails, router: router, thread: thread, floating: floating, browses: browses, title: title, draftNews: draftNews,
                            lift: lift))
    }
}
