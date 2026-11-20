import Agenda
import Domain
import MailFormat
import Persistence
import HubDesign
import SwiftUI

/// What opens the editor: a new event (at a time, or now) or one to change.
struct EditorRequest: Identifiable {
    let id = UUID()
    var event: CalendarEventRow?
    var start: Date?
}

/// Creates or changes an event, sent to Google (Paul, 14/11): title, calendar, times, Meet, place, guests,
/// notes. Google sends the invitations.
struct EventEditor: View {
    @ObservedObject var agenda: AgendaLibrary
    let editing: CalendarEventRow?
    @State private var draft: EventDraft
    @State private var account: String
    @State private var guestQuery = ""
    /// The suggestion lit, as in the mails' fields (15/11).
    @State private var highlighted = 0
    @State private var moved = false
    @State private var dismissed = false
    @FocusState private var guestFocused: Bool
    @State private var saving = false
    /// What did not work, hub's sentence (`Words.problem`), never the system's text (lot 10, 20/11).
    @State private var failure: String?
    @State private var confirmingDelete = false
    /// What the event was, and what Google holds, read before changing it (review of 14/11).
    @State private var original: EventDraft?
    @State private var details: EventDetails?
    @State private var detailsRead = false
    @AppStorage("dernierAgenda") private var lastAccount = ""
    @Environment(\.dismiss) private var dismiss

    init(agenda: AgendaLibrary, request: EditorRequest) {
        self.agenda = agenda
        editing = request.event
        if let event = request.event {
            _draft = State(initialValue: EventDraft(event: event, notes: ""))
            _account = State(initialValue: event.account)
        } else {
            // Réglages › Calendrier: the calendar, the length and the Meet of new events (14/11).
            let settings = Preferences()
            let start = request.start ?? EventEditor.nextSlot(after: Date())
            var draft = EventDraft.new(at: start)
            draft.end = start.addingTimeInterval(TimeInterval(settings.eventMinutes * 60))
            draft.addMeet = settings.eventMeet
            _draft = State(initialValue: draft)
            let remembered = UserDefaults.standard.string(forKey: "dernierAgenda") ?? ""
            let accounts = agenda.accounts.map(\.email)
            // A work account: by its state, never by its label « Perso » (lot 10, 20/11).
            let work = accounts.first { !AccountStyle.isPersonal($0) }
            let chosen = settings.defaultAccount.flatMap { accounts.contains($0) ? $0 : nil }
            _account = State(initialValue: chosen ?? (accounts.contains(remembered) ? remembered : (work ?? accounts.first ?? "")))
        }
    }

    /// The next half hour.
    static func nextSlot(after date: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minute = calendar.date(from: parts) ?? date
        let minutes = parts.minute ?? 0
        return calendar.date(byAdding: .minute, value: minutes < 30 ? 30 - minutes : 60 - minutes, to: minute) ?? date
    }

