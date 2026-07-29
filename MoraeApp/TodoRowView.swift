import MoraeCore
import SwiftUI

struct TodoRowView: View {
    let item: TodoItem
    let canMoveUp: Bool
    let canMoveDown: Bool
    let dragIdentifier: String?
    let isDragging: Bool
    let showsDropIndicator: Bool
    let onToggleCompletion: () -> Void
    let onDragStarted: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: MoraeSpacing.small) {
            dragHandle
            completionButton
            titleAndMetadata
            Spacer(minLength: MoraeSpacing.xSmall)
            actionButtons
        }
        .padding(.horizontal, MoraeSpacing.small)
        .padding(.vertical, 7)
        .background(
            isHovered ? MoraeColor.subtleFill : .clear,
            in: RoundedRectangle(cornerRadius: MoraeRadius.medium)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .opacity(isDragging ? 0.46 : 1)
        .overlay(alignment: .top) {
            if showsDropIndicator {
                Capsule()
                    .fill(MoraeColor.accent)
                    .frame(height: 2)
                    .offset(y: -1)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if item.status == .pending, canMoveUp {
                Button("위로 이동", action: onMoveUp)
            }
            if item.status == .pending, canMoveDown {
                Button("아래로 이동", action: onMoveDown)
            }
            Button("편집", action: onEdit)
            Button("삭제", action: onDelete)
        }
    }

    @ViewBuilder
    private var dragHandle: some View {
        if let dragIdentifier {
            Image(systemName: "circle.grid.2x3.fill")
                .font(.system(size: 11))
                .foregroundStyle(MoraeColor.secondaryForeground)
                .frame(width: 16, height: 24)
                .contentShape(Rectangle())
                .onDrag {
                    onDragStarted()
                    return NSItemProvider(object: dragIdentifier as NSString)
                }
                .help("드래그하여 순서 변경")
                .accessibilityLabel("\(item.title) 순서 변경 핸들")
        }
    }

    private var completionButton: some View {
        Button(action: onToggleCompletion) {
            Image(
                systemName: item.status == .completed
                    ? "checkmark.circle.fill"
                    : "circle"
            )
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(
                item.status == .completed
                    ? MoraeColor.accent
                    : MoraeColor.secondaryForeground
            )
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            item.status == .completed
                ? "\(item.title) 미완료로 변경"
                : "\(item.title) 완료"
        )
    }

    private var titleAndMetadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: MoraeSpacing.xSmall) {
                if item.priority == .important {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("중요")
                }
                Text(item.title)
                    .font(.subheadline)
                    .strikethrough(item.status == .completed)
                    .foregroundStyle(
                        item.status == .completed
                            ? MoraeColor.secondaryForeground
                            : MoraeColor.foreground
                    )
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
            if let minutes = item.estimatedMinutes {
                Label("\(minutes)분", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(MoraeColor.secondaryForeground)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            if item.status == .pending {
                rowButton(
                    systemImage: "arrow.up",
                    accessibilityLabel: "\(item.title) 위로 이동",
                    isDisabled: !canMoveUp,
                    action: onMoveUp
                )
                rowButton(
                    systemImage: "arrow.down",
                    accessibilityLabel: "\(item.title) 아래로 이동",
                    isDisabled: !canMoveDown,
                    action: onMoveDown
                )
            }
            rowButton(
                systemImage: "pencil",
                accessibilityLabel: "\(item.title) 편집",
                action: onEdit
            )
            rowButton(
                systemImage: "trash",
                accessibilityLabel: "\(item.title) 삭제",
                action: onDelete
            )
        }
        .controlSize(.small)
        .opacity(isHovered ? 1 : 0.68)
    }

    private func rowButton(
        systemImage: String,
        accessibilityLabel: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
    }
}
