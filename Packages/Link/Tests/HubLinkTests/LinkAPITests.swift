import Foundation
import Testing
@testable import HubLink

/// The language of the Mac and the iPhone (20/11). Every address here is invented.
@Suite struct LinkAPITests {
    @Test func aPairingLinkCarriesTheAddressAndTheToken() throws {
        let address = try #require(URL(string: "https://mac.exemple.ts.net:8443"))
        let link = LinkAPI.pairingURL(address: address, token: "abc-123_XYZ")
        #expect(link.scheme == "polhub" && link.host == "appairer")
        let read = try #require(LinkAPI.pairing(from: link))
        #expect(read.address == address && read.token == "abc-123_XYZ")
    }

    @Test func onlyAnHTTPSAddressPairs() throws {
        func link(_ address: String, token: String = "t") -> URL {
            LinkAPI.pairingURL(address: URL(string: address)!, token: token)
        }
        #expect(LinkAPI.pairing(from: link("http://mac.exemple.ts.net:8443")) == nil)
        #expect(LinkAPI.pairing(from: link("http://127.0.0.1:8790")) != nil)
        #expect(LinkAPI.pairing(from: link("https://mac.exemple.ts.net", token: "")) == nil)
        #expect(LinkAPI.pairing(from: try #require(URL(string: "https://exemple.fr/appairer?jeton=t"))) == nil)
    }

    @Test func theTokenIsReadFromItsHeader() {
        #expect(LinkAPI.token(fromAuthorization: LinkAPI.bearer("secret")) == "secret")
        #expect(LinkAPI.token(fromAuthorization: "Basic secret") == nil)
        #expect(LinkAPI.token(fromAuthorization: "Bearer ") == nil)
        #expect(LinkAPI.token(fromAuthorization: nil) == nil)
    }

    @Test func datesSurviveTheTrip() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000.25)
        let thread = LinkThread(id: "moi@exemple.fr|a", account: "moi@exemple.fr", subject: "Devis", people: "Camille, moi",
                                snippet: "Bonjour", date: date, unread: true, messages: 3, hasFiles: false, project: "Site vitrine")
        let data = try LinkAPI.encoder.encode(thread)
        #expect(try LinkAPI.decoder.decode(LinkThread.self, from: data) == thread)
    }

    @Test func aPersonShowsItsNameElseItsAddress() {
        #expect(LinkPerson(name: "Camille Martin", email: "camille@exemple.fr").shown == "Camille Martin")
        #expect(LinkPerson(name: "", email: "camille@exemple.fr").shown == "camille@exemple.fr")
        #expect(LinkPerson(name: nil, email: "camille@exemple.fr").shown == "camille@exemple.fr")
    }
}
