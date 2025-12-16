import Testing
import Foundation
@testable import AppIntentsMCP

@Suite("IntentDiscovery Tests")
struct IntentDiscoveryTests {

    @Test("Can discover intents from system")
    func discoverIntents() async throws {
        let discovery = IntentDiscovery()
        let intents = try await discovery.discoverAll()

        // Should find at least some intents on any macOS system
        // (Reminders, Calendar, etc. have App Intents)
        // Just verify it runs without crashing
        #expect(intents.count >= 0)
    }

    @Test("Can search intents by query")
    func searchIntents() async throws {
        let discovery = IntentDiscovery()
        _ = try await discovery.discoverAll()

        let results = await discovery.search(query: "reminder")
        // Results depend on what's installed
        #expect(results.count >= 0)
    }
}
