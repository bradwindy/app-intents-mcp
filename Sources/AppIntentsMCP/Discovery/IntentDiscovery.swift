import Foundation

public actor IntentDiscovery {
    private var cachedIntents: [DiscoveredIntent] = []
    private var lastDiscoveryTime: Date?
    private let bundleScanner = BundleScanner()

    public init() {}

    public func discoverAll(forceRefresh: Bool = false) async throws -> [DiscoveredIntent] {
        if !forceRefresh,
           let lastTime = lastDiscoveryTime,
           Date().timeIntervalSince(lastTime) < 300, // 5 minute cache
           !cachedIntents.isEmpty {
            return cachedIntents
        }

        var allIntents: [DiscoveredIntent] = []

        // Layer 1: Bundle scanning
        let bundleIntents = await bundleScanner.scanAllApps()
        allIntents.append(contentsOf: bundleIntents)

        // Layer 2: Shortcuts database (future implementation)
        // let shortcutsIntents = try await shortcutsDBScanner.scan()
        // allIntents.append(contentsOf: shortcutsIntents)

        // Deduplicate by ID
        var seen = Set<String>()
        cachedIntents = allIntents.filter { intent in
            if seen.contains(intent.id) { return false }
            seen.insert(intent.id)
            return true
        }

        lastDiscoveryTime = Date()
        return cachedIntents
    }

    public func getIntent(byID id: String) async -> DiscoveredIntent? {
        return cachedIntents.first { $0.id == id }
    }

    public func search(query: String) async -> [DiscoveredIntent] {
        let lowercaseQuery = query.lowercased()
        return cachedIntents.filter { intent in
            intent.name.lowercased().contains(lowercaseQuery) ||
            intent.description?.lowercased().contains(lowercaseQuery) == true ||
            intent.appBundleID.lowercased().contains(lowercaseQuery)
        }
    }

    public func getIntents(forApp bundleID: String) async -> [DiscoveredIntent] {
        return cachedIntents.filter { $0.appBundleID == bundleID }
    }

    public func listApps() async -> [(bundleID: String, intentCount: Int)] {
        var appCounts: [String: Int] = [:]
        for intent in cachedIntents {
            appCounts[intent.appBundleID, default: 0] += 1
        }
        return appCounts.map { ($0.key, $0.value) }.sorted { $0.intentCount > $1.intentCount }
    }
}
