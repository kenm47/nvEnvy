import Foundation

/// Shared date format styles for note list rows. Centralized so macOS and iOS
/// don't drift, and so `Note.cachedModifiedString` can be computed once
/// per-note instead of once per-row-render.
public let rowModifiedDateStyle = Date.FormatStyle(date: .abbreviated, time: .shortened)
public let rowRelativeDateStyle = Date.RelativeFormatStyle(presentation: .named)
