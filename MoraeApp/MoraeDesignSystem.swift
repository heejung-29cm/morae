import SwiftUI

enum MoraeColor {
    static let accent = Color("MoraeAccent")
    static let foreground = Color.primary
    static let secondaryForeground = Color.secondary
    static let subtleFill = Color.primary.opacity(0.055)
    static let selectedFill = accent.opacity(0.12)
    static let separator = Color.primary.opacity(0.10)
    static let error = Color.red
}

enum MoraeSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let section: CGFloat = 18
}

enum MoraeRadius {
    static let small: CGFloat = 6
    static let medium: CGFloat = 9
    static let large: CGFloat = 12
}
