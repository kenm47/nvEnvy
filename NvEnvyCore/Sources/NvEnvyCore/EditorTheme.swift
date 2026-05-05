import Foundation

/// Platform-agnostic RGBA color. App layer adapts this to `NSColor` / `UIColor`.
public struct RGBAColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
}

/// Platform-agnostic editor font selector. App layer resolves to `NSFont` / `UIFont`.
///
/// `dynamicType` binds to `UIFont.preferredFont(forTextStyle: .body)` on iOS so
/// the editor scales with the user's content-size category. macOS resolves it to
/// the system font at default body size (Dynamic Type is iOS-only).
public enum EditorFontDescriptor: Codable, Hashable, Sendable {
    case systemMonospaced(size: Double)
    case named(postScriptName: String, size: Double)
    case dynamicType

    public static let `default` = EditorFontDescriptor.systemMonospaced(size: 14)
}
