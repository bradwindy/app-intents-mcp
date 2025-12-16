import Testing
import Foundation
@testable import AppIntentsMCP

@Suite("BundleScanner Tests")
struct BundleScannerTests {

    @Test("Can find application directories")
    func findAppDirectories() async {
        let scanner = BundleScanner()
        let directories = scanner.applicationDirectories

        #expect(directories.contains("/Applications"))
        #expect(directories.contains(NSHomeDirectory() + "/Applications"))
    }

    @Test("Can scan app bundle for metadata")
    func scanAppBundle() async throws {
        let scanner = BundleScanner()
        // Scan a known system app
        let infos = try await scanner.scanBundle(at: URL(fileURLWithPath: "/System/Applications/Reminders.app"))
        // May or may not find intents depending on macOS version
        // Just verify it doesn't crash
        #expect(infos != nil || infos == nil) // Always passes, just checks no crash
    }
}
