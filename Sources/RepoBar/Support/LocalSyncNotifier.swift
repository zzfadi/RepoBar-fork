import Foundation
import RepoBarCore
import UserNotifications

actor LocalSyncNotifier {
    static let shared = LocalSyncNotifier()
    private let center: UNUserNotificationCenter?

    init() {
        if Bundle.main.bundleURL.pathExtension == "app" {
            self.center = UNUserNotificationCenter.current()
        } else {
            self.center = nil
        }
    }

    func notifySync(for status: LocalRepoStatus) async {
        guard let center = self.center else { return }

        let authorizationStatus = await self.authorizationStatus(using: center)
        let authorized: Bool = switch authorizationStatus {
        case .authorized, .provisional:
            true
        case .notDetermined:
            await self.requestAuthorization(using: center)
        default:
            false
        }

        guard authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "RepoBar"
        content.body = "Synced \(status.displayName) (\(status.branch))"
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        _ = try? await center.add(request)
    }

    private func authorizationStatus(using center: UNUserNotificationCenter) async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func requestAuthorization(using center: UNUserNotificationCenter) async -> Bool {
        await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }
}
