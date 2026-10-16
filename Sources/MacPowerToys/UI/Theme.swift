import AppKit
import SwiftUI

/// Design tokens for the app's glass surfaces.
///
/// ponytail: the *idiom* (translucent surface + hairline border + rim highlight)
/// is inspired by the reference app the user pointed at; every value here is
/// self-authored — that project is GPL and no code was copied from it.
enum Theme {
    enum Radius {
        static let panel: CGFloat = 12
        static let row: CGFloat = 8
        static let chip: CGFloat = 6
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 6
        static let m: CGFloat = 9
        static let l: CGFloat = 12
    }

    static let accent = Color.accentColor

    // MARK: - Surfaces

    static func baseFill(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.72) : Color.black.opacity(0.45)
    }

    static func cardFill(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.45) : Color.white.opacity(0.08)
    }

    static func hoverFill(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.07) : Color.white.opacity(0.11)
    }

    static func selectedFill(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.11) : Color.white.opacity(0.17)
    }

    /// Hairline that separates one card from the next. Raised contrast is a
    /// real setting, so a user who asks for it gets a visible line.
    static func border(_ scheme: ColorScheme) -> Color {
        let raised = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        return scheme == .light
            ? Color.black.opacity(raised ? 0.24 : 0.10)
            : Color.white.opacity(raised ? 0.30 : 0.13)
    }

    /// The lit top edge: without it a translucent panel reads as paper.
    static var rimHighlight: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.28), Color.white.opacity(0.03)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static let shadowColor = Color.black.opacity(0.34)
    static let shadowRadius: CGFloat = 16
    static let shadowY: CGFloat = 6

    // MARK: - Type

    static func title(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .semibold)
    }

    static func body(_ size: CGFloat = 13) -> Font {
        .system(size: size)
    }

    static func caption(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .medium)
    }

    static func mono(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}
