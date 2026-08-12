import SwiftUI

enum MoraeColor {
    static let accent = Color("MoraeAccent")
    static let onAccent = Color("MoraeOnAccent")
    static let foreground = Color.primary
    static let secondaryForeground = Color.secondary
    static let mutedForeground = Color.secondary.opacity(0.78)
    static let subtleFill = Color.primary.opacity(0.04)
    static let selectedFill = accent.opacity(0.12)
    static let chipFill = Color.primary.opacity(0.055)
    static let controlFill = Color(nsColor: .controlBackgroundColor)
    static let controlBorder = Color.primary.opacity(0.12)
    static let separator = Color.primary.opacity(0.11)
    static let error = Color.red
}

enum MoraeSpacing {
    static let xSmall: CGFloat = 4
    static let compact: CGFloat = 6
    static let small: CGFloat = 8
    static let regular: CGFloat = 10
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let section: CGFloat = 18
}

enum MoraeRadius {
    static let small: CGFloat = 6
    static let control: CGFloat = 8
    static let medium: CGFloat = 9
    static let large: CGFloat = 12
}

enum MoraeControlMetrics {
    static let inputHeight: CGFloat = 30
    static let buttonHeight: CGFloat = 28
    static let headerIconButtonSize: CGFloat = 28
    static let rowIconButtonSize: CGFloat = 24
}

struct MoraeInputModifier: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .padding(.horizontal, MoraeSpacing.regular)
            .frame(height: MoraeControlMetrics.inputHeight)
            .background(
                MoraeColor.controlFill,
                in: RoundedRectangle(cornerRadius: MoraeRadius.control)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MoraeRadius.control)
                    .stroke(
                        isFocused
                            ? MoraeColor.accent
                            : MoraeColor.controlBorder,
                        lineWidth: isFocused ? 1 : 0.5
                    )
            }
            .shadow(
                color: isFocused ? MoraeColor.accent.opacity(0.18) : .clear,
                radius: isFocused ? 3 : 0,
                x: 0,
                y: 0
            )
    }
}

enum MoraeButtonVariant: Equatable {
    case chip
    case prominent
}

struct MoraeCompactButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let variant: MoraeButtonVariant
    var foreground: Color?
    var horizontalPadding: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foreground ?? labelColor)
            .padding(.horizontal, horizontalPadding)
            .frame(height: MoraeControlMetrics.buttonHeight)
            .background(
                backgroundColor(configuration: configuration),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay {
                if variant == .chip {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(MoraeColor.controlBorder, lineWidth: 0.5)
                }
            }
            .shadow(
                color: variant == .prominent
                    ? Color.black.opacity(0.16)
                    : .clear,
                radius: variant == .prominent ? 2 : 0,
                x: 0,
                y: variant == .prominent ? 1 : 0
            )
            .opacity(isEnabled ? 1 : 0.46)
    }

    private var labelColor: Color {
        switch variant {
        case .chip: MoraeColor.secondaryForeground
        case .prominent: MoraeColor.onAccent
        }
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        switch variant {
        case .chip:
            configuration.isPressed
                ? MoraeColor.chipFill.opacity(1.6)
                : MoraeColor.chipFill
        case .prominent:
            configuration.isPressed
                ? MoraeColor.accent.opacity(0.82)
                : MoraeColor.accent
        }
    }
}

struct MoraeIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let size: CGFloat
    var foreground: Color = MoraeColor.secondaryForeground
    var showsBackground = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size == MoraeControlMetrics.rowIconButtonSize ? 12 : 14))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(
                showsBackground
                    ? (
                        configuration.isPressed
                            ? MoraeColor.chipFill.opacity(1.6)
                            : MoraeColor.chipFill
                    )
                    : .clear,
                in: RoundedRectangle(
                    cornerRadius: {
                        if size == MoraeControlMetrics.rowIconButtonSize {
                            return MoraeRadius.small
                        }
                        if size == MoraeControlMetrics.inputHeight {
                            return MoraeRadius.control
                        }
                        return 7
                    }()
                )
            )
            .opacity(isEnabled ? 1 : 0.42)
            .contentShape(Rectangle())
    }
}

struct MoraeAccentIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var size: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MoraeColor.accent)
            .frame(width: size, height: size)
            .background(
                configuration.isPressed
                    ? MoraeColor.accent.opacity(0.18)
                    : MoraeColor.selectedFill,
                in: RoundedRectangle(cornerRadius: MoraeRadius.small)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MoraeRadius.small)
                    .stroke(
                        MoraeColor.accent.opacity(
                            configuration.isPressed ? 0.26 : 0.14
                        ),
                        lineWidth: 0.5
                    )
            }
            .opacity(isEnabled ? 1 : 0.50)
            .contentShape(Rectangle())
    }
}

extension View {
    func moraeInput(isFocused: Bool) -> some View {
        modifier(MoraeInputModifier(isFocused: isFocused))
    }
}
