import Foundation

public enum RepoAutocompleteScoring {
    private struct ComponentScoreWeights {
        let exact: Int
        let prefix: Int
        let substring: Int
        let subsequence: Int
    }

    public struct Scored {
        public let repo: Repository
        public let score: Int
        public let sourceRank: Int

        public init(repo: Repository, score: Int, sourceRank: Int) {
            self.repo = repo
            self.score = score
            self.sourceRank = sourceRank
        }
    }

    public static func scored(
        repos: [Repository],
        query: String,
        sourceRank: Int,
        bonus: Int = 0
    ) -> [Scored] {
        repos.compactMap { repo in
            guard let score = Self.score(repo: repo, query: query) else { return nil }
            return Scored(repo: repo, score: score + bonus, sourceRank: sourceRank)
        }
    }

    public static func sort(_ scored: [Scored]) -> [Scored] {
        scored.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.sourceRank != $1.sourceRank { return $0.sourceRank < $1.sourceRank }
            return $0.repo.fullName.localizedCaseInsensitiveCompare($1.repo.fullName) == .orderedAscending
        }
    }

    public static func merge(local: [Scored], remote: [Scored], limit: Int) -> [Repository] {
        var bestByKey: [String: Scored] = [:]
        let insert: (Scored) -> Void = { scored in
            let key = scored.repo.fullName.lowercased()
            if let existing = bestByKey[key] {
                if scored.score > existing.score {
                    bestByKey[key] = scored
                }
            } else {
                bestByKey[key] = scored
            }
        }
        local.forEach(insert)
        remote.forEach(insert)
        return Array(Self.sort(Array(bestByKey.values)).prefix(limit)).map(\.repo)
    }

    public static func score(repo: Repository, query: String) -> Int? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowerQuery = trimmed.lowercased()
        let fullName = repo.fullName.lowercased()
        let hasSlash = lowerQuery.contains("/")
        if hasSlash {
            if fullName == lowerQuery { return 1000 }
            if fullName.hasPrefix(lowerQuery) { return 700 }
        }

        let parts = lowerQuery.split(separator: "/", omittingEmptySubsequences: false)
        let ownerQuery = parts.count > 1 ? String(parts[0]) : nil
        let repoQuery = parts.count > 1 ? String(parts[1]) : lowerQuery

        let ownerScore = Self.componentScore(
            query: ownerQuery ?? "",
            target: repo.owner,
            weights: ComponentScoreWeights(
                exact: 200,
                prefix: 120,
                substring: 80,
                subsequence: 40
            )
        )
        let repoScore = Self.componentScore(
            query: repoQuery,
            target: repo.name,
            weights: ComponentScoreWeights(
                exact: 600,
                prefix: 420,
                substring: 260,
                subsequence: 160
            )
        )

        var score = 0
        if let ownerScore, ownerQuery != nil {
            score += ownerScore
        }
        if let repoScore {
            score += repoScore
        }

        if ownerQuery == nil {
            if repoScore == nil {
                let ownerFallback = Self.componentScore(
                    query: lowerQuery,
                    target: repo.owner,
                    weights: ComponentScoreWeights(
                        exact: 120,
                        prefix: 80,
                        substring: 60,
                        subsequence: 30
                    )
                )
                guard let ownerFallback else { return nil }
                score += ownerFallback
            }
        } else if ownerScore == nil, repoScore == nil {
            return nil
        }

        if ownerScore != nil, repoScore != nil {
            score += 40
        }
        return score == 0 ? nil : score
    }

    private static func componentScore(
        query: String,
        target: String,
        weights: ComponentScoreWeights
    ) -> Int? {
        guard !query.isEmpty else { return 0 }
        let lowerTarget = target.lowercased()
        if lowerTarget == query { return weights.exact }
        if lowerTarget.hasPrefix(query) { return weights.prefix }
        if lowerTarget.contains(query) { return weights.substring }
        if Self.isSubsequence(query, of: lowerTarget) { return weights.subsequence }
        return nil
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var needleIndex = needle.startIndex
        var haystackIndex = haystack.startIndex

        while needleIndex < needle.endIndex, haystackIndex < haystack.endIndex {
            if needle[needleIndex] == haystack[haystackIndex] {
                needleIndex = needle.index(after: needleIndex)
            }
            haystackIndex = haystack.index(after: haystackIndex)
        }

        return needleIndex == needle.endIndex
    }
}
