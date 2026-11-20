import Foundation
import Testing
@testable import HubLink

/// 20/11 : les notifications de l'iPhone passent chiffrées par Apple ; seul l'iPhone, qui a fait la clé, les lit.
@Suite struct PushSealTests {
    @Test func whatIsSealedOpensWithTheSameKey() throws {
        let key = PushSeal.newKey()
        let content = PushContent(title: "Camille Martin", subtitle: "Devis du site", body: "Bonjour, voici le devis")
        let sealed = try PushSeal.seal(content, key: key)
        #expect(!sealed.contains("Camille") && !sealed.contains("Devis"))
        #expect(PushSeal.open(sealed, key: key) == content)
    }

    @Test func anotherKeyOrABadKeyOpensNothing() throws {
        let sealed = try PushSeal.seal(PushContent(title: "a", subtitle: nil, body: "b"), key: PushSeal.newKey())
        #expect(PushSeal.open(sealed, key: PushSeal.newKey()) == nil)
        #expect(PushSeal.open(sealed, key: "pas une clé") == nil)
        #expect(!PushSeal.isKey("pas une clé") && PushSeal.isKey(PushSeal.newKey()))
    }

    @Test func thePushTokenCarriesTheKey() throws {
        let given = LinkPushToken(token: "abc", name: "iPhone", key: "clé")
        let read = try LinkAPI.decoder.decode(LinkPushToken.self, from: LinkAPI.encoder.encode(given))
        #expect(read.key == "clé")
    }
}
