import Darwin
import Foundation

enum MoraeRuntimeProfile: Equatable, Sendable {
    case standard
    case freshTest(sessionID: String)

    static func current(
        arguments: [String] = CommandLine.arguments,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) -> MoraeRuntimeProfile {
        arguments.contains("--fresh-test-profile")
            ? .freshTest(sessionID: String(processID))
            : .standard
    }

    var isFreshTest: Bool {
        if case .freshTest = self {
            return true
        }
        return false
    }

    var displayName: String? {
        isFreshTest ? "첫 실행 테스트 모드" : nil
    }

    var sessionRootURL: URL? {
        guard case let .freshTest(sessionID) = self else { return nil }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "morae-fresh-test-\(getuid())-\(sessionID)",
                isDirectory: true
            )
    }

    var defaultsSuiteName: String? {
        guard case let .freshTest(sessionID) = self else { return nil }
        return "io.github.heejung-29cm.morae.fresh-test.\(sessionID)"
    }

    func makeUserDefaults(
        resetPersistentDomain: Bool = false
    ) -> UserDefaults {
        guard let defaultsSuiteName,
              let defaults = UserDefaults(suiteName: defaultsSuiteName)
        else {
            return .standard
        }
        if resetPersistentDomain {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        return defaults
    }

    func cleanUp() {
        guard isFreshTest else { return }
        if let defaultsSuiteName {
            UserDefaults(suiteName: defaultsSuiteName)?
                .removePersistentDomain(forName: defaultsSuiteName)
        }
    }
}

struct AppDataPaths: Equatable, Sendable {
    let directoryURL: URL
    let databaseURL: URL
}

enum AppDataDirectoryError: Error, LocalizedError, Equatable {
    case applicationSupportUnavailable
    case directoryInaccessible

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            "Morae could not locate Application Support."
        case .directoryInaccessible:
            "Morae could not access its local data directory."
        }
    }

    var recoverySuggestion: String? {
        "Check disk availability and folder permissions, then reopen Morae."
    }
}

struct AppDataDirectory {
    private let fileManager: FileManager
    private let applicationSupportURL: () throws -> URL

    init(
        fileManager: FileManager = .default,
        applicationSupportURL: (() throws -> URL)? = nil
    ) {
        self.fileManager = fileManager
        self.applicationSupportURL = applicationSupportURL ?? {
            guard let url = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw AppDataDirectoryError.applicationSupportUnavailable
            }
            return url
        }
    }

    func prepare() throws -> AppDataPaths {
        let supportURL = try applicationSupportURL()
        let directoryURL = supportURL.appendingPathComponent("Morae", isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true,
                  fileManager.isReadableFile(atPath: directoryURL.path),
                  fileManager.isWritableFile(atPath: directoryURL.path) else {
                throw AppDataDirectoryError.directoryInaccessible
            }
        } catch let error as AppDataDirectoryError {
            throw error
        } catch {
            throw AppDataDirectoryError.directoryInaccessible
        }

        return AppDataPaths(
            directoryURL: directoryURL,
            databaseURL: directoryURL.appendingPathComponent("morae.sqlite")
        )
    }
}
