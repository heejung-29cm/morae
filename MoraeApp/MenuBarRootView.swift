import MoraeCore
import SwiftUI

enum MenuBarSection: String, CaseIterable, Sendable {
    case article
    case yesterdayCompleted
    case todayTodos
    case recentAgents

    static let orderedCases: [MenuBarSection] = [
        .article,
        .yesterdayCompleted,
        .todayTodos,
        .recentAgents,
    ]

    var title: String {
        switch self {
        case .article: "오늘의 아티클"
        case .yesterdayCompleted: "어제 완료"
        case .todayTodos: "오늘 할 일"
        case .recentAgents: "최근 에이전트 기록"
        }
    }

    var emptyMessage: String {
        switch self {
        case .article: "아직 추천한 아티클이 없습니다."
        case .yesterdayCompleted: "어제 완료한 일이 없습니다."
        case .todayTodos: "오늘 할 일이 없습니다."
        case .recentAgents: "수신한 에이전트 기록이 없습니다."
        }
    }
}

@MainActor
struct MenuBarRootView: View {
    let container: AppContainer
    @State private var viewModel: MenuBarViewModel

    init(container: AppContainer) {
        self.container = container
        _viewModel = State(
            initialValue: MenuBarViewModel(
                repository: container.todoRepository,
                clock: container.clock
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let startupError = container.startupError {
                        startupErrorView(startupError)
                    } else {
                        articleSection
                        yesterdaySection
                        todaySection
                        emptySection(.recentAgents)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 380, height: 600)
        .task {
            await viewModel.onAppear()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("모래")
                    .font(.headline)
                Text(viewModel.today.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("오늘 브리핑 만들기", systemImage: "sparkles") {}
                .disabled(true)
                .help("수동 브리핑은 Sprint 3에서 연결됩니다.")
            SettingsLink {
                Label("설정", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
            }
            .help("설정 열기")
            .accessibilityLabel("설정 열기")
        }
        .padding(16)
    }

    private var articleSection: some View {
        emptySection(.article)
    }

    private var yesterdaySection: some View {
        sectionContainer(.yesterdayCompleted) {
            if viewModel.yesterdayCompleted.isEmpty {
                emptyMessage(for: .yesterdayCompleted)
            } else {
                ForEach(viewModel.yesterdayCompleted) { item in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(item.title)
                            .lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("완료, \(item.title)")
                }
            }
        }
    }

    private var todaySection: some View {
        sectionContainer(.todayTodos) {
            if viewModel.todayTodos.isEmpty {
                emptyMessage(for: .todayTodos)
            } else {
                ForEach(viewModel.todayTodos) { item in
                    HStack(spacing: 8) {
                        Button {
                            Task {
                                await viewModel.toggleTodo(id: item.id)
                            }
                        } label: {
                            Image(
                                systemName: item.status == .completed
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            item.status == .completed
                                ? "\(item.title) 미완료로 변경"
                                : "\(item.title) 완료"
                        )

                        if item.priority == .important {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.orange)
                                .accessibilityLabel("중요")
                        }
                        Text(item.title)
                            .strikethrough(item.status == .completed)
                            .foregroundStyle(
                                item.status == .completed ? .secondary : .primary
                            )
                            .lineLimit(2)
                        Spacer()
                        if let minutes = item.estimatedMinutes {
                            Text("\(minutes)분")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("오류, \(errorMessage)")
            }
        }
    }

    private func emptySection(_ section: MenuBarSection) -> some View {
        sectionContainer(section) {
            emptyMessage(for: section)
        }
    }

    private func sectionContainer<Content: View>(
        _ section: MenuBarSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyMessage(for section: MenuBarSection) -> some View {
        Text(section.emptyMessage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("\(section.title), \(section.emptyMessage)")
    }

    private func startupErrorView(_ error: AppError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("로컬 데이터 열기 실패", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(error.userMessage)
            if let recovery = error.recovery {
                Text(recovery)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
