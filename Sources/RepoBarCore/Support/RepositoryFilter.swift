import Foundation

public enum RepositoryFilter {
    public static func apply(
        _ repos: [Repository],
        includeForks: Bool,
        pinned: Set<String> = []
    ) -> [Repository] {
        guard includeForks == false else { return repos }
        guard pinned.isEmpty == false else { return repos.filter { $0.isFork == false } }
        return repos.filter { repo in
            repo.isFork == false || pinned.contains(repo.fullName)
        }
    }
}
