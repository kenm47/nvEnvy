import UIKit
import NvEnvyCore

enum FontResolver {
    static func resolve(_ descriptor: EditorFontDescriptor) -> UIFont {
        switch descriptor {
        case .dynamicType:
            return .preferredFont(forTextStyle: .body)
        case .systemMonospaced(let size):
            let base = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
            return UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
        case .named(let postScriptName, let size):
            guard let base = UIFont(name: postScriptName, size: size) else {
                return .preferredFont(forTextStyle: .body)
            }
            return UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
        }
    }
}
