import Foundation
import MoraeCore
import Observation

@MainActor
@Observable
final class MenuBarViewModel {
    private(set) var todayTodos: [TodoItem] = []
    private(set) var yesterdayCompleted: [TodoItem] = []
    private(set) var errorMessage: String?

    let today: LocalDay

    private let repository: (any TodoRepository)?
    private let clock: any Clock
    private let calendar: Calendar
    @ObservationIgnored
    nonisolated(unsafe) private var observationTask: Task<Void, Never>?

    init(
        repository: (any TodoRepository)?,
        clock: any Clock,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.repository = repository
        self.clock = clock
        self.calendar = calendar
        today = clock.localDay(for: clock.now(), calendar: calendar)
    }

    func onAppear() async {
        guard observationTask == nil, let repository else {
            return
        }

        do {
            let summary = try await BuildLocalTaskSummary(repository: repository)
                .execute(today: today, calendar: calendar)
            yesterdayCompleted = summary.yesterdayCompleted
        } catch {
            errorMessage = "할 일 요약을 불러오지 못했습니다."
        }

        observationTask = Task { [weak self, repository, today] in
            do {
                for try await items in repository.observation(day: today) {
                    guard !Task.isCancelled else { return }
                    self?.todayTodos = items
                    self?.errorMessage = nil
                }
            } catch is CancellationError {
                return
            } catch {
                self?.errorMessage = "할 일 목록을 불러오지 못했습니다."
            }
        }
    }

    func toggleTodo(id: TodoID) async {
        guard let repository,
              let item = todayTodos.first(where: { $0.id == id }) else {
            return
        }
        do {
            _ = try await repository.setCompletion(
                id: id,
                isCompleted: item.status == .pending,
                at: clock.now()
            )
        } catch {
            errorMessage = "완료 상태를 변경하지 못했습니다."
        }
    }

    deinit {
        observationTask?.cancel()
    }
}
