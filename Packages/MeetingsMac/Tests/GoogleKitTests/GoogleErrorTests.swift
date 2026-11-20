import Foundation
import Testing
@testable import GoogleKit

/// Lot 10 (20/11): what an account's kept error is, read by `GoogleError` from its own words, never by the first words of
/// the text elsewhere; and which errors Paul must act on.
@Suite struct GoogleErrorTests {
    static let all: [GoogleError] = [.noKey, .badKey, .refused("invalid_grant"), .refused("admin_policy_enforced"), .refused("access_denied"),
                                     .badAnswer, .expired, .http(503), .timeout, .needsWrite, .notOrganizer, .missingScope(.gmailModify),
                                     .missingScope(.calendarEvents), .rateLimited, .notFound, .readOnlyBuild]

    @Test func aKeptTextSaysItsErrorAgain() {
        for error in Self.all {
            #expect(GoogleError(stored: error.description) == error, "\(error)")
        }
        #expect(GoogleError(stored: "Error Domain=NSURLErrorDomain Code=-1009 \"(null)\"") == nil)
        #expect(GoogleError(stored: "") == nil)
    }

    @Test func whatMustBeReconnected() {
        #expect(GoogleError.expired.needsReconnecting && GoogleError.needsWrite.needsReconnecting)
        #expect(GoogleError.refused("admin_policy_enforced").needsReconnecting && GoogleError.refused("invalid_grant").needsReconnecting)
        #expect(GoogleError.missingScope(.gmailModify).needsReconnecting && GoogleError.missingScope(.calendarEvents).needsReconnecting)
        #expect(!GoogleError.timeout.needsReconnecting && !GoogleError.http(503).needsReconnecting && !GoogleError.rateLimited.needsReconnecting)
    }
}
