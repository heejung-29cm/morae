import MoraeCore
import SwiftUI

struct TodoEditorView: View {
    private enum Field: Hashable {
        case title
        case estimatedMinutes
        case relatedURL
        case projectPath
    }

    @State private var draft: TodoEditDraft
    @FocusState private var focusedField: Field?

    let onSave: (TodoEditDraft) async -> Void
    let onCancel: () -> Void

    init(
        initialDraft: TodoEditDraft,
        onSave: @escaping (TodoEditDraft) async -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: initialDraft)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MoraeSpacing.medium) {
            HStack(spacing: MoraeSpacing.small) {
                Image(systemName: "pencil")
                    .foregroundStyle(MoraeColor.accent)
                Text("할 일 편집")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("편집 취소", systemImage: "xmark", action: onCancel)
                    .labelStyle(.iconOnly)
                    .buttonStyle(
                        MoraeIconButtonStyle(
                            size: MoraeControlMetrics.rowIconButtonSize,
                            showsBackground: false
                        )
                    )
                    .help("편집 취소")
            }

            VStack(alignment: .leading, spacing: MoraeSpacing.small) {
                TextField("제목", text: $draft.title)
                    .focused($focusedField, equals: .title)
                    .moraeInput(isFocused: focusedField == .title)
                    .accessibilityLabel("할 일 제목")
                Toggle("중요한 할 일", isOn: Binding(
                    get: { draft.priority == .important },
                    set: { draft.priority = $0 ? .important : .normal }
                ))
                HStack(spacing: MoraeSpacing.small) {
                    TextField("예상 시간(분)", text: $draft.estimatedMinutes)
                        .focused($focusedField, equals: .estimatedMinutes)
                        .moraeInput(
                            isFocused: focusedField == .estimatedMinutes
                        )
                    TextField("관련 URL", text: $draft.relatedURL)
                        .focused($focusedField, equals: .relatedURL)
                        .moraeInput(isFocused: focusedField == .relatedURL)
                }
                TextField("프로젝트 경로", text: $draft.projectPath)
                    .focused($focusedField, equals: .projectPath)
                    .moraeInput(isFocused: focusedField == .projectPath)
            }

            HStack(spacing: MoraeSpacing.compact) {
                Spacer()
                Button("취소", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(
                        MoraeCompactButtonStyle(variant: .chip)
                    )
                Button("저장") {
                    Task {
                        await onSave(draft)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(
                    MoraeCompactButtonStyle(variant: .prominent)
                )
            }
        }
        .padding(MoraeSpacing.medium)
        .background(
            MoraeColor.selectedFill,
            in: RoundedRectangle(cornerRadius: MoraeRadius.large)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MoraeRadius.large)
                .stroke(MoraeColor.accent.opacity(0.32))
        }
        .accessibilityElement(children: .contain)
        .task {
            focusedField = .title
        }
    }
}

struct InlineDeleteConfirmationView: View {
    let item: TodoItem
    let onCancel: () -> Void
    let onDelete: () -> Void

    @FocusState private var isCancelFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: MoraeSpacing.medium) {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 28, height: 28)
                .background(
                    Color.red.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: MoraeRadius.medium)
                )

            VStack(alignment: .leading, spacing: MoraeSpacing.small) {
                Text("‘\(item.title)’을 삭제할까요?")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text("삭제 후 5초 동안 실행 취소할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(MoraeColor.secondaryForeground)
                HStack(spacing: MoraeSpacing.compact) {
                    Spacer()
                    Button("취소", role: .cancel, action: onCancel)
                        .keyboardShortcut(.cancelAction)
                        .focused($isCancelFocused)
                        .buttonStyle(
                            MoraeCompactButtonStyle(variant: .chip)
                        )
                    Button("삭제", role: .destructive, action: onDelete)
                        .buttonStyle(
                            MoraeCompactButtonStyle(
                                variant: .chip,
                                foreground: MoraeColor.error
                            )
                        )
                }
            }
        }
        .padding(MoraeSpacing.medium)
        .background(
            Color.red.opacity(0.065),
            in: RoundedRectangle(cornerRadius: MoraeRadius.large)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MoraeRadius.large)
                .stroke(Color.red.opacity(0.20))
        }
        .accessibilityElement(children: .contain)
        .task {
            isCancelFocused = true
        }
    }
}

struct UndoDeleteBanner: View {
    let title: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: MoraeSpacing.small) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(MoraeColor.accent)
            Text("‘\(title)’을 삭제했습니다.")
                .font(.caption)
                .lineLimit(2)
            Spacer(minLength: MoraeSpacing.small)
            Button("실행 취소", action: onUndo)
                .font(.caption.weight(.semibold))
                .keyboardShortcut("z", modifiers: .command)
                .buttonStyle(
                    MoraeCompactButtonStyle(
                        variant: .chip,
                        foreground: MoraeColor.accent,
                        horizontalPadding: MoraeSpacing.small
                    )
                )
        }
        .padding(.horizontal, MoraeSpacing.medium)
        .padding(.vertical, 9)
        .background(
            MoraeColor.selectedFill,
            in: RoundedRectangle(cornerRadius: MoraeRadius.medium)
        )
        .accessibilityElement(children: .contain)
    }
}
