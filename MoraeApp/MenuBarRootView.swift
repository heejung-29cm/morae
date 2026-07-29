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

    private var today: LocalDay {
        container.clock.localDay(
            for: container.clock.now(),
            calendar: .autoupdatingCurrent
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
                        ForEach(MenuBarSection.orderedCases, id: \.self) { section in
                            emptySection(section)
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 380, height: 600)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("모래")
                    .font(.headline)
                Text(today.rawValue)
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

    private func emptySection(_ section: MenuBarSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.headline)
            Text(section.emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityElement(children: .combine)
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
