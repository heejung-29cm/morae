import Foundation

enum AgentHookProvider: String, CaseIterable, Hashable, Sendable {
    case codex
    case claude

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        }
    }
}

enum AgentHookInstallStatus: Equatable, Sendable {
    case notInstalled
    case installed
    case needsAttention(String)
}

enum AgentHookInstallError: Error, LocalizedError, Equatable {
    case helperUnavailable
    case invalidCodexConfig
    case unsupportedCodexNotify
    case invalidClaudeConfig
    case unsupportedClaudeHooks
    case fileOperationFailed

    var errorDescription: String? {
        switch self {
        case .helperUnavailable:
            "이벤트 helper를 찾을 수 없습니다. 모래를 다시 설치해 주세요."
        case .invalidCodexConfig:
            "Codex 설정 파일을 읽을 수 없습니다. config.toml 문법을 확인해 주세요."
        case .unsupportedCodexNotify:
            "기존 Codex notify 형식이 복잡해 자동으로 병합할 수 없습니다. 직접 설정을 이용해 주세요."
        case .invalidClaudeConfig:
            "Claude 설정 파일이 올바른 JSON이 아닙니다. settings.json 문법을 확인해 주세요."
        case .unsupportedClaudeHooks:
            "기존 Claude hooks 형식을 안전하게 병합할 수 없습니다. 직접 설정을 이용해 주세요."
        case .fileOperationFailed:
            "설정 파일을 안전하게 저장하지 못했습니다. 폴더 권한을 확인해 주세요."
        }
    }
}

protocol AgentHookInstalling {
    func status(
        for provider: AgentHookProvider
    ) -> AgentHookInstallStatus
    func install(
        _ provider: AgentHookProvider,
        sourceHelperURL: URL
    ) throws
    func installedHelperURL() -> URL
}

struct LiveAgentHookInstaller: AgentHookInstalling {
    static let relayArgument = "--morae-codex-relay"

    private struct ClaudeHookSpec {
        let event: String
        let argument: String
        let matcher: String?
    }

    private static let claudeSpecs = [
        ClaudeHookSpec(
            event: "UserPromptSubmit",
            argument: "claude-turn-start",
            matcher: nil
        ),
        ClaudeHookSpec(
            event: "Stop",
            argument: "claude-stop",
            matcher: nil
        ),
        ClaudeHookSpec(
            event: "Notification",
            argument: "claude-notification",
            matcher:
                "permission_prompt|elicitation_dialog|agent_needs_input"
        ),
        ClaudeHookSpec(
            event: "TaskCompleted",
            argument: "claude-task-completed",
            matcher: nil
        ),
        ClaudeHookSpec(
            event: "StopFailure",
            argument: "claude-stop-failure",
            matcher: nil
        ),
    ]

    private let fileManager: FileManager
    private let homeDirectoryURL: URL
    private let applicationSupportURL: URL

    init(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationSupportURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.homeDirectoryURL = homeDirectoryURL
        self.applicationSupportURL = applicationSupportURL
            ?? fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
            ?? homeDirectoryURL.appendingPathComponent(
                "Library/Application Support",
                isDirectory: true
            )
    }

    func status(
        for provider: AgentHookProvider
    ) -> AgentHookInstallStatus {
        do {
            switch provider {
            case .codex:
                guard fileManager.fileExists(
                    atPath: codexConfigURL.path
                ) else {
                    return .notInstalled
                }
                let content = try String(
                    contentsOf: codexConfigURL,
                    encoding: .utf8
                )
                guard let command = try codexNotifyCommand(in: content)
                else {
                    return .notInstalled
                }
                return command.first == installedHelperURL().path
                    ? .installed
                    : .notInstalled
            case .claude:
                guard fileManager.fileExists(
                    atPath: claudeConfigURL.path
                ) else {
                    return .notInstalled
                }
                let root = try claudeRoot(at: claudeConfigURL)
                return Self.claudeSpecs.allSatisfy {
                    containsClaudeHook(
                        root: root,
                        spec: $0,
                        helperURL: installedHelperURL()
                    )
                } ? .installed : .notInstalled
            }
        } catch let error as AgentHookInstallError {
            return .needsAttention(error.localizedDescription)
        } catch {
            return .needsAttention(
                AgentHookInstallError.fileOperationFailed.localizedDescription
            )
        }
    }

