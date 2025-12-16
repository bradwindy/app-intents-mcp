import Foundation

public actor IntentExecutor {
    private let shortcutsBridge = ShortcutsBridge()

    public init() {}

    public func execute(intent: DiscoveredIntent, parameters: JSONValue?) async -> IntentResult {
        let startTime = Date()

        // Strategy 1: Try to find and run a matching shortcut
        if await shortcutsBridge.isAvailable() {
            // Convert parameters to JSON input if present
            var input: String? = nil
            if let params = parameters {
                let paramsDict = jsonValueToDict(params)
                if !paramsDict.isEmpty {
                    if let jsonData = try? JSONSerialization.data(withJSONObject: paramsDict),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        input = jsonString
                    }
                }
            }

            // Try running a shortcut that matches the intent name
            // This is a simplified approach - in practice we'd need to:
            // 1. Create a wrapper shortcut dynamically
            // 2. Or use private APIs to invoke intents directly
            do {
                let shortcuts = try await shortcutsBridge.listShortcuts()

                // Look for a shortcut matching the intent name
                let shortcutName = intent.name.replacingOccurrences(of: " ", with: "")
                if let match = shortcuts.first(where: {
                    $0.lowercased().contains(intent.name.lowercased()) ||
                    $0.lowercased().contains(shortcutName.lowercased())
                }) {
                    return try await shortcutsBridge.runShortcut(name: match, input: input)
                }
            } catch {
                // Fall through to error
            }
        }

        let executionTime = Date().timeIntervalSince(startTime)
        return IntentResult.failure(
            error: "No execution strategy available for intent '\(intent.name)'. Create a Shortcut named '\(intent.name)' to enable execution.",
            executionTime: executionTime
        )
    }

    private func jsonValueToDict(_ value: JSONValue) -> [String: Any] {
        guard case .object(let obj) = value else { return [:] }
        return obj.mapValues { jsonValueToAny($0) }
    }

    private func jsonValueToAny(_ value: JSONValue) -> Any {
        switch value {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let arr): return arr.map { jsonValueToAny($0) }
        case .object(let obj): return obj.mapValues { jsonValueToAny($0) }
        }
    }
}
