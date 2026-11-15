import Agenda
import Domain
import Persistence
import PolhubDesign
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
    @State private var saving = false
    @State private var failure: GoogleError?
    @State private var otherFailure: String?
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
            let work = accounts.first { AccountStyle.label(for: $0) != "Perso" }
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
                            Avatar(contact?.initials ?? String(email.prefix(1)).uppercased(), size: 24)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(contact?.name ?? email)
                                if contact != nil { Text(email).font(.tag).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button { draft.guests.removeAll { $0 == email } } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary).help("Retirer")
                        }
                    }
                    TextField("Ajouter un invité", text: $guestQuery, prompt: Text("Nom ou adresse"))
                        .onSubmit(addTypedGuest)
                    ForEach(suggestions) { contact in
                        Button {
                            add(contact.email ?? "")
                        } label: {
                            HStack(spacing: Space.s) {
                                Avatar(contact.initials, size: 22)
                                Text(contact.name)
                                Text(contact.email ?? "").foregroundStyle(.secondary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
            if let failure {
                HStack(spacing: Space.s) {
                    Label(failure.description, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let otherFailure {
                Label(otherFailure, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            } else if editing?.recurringEventID != nil {
                Label("Ce rendez-vous fait partie d'une série : seul celui-ci change.", systemImage: "repeat")
                    .font(.tag).foregroundStyle(.secondary)
            } else if editing != nil, detailsRead, details == nil {
                Label("Google n'a pas pu être lu : la description et les invités ne changent que si tu les modifies.", systemImage: "info.circle")
                    .font(.tag).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if editing != nil {
                    Button("Supprimer…", role: .destructive) { confirmingDelete = true }.disabled(saving)
                }
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("Annuler", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                Button(editing == nil ? "Créer" : "Enregistrer", action: save)
                    .buttonStyle(.glassProminent)
                    .tint(color)
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || (editing == nil && draft.title.trimmingCharacters(in: .whitespaces).isEmpty) || account.isEmpty
                              || (editing != nil && !detailsRead))
            }
        }
        .padding(Space.l)
    }

    private var suggestions: [ContactRow] {
        let query = guestQuery.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { return [] }
        return agenda.contacts.filter { contact in
            guard let email = contact.email, !draft.guests.contains(email) else { return false }
            return [contact.name, email, contact.company ?? ""].contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        .prefix(5).map { $0 }
    }

    private func addTypedGuest() {
        let query = guestQuery.trimmingCharacters(in: .whitespaces)
        if query.contains("@"), query.contains(".") {
            add(query)
        } else if suggestions.count == 1, let email = suggestions.first?.email {
            add(email)
        }
    }

    private func add(_ email: String) {
        let email = email.lowercased()
        guard !email.isEmpty, !draft.guests.contains(email) else { return }
        draft.guests.append(email)
        guestQuery = ""
    }

    /// Moving the start moves the end with it, as in Google.
    private func moveStart(to start: Date) {
        let length = draft.end.timeIntervalSince(draft.start)
        draft.start = start
        draft.end = start.addingTimeInterval(max(0, length))
    }

    private func save() {
        saving = true
        failure = nil
        otherFailure = nil
        Task {
            defer { saving = false }
            do {
                try await agenda.save(draft, account: account, editing: editing, original: original, details: details)
                if editing == nil { lastAccount = account }
                dismiss()
            } catch let error as GoogleError {
                failure = error
            } catch {
                otherFailure = "\(error.localizedDescription)"
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
            } catch let error as GoogleError {
                failure = error
            } catch {
                otherFailure = "\(error.localizedDescription)"
            }
        }
    }
}
