import Foundation
import Security

public struct LocalProjectsSnapshot: Equatable, Sendable {
    public let discoveredRepoCount: Int
    public let statuses: [LocalRepoStatus]
    public let syncedStatuses: [LocalRepoStatus]

    public init(discoveredRepoCount: Int, statuses: [LocalRepoStatus], syncedStatuses: [LocalRepoStatus]) {
        self.discoveredRepoCount = discoveredRepoCount
        self.statuses = statuses
        self.syncedStatuses = syncedStatuses
    }
}

public struct LocalProjectsService {
    public init() {}

    public static func gitExecutableInfo() -> GitExecutableInfo {
        let url = GitExecutableLocator.shared.url
        let version = GitExecutableLocator.version(at: url)
        return GitExecutableInfo(path: url.path, version: version)
    }

    public func discoverRepoRoots(rootPath: String, maxDepth: Int = 2) -> [URL] {
        let fileManager = FileManager.default
        let expandedRoot = PathFormatter.expandTilde(rootPath)
        let rootURL = URL(fileURLWithPath: expandedRoot, isDirectory: true)
        return self.discoverRepoRoots(rootURL: rootURL, maxDepth: maxDepth, fileManager: fileManager)
    }

    public func discoverRepoRoots(rootURL: URL, maxDepth: Int = 2) -> [URL] {
        self.discoverRepoRoots(rootURL: rootURL, maxDepth: maxDepth, fileManager: .default)
    }

    private func discoverRepoRoots(rootURL: URL, maxDepth: Int, fileManager: FileManager) -> [URL] {
        let rootURL = (rootURL as NSURL).filePathURL ?? rootURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return []
        }
        return self.findGitRepos(in: rootURL, maxDepth: max(0, maxDepth), fileManager: fileManager)
    }

    public func snapshot(
        rootPath: String,
        maxDepth: Int = 2,
        autoSyncEnabled: Bool,
        maxRepoCount: Int? = nil,
        includeOnlyRepoNames: Set<String>? = nil,
        concurrencyLimit: Int = 8
    ) async -> LocalProjectsSnapshot {
        let repos = self.discoverRepoRoots(rootPath: rootPath, maxDepth: maxDepth)
        return await self.snapshot(
            repoRoots: repos,
            autoSyncEnabled: autoSyncEnabled,
            maxRepoCount: maxRepoCount,
            includeOnlyRepoNames: includeOnlyRepoNames,
            concurrencyLimit: concurrencyLimit
        )
    }

    public func snapshot(
        repoRoots: [URL],
        autoSyncEnabled: Bool,
        maxRepoCount: Int? = nil,
        includeOnlyRepoNames: Set<String>? = nil,
        concurrencyLimit: Int = 8
    ) async -> LocalProjectsSnapshot {
        let git = GitRunner()

        guard repoRoots.isEmpty == false else {
            return LocalProjectsSnapshot(discoveredRepoCount: 0, statuses: [], syncedStatuses: [])
        }

        let filtered = includeOnlyRepoNames.map { allowList in
            repoRoots.filter { allowList.contains($0.lastPathComponent) }
        } ?? repoRoots

        let limitedRepos: [URL] = if let maxRepoCount, maxRepoCount > 0 {
            Array(filtered.prefix(maxRepoCount))
        } else {
            filtered
        }

        let chunkSize = max(1, concurrencyLimit)
        let chunks = stride(from: 0, to: limitedRepos.count, by: chunkSize).map { start in
            Array(limitedRepos[start ..< min(start + chunkSize, limitedRepos.count)])
        }

        struct Processed {
            let status: LocalRepoStatus
            let didSync: Bool
        }

        func loadStatus(at repoURL: URL) -> LocalRepoStatus? {
            let branch = currentBranch(at: repoURL, git: git)
            let isClean = isClean(at: repoURL, git: git)
            let (ahead, behind) = aheadBehind(at: repoURL, git: git)
            let syncState = LocalSyncState.resolve(isClean: isClean, ahead: ahead, behind: behind)
            let remote = remoteInfo(at: repoURL, git: git)
            let repoName = remote?.name ?? repoURL.lastPathComponent
            let fullName = remote?.fullName
            return LocalRepoStatus(
                path: repoURL,
                name: repoName,
                fullName: fullName,
                branch: branch,
                isClean: isClean,
                aheadCount: ahead,
                behindCount: behind,
                syncState: syncState
            )
        }

        func pullFastForward(at repoURL: URL) -> Bool {
            (try? git.run(["pull", "--ff-only"], in: repoURL)) != nil
        }

        func headSHA(at repoURL: URL) -> String? {
            (try? git.run(["rev-parse", "HEAD"], in: repoURL))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        var processed: [Processed] = []
        processed.reserveCapacity(limitedRepos.count)

        for chunk in chunks {
            await withTaskGroup(of: Processed?.self) { group in
                for repoURL in chunk {
                    group.addTask {
                        guard var status = loadStatus(at: repoURL) else { return nil }
                        var didSync = false
                        if autoSyncEnabled, status.isClean, status.branch != "detached" {
                            let before = headSHA(at: repoURL)
                            if pullFastForward(at: repoURL) {
                                let after = headSHA(at: repoURL)
                                if let before, let after, before != after {
                                    didSync = true
                                    status = loadStatus(at: repoURL) ?? status
                                }
                            }
                        }
                        return Processed(status: status, didSync: didSync)
                    }
                }

                for await item in group {
                    if let item {
                        processed.append(item)
                    }
                }
            }
        }

        var statuses = processed.map(\.status)
        let syncedStatuses = processed.filter(\.didSync).map(\.status)

        statuses.sort { lhs, rhs in
            if lhs.displayName != rhs.displayName { return lhs.displayName < rhs.displayName }
            return lhs.path.path < rhs.path.path
        }

        return LocalProjectsSnapshot(
            discoveredRepoCount: repoRoots.count,
            statuses: statuses,
            syncedStatuses: syncedStatuses
        )
    }

    private func findGitRepos(in root: URL, maxDepth: Int, fileManager: FileManager) -> [URL] {
        var results: [URL] = []

        func scan(_ url: URL, depth: Int) {
            if self.isGitRepo(url, fileManager: fileManager) {
                results.append(url)
                return
            }

            guard depth < maxDepth else { return }

            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                )
            } catch {
                return
            }

            for child in children {
                let name = child.lastPathComponent
                if name.hasPrefix(".") { continue }

                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true { continue }
                guard values?.isDirectory == true else { continue }

                scan(child, depth: depth + 1)
            }
        }

        scan(root, depth: 0)
        return results
    }

    private func isGitRepo(_ url: URL, fileManager: FileManager) -> Bool {
        let gitURL = url.appendingPathComponent(".git")
        return fileManager.fileExists(atPath: gitURL.path)
    }
}

