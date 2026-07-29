import Foundation

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
