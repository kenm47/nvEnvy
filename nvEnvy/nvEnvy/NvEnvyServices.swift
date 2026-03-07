import AppKit

class NvEnvyServices: NSObject {
    weak var appState: AppState?

    @objc func createFromSelection(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        var text: String?

        if let html = pboard.string(forType: .html) {
            // Strip HTML tags for plain text body
            if let data = html.data(using: .utf8),
               let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {
                text = attributed.string
            }
        } else if let rtf = pboard.data(forType: .rtf) {
            if let attributed = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                text = attributed.string
            }
        }

        if text == nil {
            text = pboard.string(forType: .string)
        }

        guard let body = text, !body.isEmpty else { return }

        let title = String(body.prefix(60)).components(separatedBy: .newlines).first ?? "Imported Note"

        DispatchQueue.main.async { [weak self] in
            self?.appState?.createNoteFromIntent(title: title, body: body, tags: [])
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