    func install(
        _ provider: AgentHookProvider,
        sourceHelperURL: URL
    ) throws {
        let helperURL = try installHelper(from: sourceHelperURL)
        switch provider {
        case .codex:
            try installCodex(helperURL: helperURL)
        case .claude:
            try installClaude(helperURL: helperURL)
        }
    }

    func installedHelperURL() -> URL {
        applicationSupportURL
            .appendingPathComponent("Morae", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("hamster-event")
    }

    private var codexConfigURL: URL {
        homeDirectoryURL
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml")
    }

    private var claudeConfigURL: URL {
        homeDirectoryURL
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private func installHelper(from sourceURL: URL) throws -> URL {
        guard fileManager.isExecutableFile(atPath: sourceURL.path) else {
            throw AgentHookInstallError.helperUnavailable
        }
        let destinationURL = installedHelperURL()
        let directoryURL = destinationURL.deletingLastPathComponent()
        let temporaryURL = directoryURL.appendingPathComponent(
            ".hamster-event-\(UUID().uuidString)"
        )
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: sourceURL, to: temporaryURL)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: temporaryURL.path
            )
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(
                    destinationURL,
                    withItemAt: temporaryURL
                )
            } else {
                try fileManager.moveItem(
                    at: temporaryURL,
                    to: destinationURL
                )
            }
            return destinationURL
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw AgentHookInstallError.fileOperationFailed
        }
    }

    private func installCodex(helperURL: URL) throws {
        let directoryURL = codexConfigURL.deletingLastPathComponent()
        let content: String
        if fileManager.fileExists(atPath: codexConfigURL.path) {
            do {
                content = try String(
                    contentsOf: codexConfigURL,
                    encoding: .utf8
                )
            } catch {
                throw AgentHookInstallError.invalidCodexConfig
            }
        } else {
            content = ""
        }

        let existing = try codexNotifyCommand(in: content)
        let previous = previousCodexCommand(from: existing, helperURL: helperURL)
        let command: [String]
        if let previous, !isMoraeHelperCommand(previous) {
            let data = try JSONEncoder().encode(previous)
            command = [
                helperURL.path,
                Self.relayArgument,
                data.base64EncodedString(),
            ]
        } else {
            command = [helperURL.path]
        }
        let updated = try replacingCodexNotify(
            in: content,
            command: command
        )
        try save(
            Data(updated.utf8),
            to: codexConfigURL,
            creating: directoryURL
        )
    }

    private func previousCodexCommand(
        from command: [String]?,
        helperURL: URL
    ) -> [String]? {
        guard let command else { return nil }
        guard command.count == 3,
              command[0] == helperURL.path,
              command[1] == Self.relayArgument,
              let data = Data(base64Encoded: command[2]),
              let previous = try? JSONDecoder().decode(
                [String].self,
                from: data
              )
        else {
            return command
        }
        return previous
    }

    private func isMoraeHelperCommand(_ command: [String]) -> Bool {
        guard let executable = command.first else { return false }
        return executable == installedHelperURL().path
            || executable.hasSuffix(
                "/Morae.app/Contents/MacOS/hamster-event"
            )
    }

    private func replacingCodexNotify(
        in content: String,
        command: [String]
    ) throws -> String {
        let line = "notify = \(tomlArray(command))"
        let rootRange = codexRootRange(in: content)
        let root = String(content[rootRange])
        let completePattern =
            #"(?m)^[ \t]*notify[ \t]*=[ \t]*(\[[^\r\n]*\])[ \t]*(?:#.*)?$"#
        let anyPattern = #"(?m)^[ \t]*notify[ \t]*="#
        let complete = try NSRegularExpression(pattern: completePattern)
        let any = try NSRegularExpression(pattern: anyPattern)
        let rootNSRange = NSRange(root.startIndex..., in: root)
        let matches = complete.matches(
            in: root,
            range: rootNSRange
        )
        guard matches.count <= 1 else {
            throw AgentHookInstallError.invalidCodexConfig
        }
        if let match = matches.first,
           let range = Range(match.range, in: root) {
            let absoluteRange = range.lowerBound..<range.upperBound
            let updatedRoot = root.replacingCharacters(
                in: absoluteRange,
                with: line
            )
            return updatedRoot + content[rootRange.upperBound...]
        }
        if any.firstMatch(in: root, range: rootNSRange) != nil {
            throw AgentHookInstallError.unsupportedCodexNotify
        }
        let separator = root.isEmpty || root.hasSuffix("\n") ? "" : "\n"
        return root + separator + line + "\n"
            + content[rootRange.upperBound...]
    }

    private func codexNotifyCommand(
        in content: String
    ) throws -> [String]? {
        let root = String(content[codexRootRange(in: content)])
        let completePattern =
            #"(?m)^[ \t]*notify[ \t]*=[ \t]*(\[[^\r\n]*\])[ \t]*(?:#.*)?$"#
        let anyPattern = #"(?m)^[ \t]*notify[ \t]*="#
        let complete = try NSRegularExpression(pattern: completePattern)
        let any = try NSRegularExpression(pattern: anyPattern)
        let fullRange = NSRange(root.startIndex..., in: root)
        let matches = complete.matches(in: root, range: fullRange)
        guard matches.count <= 1 else {
            throw AgentHookInstallError.invalidCodexConfig
        }
        guard let match = matches.first else {
            if any.firstMatch(in: root, range: fullRange) != nil {
                throw AgentHookInstallError.unsupportedCodexNotify
            }
            return nil
        }
        guard let arrayRange = Range(match.range(at: 1), in: root),
              let command = parseTOMLArray(String(root[arrayRange])),
              !command.isEmpty else {
            throw AgentHookInstallError.invalidCodexConfig
        }
        return command
    }

    private func codexRootRange(in content: String) -> Range<String.Index> {
        let pattern = #"(?m)^[ \t]*\[\[?[A-Za-z0-9_.\"'-]"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: content,
                range: NSRange(content.startIndex..., in: content)
              ),
              let range = Range(match.range, in: content)
        else {
            return content.startIndex..<content.endIndex
        }
        return content.startIndex..<range.lowerBound
    }

    private func tomlArray(_ values: [String]) -> String {
        let encoded = values.map {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            let data = try! encoder.encode($0)
            return String(decoding: data, as: UTF8.self)
        }
        return "[\(encoded.joined(separator: ", "))]"
    }

    private func parseTOMLArray(_ value: String) -> [String]? {
        var index = value.startIndex
        func skipWhitespace() {
            while index < value.endIndex,
                  value[index].isWhitespace {
                index = value.index(after: index)
            }
        }
        skipWhitespace()
        guard index < value.endIndex, value[index] == "[" else {
            return nil
        }
        index = value.index(after: index)
        var result: [String] = []
        while true {
            skipWhitespace()
            guard index < value.endIndex else { return nil }
            if value[index] == "]" {
                index = value.index(after: index)
                skipWhitespace()
                return index == value.endIndex ? result : nil
            }
            let quote = value[index]
            guard quote == "\"" || quote == "'" else { return nil }
            index = value.index(after: index)
            var item = ""
            var escaped = false
            var closed = false
            while index < value.endIndex {
                let character = value[index]
                index = value.index(after: index)
                if quote == "\"", escaped {
                    switch character {
                    case "\"": item.append("\"")
                    case "\\": item.append("\\")
                    case "n": item.append("\n")
                    case "r": item.append("\r")
                    case "t": item.append("\t")
                    default: return nil
                    }
                    escaped = false
                } else if quote == "\"", character == "\\" {
                    escaped = true
                } else if character == quote {
                    closed = true
                    break
                } else {
                    item.append(character)
                }
            }
            guard closed, !escaped else { return nil }
            result.append(item)
            skipWhitespace()
            guard index < value.endIndex else { return nil }
            if value[index] == "," {
                index = value.index(after: index)
                continue
            }
            if value[index] != "]" { return nil }
        }
    }

    private func installClaude(helperURL: URL) throws {
        let root: [String: Any]
        if fileManager.fileExists(atPath: claudeConfigURL.path) {
            root = try claudeRoot(at: claudeConfigURL)
        } else {
            root = [:]
        }
        var updated = root
        var hooks = (root["hooks"] as? [String: Any]) ?? [:]
        if root["hooks"] != nil, root["hooks"] as? [String: Any] == nil {
            throw AgentHookInstallError.unsupportedClaudeHooks
        }
        for spec in Self.claudeSpecs {
            var groups = (hooks[spec.event] as? [[String: Any]]) ?? []
            if hooks[spec.event] != nil,
               hooks[spec.event] as? [[String: Any]] == nil {
                throw AgentHookInstallError.unsupportedClaudeHooks
            }
            groups = removingMoraeHandlers(from: groups, argument: spec.argument)
            var group: [String: Any] = [
                "hooks": [[
                    "type": "command",
                    "command": claudeCommand(
                        helperURL: helperURL,
                        argument: spec.argument
                    ),
                ]],
            ]
            if let matcher = spec.matcher {
                group["matcher"] = matcher
            }
            groups.append(group)
            hooks[spec.event] = groups
        }
        updated["hooks"] = hooks
        guard JSONSerialization.isValidJSONObject(updated) else {
            throw AgentHookInstallError.invalidClaudeConfig
        }
        let data = try JSONSerialization.data(
            withJSONObject: updated,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try save(
            data + Data("\n".utf8),
            to: claudeConfigURL,
            creating: claudeConfigURL.deletingLastPathComponent()
        )
    }

    private func claudeRoot(at url: URL) throws -> [String: Any] {
        do {
            let data = try Data(contentsOf: url)
            guard let root = try JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
                throw AgentHookInstallError.invalidClaudeConfig
            }
            return root
        } catch let error as AgentHookInstallError {
            throw error
        } catch {
            throw AgentHookInstallError.invalidClaudeConfig
        }
    }

    private func removingMoraeHandlers(
        from groups: [[String: Any]],
        argument: String
    ) -> [[String: Any]] {
        groups.compactMap { group in
            guard let handlers = group["hooks"] as? [[String: Any]]
            else {
                return group
            }
            let remaining = handlers.filter {
                guard let command = $0["command"] as? String else {
                    return true
                }
                return !isMoraeClaudeCommand(
                    command,
                    argument: argument
                )
            }
            guard !remaining.isEmpty else { return nil }
            var updated = group
            updated["hooks"] = remaining
            return updated
        }
    }

    private func containsClaudeHook(
        root: [String: Any],
        spec: ClaudeHookSpec,
        helperURL: URL
    ) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any],
              let groups = hooks[spec.event] as? [[String: Any]]
        else {
            return false
        }
        let expected = claudeCommand(
            helperURL: helperURL,
            argument: spec.argument
        )
        return groups.contains { group in
            guard let handlers = group["hooks"] as? [[String: Any]]
            else {
                return false
            }
            let matcherMatches = spec.matcher == nil
                || group["matcher"] as? String == spec.matcher
            return matcherMatches && handlers.contains {
                $0["type"] as? String == "command"
                    && $0["command"] as? String == expected
            }
        }
    }

    private func isMoraeClaudeCommand(
        _ command: String,
        argument: String
    ) -> Bool {
        command.contains("hamster-event")
            && command.hasSuffix(" \(argument)")
    }

    private func claudeCommand(
        helperURL: URL,
        argument: String
    ) -> String {
        "\"\(helperURL.path.replacingOccurrences(of: "\"", with: "\\\""))\" \(argument)"
    }

    private func save(
        _ data: Data,
        to url: URL,
        creating directoryURL: URL
    ) throws {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: url.path) {
                let backupURL = url.appendingPathExtension("morae-backup")
                if !fileManager.fileExists(atPath: backupURL.path) {
                    try fileManager.copyItem(at: url, to: backupURL)
                }
            }
            let permissions = try? fileManager.attributesOfItem(
                atPath: url.path
            )[.posixPermissions]
            try data.write(to: url, options: .atomic)
            if let permissions {
                try fileManager.setAttributes(
                    [.posixPermissions: permissions],
                    ofItemAtPath: url.path
                )
            }
        } catch {
            throw AgentHookInstallError.fileOperationFailed
        }
    }
}
