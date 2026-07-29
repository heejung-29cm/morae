import SwiftUI

enum MenuBarStateKind: Equatable, Sendable {
    case empty
    case validation
    case error

    var defaultSystemImage: String {
        switch self {
        case .empty: "tray"
        case .validation: "exclamationmark.circle"
        case .error: "exclamationmark.triangle"
        }
    }

    var accessibilityPrefix: String {
        switch self {
        case .empty: "빈 상태"
        case .validation: "입력 오류"
        case .error: "오류"
        }
    }
}

struct MenuBarStateView: View {
    let kind: MenuBarStateKind
    let title: String?
    let message: String
    let recovery: String?
    let systemImage: String

    init(
        kind: MenuBarStateKind,
        title: String? = nil,
        message: String,
        recovery: String? = nil,
        systemImage: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.recovery = recovery
        self.systemImage = systemImage ?? kind.defaultSystemImage
    }

    var body: some View {
        HStack(alignment: .top, spacing: MoraeSpacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    tint.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: MoraeRadius.medium)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MoraeColor.foreground)
                }
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(
                        kind == .empty
                            ? MoraeColor.secondaryForeground
                            : MoraeColor.foreground
                    )
                    .fixedSize(horizontal: false, vertical: true)
                if let recovery {
                    Text(recovery)
                        .font(.caption)
                        .foregroundStyle(MoraeColor.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MoraeSpacing.medium)
        .background(
            background,
            in: RoundedRectangle(cornerRadius: MoraeRadius.large)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MoraeRadius.large)
                .stroke(tint.opacity(kind == .empty ? 0.08 : 0.18))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var tint: Color {
        switch kind {
        case .empty: MoraeColor.secondaryForeground
        case .validation: .orange
        case .error: MoraeColor.error
        }
    }

    private var background: Color {
        switch kind {
        case .empty: MoraeColor.subtleFill
        case .validation: Color.orange.opacity(0.065)
        case .error: MoraeColor.error.opacity(0.065)
        }
    }

    private var accessibilityText: String {
        [
            kind.accessibilityPrefix,
            title,
            message,
            recovery,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}
