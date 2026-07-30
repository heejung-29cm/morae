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
        HStack(alignment: .center, spacing: MoraeSpacing.xSmall) {
            dragHandle
            completionButton
            titleAndMetadata
            Spacer(minLength: MoraeSpacing.xSmall)
            actionButtons
        }
        .padding(.leading, MoraeSpacing.xSmall)
        .padding(.trailing, MoraeSpacing.small)
        .padding(.vertical, 5)
        .background(
            isHovered ? MoraeColor.subtleFill : .clear,
            in: RoundedRectangle(cornerRadius: MoraeRadius.control)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .modifier(
            TodoDragSourceModifier(
                item: item,
                identifier: dragIdentifier,
                onDragStarted: onDragStarted
            )
        )
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
        .contextMenu {
            if item.status == .pending {
                Button("위로 이동", systemImage: "arrow.up", action: onMoveUp)
                    .disabled(!canMoveUp)
                Button("아래로 이동", systemImage: "arrow.down", action: onMoveDown)
                    .disabled(!canMoveDown)
                Divider()
            }
            Button("편집", systemImage: "pencil", action: onEdit)
            Button(
                "삭제",
                systemImage: "trash",
                role: .destructive,
                action: onDelete
            )
        }
    }

    @ViewBuilder
    private var dragHandle: some View {
        if dragIdentifier != nil {
            TodoDragHandleGlyph()
                .foregroundStyle(MoraeColor.mutedForeground)
                .frame(width: 18, height: 24)
                .opacity(isHovered ? 0.82 : 0.58)
                .contentShape(Rectangle())
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
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(
                item.status == .completed
                    ? MoraeColor.accent
                    : MoraeColor.secondaryForeground
            )
            .frame(width: 16, height: 16)
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
                    .font(.system(size: 12.5))
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
        .padding(.leading, 5)
    }

    private var actionButtons: some View {
        HStack(spacing: 1) {
            TodoRowActionButton(
                systemImage: "pencil",
                accessibilityLabel: "\(item.title) 편집",
                action: onEdit
            )
            TodoRowActionButton(
                systemImage: "trash",
                accessibilityLabel: "\(item.title) 삭제",
                isDestructive: true,
                action: onDelete
            )
        }
        .opacity(isHovered ? 1 : 0.60)
    }
}

private struct TodoDragSourceModifier: ViewModifier {
    let item: TodoItem
    let identifier: String?
    let onDragStarted: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier {
            content.onDrag {
                onDragStarted()
                return NSItemProvider(object: identifier as NSString)
            } preview: {
                TodoDragPreview(item: item)
            }
        } else {
            content
        }
    }
}

private struct TodoDragPreview: View {
    let item: TodoItem

    var body: some View {
        HStack(alignment: .center, spacing: MoraeSpacing.xSmall) {
            TodoDragHandleGlyph()
                .foregroundStyle(MoraeColor.mutedForeground)
                .frame(width: 18, height: 24)
            Image(systemName: "circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(MoraeColor.secondaryForeground)
                .frame(width: 16, height: 16)
            HStack(alignment: .firstTextBaseline, spacing: MoraeSpacing.xSmall) {
                if item.priority == .important {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(item.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(MoraeColor.foreground)
                    .lineLimit(2)
            }
            .padding(.leading, 5)
            Spacer(minLength: MoraeSpacing.small)
        }
        .padding(.leading, MoraeSpacing.xSmall)
        .padding(.trailing, MoraeSpacing.small)
        .padding(.vertical, 7)
        .frame(width: 340, alignment: .leading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: MoraeRadius.medium)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MoraeRadius.medium)
                .stroke(MoraeColor.controlBorder, lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)
        .opacity(0.94)
    }
}

private struct TodoDragHandleGlyph: View {
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    Circle()
                        .frame(width: 2, height: 2)
                    Circle()
                        .frame(width: 2, height: 2)
                }
            }
        }
    }
}

private struct TodoRowActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var isDestructive = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .frame(
                    width: MoraeControlMetrics.rowIconButtonSize,
                    height: MoraeControlMetrics.rowIconButtonSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            isDestructive && isHovered
                ? MoraeColor.error
                : MoraeColor.secondaryForeground
        )
        .background(
            isHovered ? MoraeColor.chipFill : .clear,
            in: RoundedRectangle(cornerRadius: MoraeRadius.small)
        )
        .onHover { isHovered = $0 }
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
    }
}
