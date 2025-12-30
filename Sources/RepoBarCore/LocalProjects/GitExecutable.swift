import Foundation
import Security

public struct GitExecutableInfo: Equatable, Sendable {
    public let path: String
    public let version: String?
    public let error: String?
    public let isSandboxed: Bool

    public init(path: String, version: String?, error: String?, isSandboxed: Bool) {
        self.path = path
        self.version = version
        self.error = error
        self.isSandboxed = isSandboxed
    }
}

struct GitExecutableLocator: Sendable {
    static let shared = GitExecutableLocator()
    let url: URL

    init() {
        let fileManager = FileManager.default
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let pathCandidates = envPath
            .split(separator: ":")
            .map { "\($0)/git" }

        let preferred: [String] = if Self.isSandboxed {
            [
                "/Library/Developer/CommandLineTools/usr/bin/git",
                "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
                "/Applications/Xcode-beta.app/Contents/Developer/usr/bin/git"
            ]
        } else {
            [
                "/opt/homebrew/bin/git",
                "/usr/local/bin/git",
                "/Library/Developer/CommandLineTools/usr/bin/git",
                "/Applications/Xcode.app/Contents/Developer/usr/bin/git"
            ]
        }

        let candidates = preferred + pathCandidates + ["/usr/bin/git"]
        let resolved = candidates.first { fileManager.isExecutableFile(atPath: $0) } ?? "/usr/bin/git"
        self.url = URL(fileURLWithPath: resolved)
    }

    static var isSandboxed: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let entitlement = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil)
        return (entitlement as? Bool) == true
    }

    static func version(at url: URL) -> (version: String?, error: String?) {
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
            return (nil, error.localizedDescription)
        }
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus != 0 {
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return (nil, message.isEmpty ? "git --version failed" : message)
        }
        return (trimmed.isEmpty ? nil : trimmed, nil)
    }
}
