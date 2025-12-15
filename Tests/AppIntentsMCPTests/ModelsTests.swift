import Testing
@testable import AppIntentsMCP

@Suite("Models Tests")
struct ModelsTests {

    @Test("Intent can be created with required fields")
    func intentCreation() {
        let intent = DiscoveredIntent(
            id: "com.apple.reminders.CreateReminder",
            appBundleID: "com.apple.reminders",
            name: "Create Reminder",
            description: "Creates a new reminder",
            parameters: [],
            returnsResult: true
        )

        #expect(intent.id == "com.apple.reminders.CreateReminder")
        #expect(intent.appBundleID == "com.apple.reminders")
        #expect(intent.name == "Create Reminder")
    }
}