    private var color: Color { agenda.color(for: account) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Titre", text: $draft.title, prompt: Text("Nouveau rendez-vous"))
                        .font(.title2.weight(.semibold))
                        .textFieldStyle(.plain)
                        .labelsHidden()
                    if editing == nil {
                        Picker("Agenda", selection: $account) {
                            ForEach(agenda.accounts) { account in
                                Text("\(AccountStyle.label(for: account.email)) · \(account.email)").tag(account.email)
                            }
                        }
                    } else {
                        LabeledContent("Agenda") {
                            HStack(spacing: Space.s) {
                                ColorDot(color)
                                Text(AccountStyle.label(for: account))
                            }
                        }
                    }
                }
                Section {
                    Toggle("Toute la journée", isOn: $draft.allDay)
                        // Back to a time: an hour from 9:00 that day, not 00:00–00:00 (review of 14/11).
                        .onChange(of: draft.allDay) { _, allDay in
                            guard !allDay else { return }
                            let day = Calendar.current.startOfDay(for: draft.start)
                            draft.start = Calendar.current.date(byAdding: .hour, value: 9, to: day) ?? draft.start
                            draft.end = Calendar.current.date(byAdding: .hour, value: 10, to: day) ?? draft.end
                        }
                    DatePicker("Début", selection: Binding(get: { draft.start }, set: { moveStart(to: $0) }),
                               displayedComponents: draft.allDay ? [.date] : [.date, .hourAndMinute])
                    DatePicker("Fin", selection: $draft.end, in: draft.start..., displayedComponents: draft.allDay ? [.date] : [.date, .hourAndMinute])
                }
                Section {
                    if editing?.meetCode != nil {
                        LabeledContent("Visio") { Label("Google Meet", systemImage: "video.fill").foregroundStyle(.secondary) }
                    } else {
                        Toggle("Visio Google Meet", isOn: $draft.addMeet)
                    }
                    TextField("Lieu", text: $draft.location, prompt: Text("Adresse ou salle"))
                }
                Section("Invités") {
                    ForEach(draft.guests, id: \.self) { email in
                        HStack(spacing: Space.s) {
                            let contact = agenda.contact(email: email)
                            PersonAvatar(initials: contact?.initials.nonEmpty ?? String(email.prefix(1)).uppercased(), tint: MailText.tint(for: email),
                                         badge: contact == nil ? .none : .contact, size: 28)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(contact?.name ?? email)
                                if contact != nil { Text(email).font(.meta).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            // A verb and its object, for the bubble and VoiceOver (lot 10, 20/11).
                            IconButton("xmark.circle.fill", help: "Retirer \(contact?.name ?? email)") { draft.guests.removeAll { $0 == email } }
                        }
                    }
                    let matches = suggestions
                    TextField("Ajouter un invité", text: $guestQuery, prompt: Text("Nom ou adresse"))
                        .focused($guestFocused)
                        .onSubmit(addTypedGuest)
                        .suggestionKeys(count: matches.count, highlighted: $highlighted, moved: $moved, dismissed: $dismissed, accept: addTypedGuest)
                        .onChange(of: guestQuery) { _, _ in
                            highlighted = 0
                            moved = false
                            dismissed = false
                        }
                    if !matches.isEmpty {
                        PersonSuggestionList(matches: matches, highlighted: $highlighted, project: project(of:), glass: false) { add($0.address.email) }
                    }
                }
                Section("Notes") {
                    TextEditor(text: $draft.notes).frame(minHeight: 70).font(.body)
                }
            }
            .formStyle(.grouped)
            footer
        }
        .interactiveDismissDisabled(saving)
        .frame(width: 520, height: 680)
        .windowTitle(editing == nil ? "Nouveau rendez-vous" : "Modifier le rendez-vous")
        .task {
            guard let editing else { return }
            details = await agenda.details(of: editing)
            let base = EventDraft(event: editing, notes: details?.notes ?? "")
            original = base
            if draft.notes.isEmpty { draft.notes = base.notes }
            detailsRead = true
        }
        .confirmationDialog("Supprimer « \(draft.title) » ?", isPresented: $confirmingDelete) {
            Button("Supprimer", role: .destructive) { remove() }
        } message: {
            Text(draft.guests.isEmpty ? "Le rendez-vous disparaît de ton agenda Google." : "Google prévient les invités.")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            // A failure: said by `ErrorLine` (design system v2, 19/11), in hub's words (lot 10, 20/11).
            if let failure {
                ErrorLine(failure)
                    .fixedSize(horizontal: false, vertical: true)
            } else if editing?.recurringEventID != nil {
                Label(Words.typeset("Ce rendez-vous fait partie d'une série : seul celui-ci change."), systemImage: "repeat")
                    .font(.tag).foregroundStyle(.secondary)
            } else if editing != nil, detailsRead, details == nil {
                Label(Words.typeset("Google n'a pas pu être lu : la description et les invités ne changent que si tu les modifies."),
                      systemImage: "info.circle")
                    .font(.tag).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if editing != nil {
                    Button("Supprimer…", role: .destructive) { confirmingDelete = true }.disabled(saving)
                }
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("Annuler", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                // The principal action, at the app's accent whatever the calendar (design system v2, 19/11).
                Button(editing == nil ? "Créer" : "Enregistrer", action: save)
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || (editing == nil && draft.title.trimmingCharacters(in: .whitespaces).isEmpty) || account.isEmpty
                              || (editing != nil && !detailsRead))
            }
        }
        .padding(Space.l)
    }

    /// The people of the mails' suggestions (15/11): contacts, people Paul wrote to, people who wrote to him;
    /// without the mails, the contacts.
    private var suggestions: [PersonSuggestion] {
        guard guestFocused, !dismissed else { return [] }
        let index = agenda.mails?.people.current
            ?? PeopleIndex(contacts: agenda.contacts, projects: agenda.projectsByEmail, mine: Set(agenda.accounts.map(\.email)))
        return index.search(guestQuery, excluding: Set(draft.guests))
    }

    private func project(of person: PersonSuggestion) -> ProjectRow? {
        agenda.projects.filter { person.projectIDs.contains($0.id) && $0.status != .termine }
            .min { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// ↩ or ⇥: the suggestion lit, else the address typed in full.
    private func addTypedGuest() {
        let query = guestQuery.trimmingCharacters(in: .whitespaces)
        if let chosen = SuggestionChoice.accepted(typed: query, matches: suggestions, highlighted: highlighted, moved: moved) {
            add(chosen.email)
        } else if query.contains("@"), query.contains(".") {
            add(query)
        }
    }

    private func add(_ email: String) {
        let email = email.lowercased()
        guard !email.isEmpty, !draft.guests.contains(email) else { return }
        draft.guests.append(email)
        guestQuery = ""
    }

    /// The guests to send: those chosen, and what is typed and not yet taken when it is an address (« Nom <adresse> »
    /// too), as the mails' composer does (`ComposeBar.commitPending`); `nil` when what is typed is no address (audit of 19/11).
    static func guests(_ chosen: [String], pending: String) -> [String]? {
        let typed = RecipientField.parse(pending).map { $0.email.lowercased() }
        guard typed.allSatisfy(MIMEBuilder.isValid) else { return nil }
        return typed.reduce(into: chosen) { all, email in if !all.contains(email) { all.append(email) } }
    }

    /// Moving the start moves the end with it, as in Google.
    private func moveStart(to start: Date) {
        let length = draft.end.timeIntervalSince(draft.start)
        draft.start = start
        draft.end = start.addingTimeInterval(max(0, length))
    }

    private func save() {
        failure = nil
        // What is typed and not yet taken goes with the event when it is an address; anything else stops « Créer »
        // (audit of 19/11). What did not work, then what to do, as every problem (lot 10, 20/11).
        guard let guests = Self.guests(draft.guests, pending: guestQuery) else {
            failure = Words.problem("L'adresse « \(guestQuery.trimmingCharacters(in: .whitespaces)) » n'est pas valide",
                                    remedy: "Choisis l'invité dans la liste, ou efface-le.").sentence
            return
        }
        var sent = draft
        sent.guests = guests
        draft.guests = guests
        guestQuery = ""
        saving = true
        Task {
            defer { saving = false }
            do {
                try await agenda.save(sent, account: account, editing: editing, original: original, details: details)
                if editing == nil { lastAccount = account }
                dismiss()
            } catch {
                // hub's sentence on screen, the system's text in the journal (lot 10, 20/11).
                let problem = Words.problem(editing == nil ? "Le rendez-vous n'a pas pu être créé" : "Le rendez-vous n'a pas pu être enregistré",
                                            error)
                failure = problem.sentence
                agenda.database.journal(problem)
            }
        }
    }

    private func remove() {
        guard let editing else { return }
        saving = true
        Task {
            defer { saving = false }
            do {
                try await agenda.delete(editing)
                dismiss()
            } catch {
                // hub's sentence on screen, the system's text in the journal (lot 10, 20/11).
                let problem = Words.problem("Le rendez-vous n'a pas pu être supprimé", error)
                failure = problem.sentence
                agenda.database.journal(problem)
            }
        }
    }
}
