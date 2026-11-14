import Foundation
import Testing
@testable import MailFormat

/// 14/11: « Se désabonner » takes the sender's own headers, never a link in the body.
@Suite struct UnsubscribeTests {
    @Test func oneClickOnlyForAnAuthenticatedMailOverHTTPS() {
        let header = "<mailto:stop@liste.exemple?subject=desinscription>, <https://liste.exemple/stop?id=42>"
        #expect(UnsubscribeMethod.from(listUnsubscribe: header, post: "List-Unsubscribe=One-Click", authenticated: true)
            == .oneClick(URL(string: "https://liste.exemple/stop?id=42")!))
        // Not authenticated by Gmail: no POST in the background, a mail Paul sends himself instead.
        #expect(UnsubscribeMethod.from(listUnsubscribe: header, post: "List-Unsubscribe=One-Click", authenticated: false)
            == .mail(to: "stop@liste.exemple", subject: "desinscription"))
        // No one-click header: the mail, then the page.
        #expect(UnsubscribeMethod.from(listUnsubscribe: "<https://liste.exemple/stop>", post: nil, authenticated: true)
            == .page(URL(string: "https://liste.exemple/stop")!))
    }

    @Test func plainHTTPAndOddHeadersAreRefused() {
        #expect(UnsubscribeMethod.from(listUnsubscribe: "<http://liste.exemple/stop>", post: "List-Unsubscribe=One-Click", authenticated: true) == nil)
        #expect(UnsubscribeMethod.from(listUnsubscribe: "https://sans-chevrons.exemple", post: nil, authenticated: true) == nil)
        #expect(UnsubscribeMethod.from(listUnsubscribe: "<javascript:alert(1)>", post: nil, authenticated: true) == nil)
        #expect(UnsubscribeMethod.from(listUnsubscribe: nil, post: nil, authenticated: true) == nil)
        #expect(UnsubscribeMethod.oneClick(URL(string: "https://liste.exemple/stop")!).domain == "liste.exemple")
        #expect(UnsubscribeMethod.mail(to: "stop@liste.exemple", subject: nil).domain == "liste.exemple")
    }

    @Test func theOneClickRequestCarriesNothingOfPauls() {
        let request = UnsubscribeMethod.oneClickRequest(URL(string: "https://liste.exemple/stop")!)
        #expect(request.httpMethod == "POST" && !request.httpShouldHandleCookies)
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self) == "List-Unsubscribe=One-Click")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }
}
