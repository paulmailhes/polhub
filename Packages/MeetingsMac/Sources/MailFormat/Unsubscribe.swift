import Foundation

/// How to leave a mailing list, from the headers the sender put on its mails (RFC 2369 and RFC 8058, 14/11).
public enum UnsubscribeMethod: Equatable, Sendable {
    /// One click: a POST the sender's server expects, nothing to fill in. Only for a mail Gmail authenticated.
    case oneClick(URL)
    /// A mail to send: Polhub prepares it, Paul sends it himself.
    case mail(to: String, subject: String?)
    /// The sender's page, opened in the browser.
    case page(URL)

    /// The domain the request goes to, shown before Paul confirms.
    public var domain: String {
        switch self {
        case .oneClick(let url), .page(let url): url.host() ?? url.absoluteString
        case .mail(let to, _): to.split(separator: "@").last.map(String.init) ?? to
        }
    }

    /// The best way the headers offer: one click (authenticated mail, https only), then a mail, then the page.
    /// Never a plain http address; never a link found in the body.
    public static func from(listUnsubscribe: String?, post: String?, authenticated: Bool) -> UnsubscribeMethod? {
        guard let header = listUnsubscribe else { return nil }
        let targets = header.components(separatedBy: ",").compactMap { piece -> String? in
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">") else { return nil }
            return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        let https = targets.compactMap(URL.init(string:)).first { $0.scheme?.lowercased() == "https" && $0.host() != nil }
        let oneClick = post?.replacingOccurrences(of: " ", with: "").lowercased() == "list-unsubscribe=one-click"
        if let https, oneClick, authenticated { return .oneClick(https) }
        if let mailto = targets.first(where: { $0.lowercased().hasPrefix("mailto:") }),
           let components = URLComponents(string: mailto), !components.path.isEmpty, components.path.contains("@") {
            let subject = components.queryItems?.first { $0.name.lowercased() == "subject" }?.value
            return .mail(to: components.path, subject: subject)
        }
        if let https { return .page(https) }
        return nil
    }

    /// RFC 8058: `List-Unsubscribe=One-Click` posted as a form, with no cookie and no credential.
    public static func oneClickRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("List-Unsubscribe=One-Click".utf8)
        return request
    }
}
