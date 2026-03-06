import Foundation

public struct URLSchemeAction: Sendable {
    public enum Kind: Sendable {
        case find(searchTerm: String, noteID: UUID?)
        case make(title: String?, body: String?, tags: [String])
    }
    public let kind: Kind
}

public enum URLSchemeHandler {

    public static func parse(_ url: URL) -> URLSchemeAction? {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "nvenvy" || scheme == "nv" else { return nil }

        let host = url.host?.lowercased() ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        func queryValue(_ name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }

        switch host {
        case "find":
            let searchTerm = url.path
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .removingPercentEncoding ?? ""

            var noteID: UUID?
            if let idStr = queryValue("id"),
               let data = Data(base64Encoded: idStr),
               let uuidStr = String(data: data, encoding: .utf8) {
                noteID = UUID(uuidString: uuidStr)
            }

            guard !searchTerm.isEmpty || noteID != nil else { return nil }
            return URLSchemeAction(kind: .find(searchTerm: searchTerm, noteID: noteID))

        case "make":
            let title = queryValue("title")
            let body = queryValue("txt")
            let tags = queryValue("tags")?.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty } ?? []

            return URLSchemeAction(kind: .make(title: title, body: body, tags: tags))

        default:
            return nil
        }
    }
}
