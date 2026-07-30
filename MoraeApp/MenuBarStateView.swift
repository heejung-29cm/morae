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

    @ViewBuilder
    var body: some View {
        if kind == .empty {
            compactEmptyState
        } else {
            feedbackState
        }
    }

    private var compactEmptyState: some View {
        HStack(spacing: MoraeSpacing.small) {
            Circle()
                .fill(MoraeColor.mutedForeground)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(MoraeColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MoraeSpacing.regular)
        .padding(.vertical, 11)
        .background(
            MoraeColor.subtleFill,
            in: RoundedRectangle(cornerRadius: MoraeRadius.medium)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MoraeRadius.medium)
                .stroke(
                    MoraeColor.controlBorder,
                    style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var feedbackState: some View {
        HStack(alignment: .top, spacing: MoraeSpacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(
                    tint.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: MoraeRadius.control)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(MoraeColor.foreground)
                }
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(MoraeColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let recovery {
                    Text(recovery)
                        .font(.system(size: 11.5))
                        .foregroundStyle(MoraeColor.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MoraeSpacing.regular)
        .background(
            background,
            in: RoundedRectangle(cornerRadius: MoraeRadius.medium)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MoraeRadius.medium)
                .stroke(tint.opacity(0.18), lineWidth: 0.5)
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
