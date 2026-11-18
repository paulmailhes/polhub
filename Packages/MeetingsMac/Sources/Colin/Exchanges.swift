import Foundation
import Persistence

/// Who wrote to whom, and when (18/11), across the threads and the mailboxes. A rule that reads thread by thread
/// speaks far too much: Paul answers a client in a new mail (a recap, « tes retours sont intégrés ») more often than
/// in the thread, and his clients send their files and their questions in new threads too. Who owes an answer is
/// read from the exchange with a person, or with a project.
public struct Exchanges: Sendable {
    /// When Paul wrote to each address (To or Cc), the oldest first.
    private var sent: [String: [Date]] = [:]
    /// When each address wrote to Paul, the oldest first: what a person wrote, never an absent mailbox's answer
    /// nor a calendar's mail sent from their address.
    private var received: [String: [Date]] = [:]
    /// The same by project, for the threads that have one.
    private var sentIn: [UUID: [Date]] = [:]
    private var receivedIn: [UUID: [Date]] = [:]
    /// The messages of each thread, the oldest first: those received, those of Paul.
    private var incoming: [String: [MailExchange]] = [:]
    private var outgoing: [String: [MailExchange]] = [:]

    /// `messages`: what `MailStore.exchanges(since:)` gave, in any order. `projects`: the project of each thread that
    /// has one, by thread key.
    public init(_ messages: [MailExchange], projects: [String: UUID] = [:]) {
        for message in messages.sorted(by: { $0.date < $1.date }) {
            let project = projects[message.threadKey]
            if message.mine {
                outgoing[message.threadKey, default: []].append(message)
                for address in Set(message.recipients.map { $0.lowercased() }) { sent[address, default: []].append(message.date) }
                if let project { sentIn[project, default: []].append(message.date) }
            } else {
                incoming[message.threadKey, default: []].append(message)
                // Nobody wrote it: it says nothing of the exchange.
                guard !message.automatic, !message.calendar else { continue }
                if let sender = message.sender?.lowercased() { received[sender, default: []].append(message.date) }
                if let project { receivedIn[project, default: []].append(message.date) }
            }
        }
    }

    /// Paul wrote to this address (To or Cc) after `date` and no later than `until`, in any thread of any mailbox.
    public func wrote(to address: String, after date: Date, until: Date = .distantFuture) -> Bool {
        Self.any(sent[address.lowercased()], after: date, until: until)
    }

    /// This address wrote to Paul after `date` and no later than `until`, in any thread of any mailbox.
    public func heard(from address: String, after date: Date, until: Date = .distantFuture) -> Bool {
        Self.any(received[address.lowercased()], after: date, until: until)
    }

    /// Paul wrote in a thread of this project after `date` and no later than `until`.
    public func wrote(in project: UUID, after date: Date, until: Date = .distantFuture) -> Bool {
        Self.any(sentIn[project], after: date, until: until)
    }

    /// Someone wrote to Paul in a thread of this project after `date` and no later than `until`.
    public func heard(in project: UUID, after date: Date, until: Date = .distantFuture) -> Bool {
        Self.any(receivedIn[project], after: date, until: until)
    }

    /// The last time this address wrote to Paul, in whatever thread, as it stood at `asOf`.
    public func lastHeard(from address: String, asOf: Date = .distantFuture) -> Date? {
        received[address.lowercased()]?.last { $0 <= asOf }
    }

    /// The last message a person wrote in this thread, as it stood at `asOf`: an absent mailbox's answer and a
    /// calendar's mail apart.
    public func lastWritten(in thread: String, asOf: Date = .distantFuture) -> MailExchange? {
        incoming[thread]?.last { $0.date <= asOf && !$0.automatic && !$0.calendar }
    }

    /// The last message received in this thread, as it stood at `asOf`.
    public func lastReceived(in thread: String, asOf: Date = .distantFuture) -> MailExchange? {
        incoming[thread]?.last { $0.date <= asOf }
    }

    /// Paul's last message in this thread, as it stood at `asOf`.
    public func lastSent(in thread: String, asOf: Date = .distantFuture) -> MailExchange? {
        outgoing[thread]?.last { $0.date <= asOf }
    }

    /// Whether one of these dates, the oldest first, is after `date` and no later than `until`: the first one after
    /// `date` is found by halves.
    private static func any(_ dates: [Date]?, after date: Date, until: Date) -> Bool {
        guard let dates, !dates.isEmpty else { return false }
        var low = 0, high = dates.count
        while low < high {
            let middle = (low + high) / 2
            if dates[middle] > date { high = middle } else { low = middle + 1 }
        }
        return low < dates.count && dates[low] <= until
    }
}
