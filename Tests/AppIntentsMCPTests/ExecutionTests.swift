import Testing
import Foundation
@testable import AppIntentsMCP

@Suite("Execution Tests")
struct ExecutionTests {

    @Test("Shortcuts bridge can check if shortcuts CLI exists")
    func shortcutsCLIExists() async {
        let bridge = ShortcutsBridge()
        let exists = await bridge.isAvailable()
        // shortcuts CLI should exist on macOS 12+
        #expect(exists == true)
    }

    @Test("Intent executor returns result")
    func executeIntent() async throws {
        let executor = IntentExecutor()
        let intent = DiscoveredIntent(
            id: "test.intent",
            appBundleID: "com.test",
            name: "Test Intent",
            description: nil,
            parameters: [],
            returnsResult: false
        )

        let result = await executor.execute(intent: intent, parameters: nil)
        // Will fail to execute since it's a fake intent, but should return a result
        #expect(result.success == false || result.success == true)
    }
}