public struct GitExecutableInfo: Equatable, Sendable {
    public let path: String
    public let version: String?

    public init(path: String, version: String?) {
        self.path = path
        self.version = version
    }
}

private struct GitRunner: Sendable {
    func run(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = GitExecutableLocator.shared.url
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw GitRunnerError.commandFailed(output: output, error: error)
        }
        return output
    }
}

private enum GitRunnerError: Error {
    case commandFailed(output: String, error: String)
}

private struct GitExecutableLocator: Sendable {
    static let shared = GitExecutableLocator()
    let url: URL

    init() {
        let fileManager = FileManager.default
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let pathCandidates = envPath
            .split(separator: ":")
            .map { "\($0)/git" }

        let preferred: [String] = if Self.isSandboxed {
            ["/usr/bin/git"]
        } else {
            [
                "/opt/homebrew/bin/git",
                "/usr/local/bin/git"
            ]
        }

        let candidates = preferred + pathCandidates + ["/usr/bin/git"]
        let resolved = candidates.first { fileManager.isExecutableFile(atPath: $0) } ?? "/usr/bin/git"
        self.url = URL(fileURLWithPath: resolved)
    }

    private static var isSandboxed: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let entitlement = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil)
        return (entitlement as? Bool) == true
    }

    static func version(at url: URL) -> String? {
        let process = Process()
        process.executableURL = url
        process.arguments = ["--version"]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        if process.terminationStatus != 0 { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct GitRemote: Sendable {
    let host: String
    let owner: String
    let name: String

    var fullName: String { "\(self.owner)/\(self.name)" }

    static func parse(_ value: String) -> GitRemote? {
        if value.contains("://") {
            return self.parseURL(value)
        }
        return self.parseScp(value)
    }

    private static func parseURL(_ value: String) -> GitRemote? {
        guard let url = URL(string: value),
              let host = url.host
        else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts[parts.count - 2]
        let name = self.stripGitSuffix(parts.last ?? "")
        return GitRemote(host: host, owner: owner, name: name)
    }

    private static func parseScp(_ value: String) -> GitRemote? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let hostPart = parts[0].split(separator: "@").last.map(String.init) ?? parts[0]
        let path = parts[1]
        let pathParts = path.split(separator: "/").map(String.init)
        guard pathParts.count >= 2 else { return nil }
        let owner = pathParts[pathParts.count - 2]
        let name = self.stripGitSuffix(pathParts.last ?? "")
        return GitRemote(host: hostPart, owner: owner, name: name)
    }

    private static func stripGitSuffix(_ value: String) -> String {
        value.hasSuffix(".git") ? String(value.dropLast(4)) : value
    }
}

private func currentBranch(at repoURL: URL, git: GitRunner) -> String {
    guard let raw = try? git.run(["rev-parse", "--abbrev-ref", "HEAD"], in: repoURL) else {
        return "unknown"
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed == "HEAD" ? "detached" : trimmed
}

private func isClean(at repoURL: URL, git: GitRunner) -> Bool {
    guard let output = try? git.run(["status", "--porcelain"], in: repoURL) else {
        return false
    }
    return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

private func aheadBehind(at repoURL: URL, git: GitRunner) -> (ahead: Int?, behind: Int?) {
    guard let output = try? git.run(["rev-list", "--left-right", "--count", "@{u}...HEAD"], in: repoURL) else {
        return (nil, nil)
    }
    let parts = output.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
    guard parts.count >= 2,
          let behind = Int(parts[0]),
          let ahead = Int(parts[1])
    else { return (nil, nil) }
    return (ahead, behind)
}

private func remoteInfo(at repoURL: URL, git: GitRunner) -> GitRemote? {
    guard let raw = try? git.run(["remote", "get-url", "origin"], in: repoURL) else {
        return nil
    }
    return GitRemote.parse(raw.trimmingCharacters(in: .whitespacesAndNewlines))
}
