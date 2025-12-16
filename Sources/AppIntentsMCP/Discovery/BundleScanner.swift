import Foundation

public actor BundleScanner {

    public nonisolated var applicationDirectories: [String] {
        [
            "/Applications",
            "/System/Applications",
            NSHomeDirectory() + "/Applications"
        ]
    }

    public init() {}

    public func scanAllApps() async -> [DiscoveredIntent] {
        var allIntents: [DiscoveredIntent] = []

        for directory in applicationDirectories {
            let url = URL(fileURLWithPath: directory)
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            // Convert enumerator to array to avoid async iteration issues
            let allURLs = enumerator.allObjects.compactMap { $0 as? URL }

            for fileURL in allURLs {
                if fileURL.pathExtension == "app" {
                    if let intents = try? await scanBundle(at: fileURL) {
                        allIntents.append(contentsOf: intents)
                    }
                }
            }
        }

        return allIntents
    }

    public func scanBundle(at url: URL) async throws -> [DiscoveredIntent] {
        var intents: [DiscoveredIntent] = []

        // Get bundle identifier
        let infoPlistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let plistData = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String else {
            return []
        }

        let appName = plist["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent

        // Look for App Intents metadata
        // App Intents are stored in Metadata.appintents bundle
        let appIntentsURL = url.appendingPathComponent("Contents/Resources/Metadata.appintents")
        if FileManager.default.fileExists(atPath: appIntentsURL.path) {
            let discovered = try await parseAppIntentsMetadata(at: appIntentsURL, bundleID: bundleID, appName: appName)
            intents.append(contentsOf: discovered)
        }

        // Also check for legacy SiriKit intents in Info.plist
        if let intentSupported = plist["INIntentsSupported"] as? [String] {
            for intentName in intentSupported {
                intents.append(DiscoveredIntent(
                    id: "\(bundleID).\(intentName)",
                    appBundleID: bundleID,
                    name: intentName.replacingOccurrences(of: "Intent", with: "").splitCamelCase(),
                    description: "Legacy SiriKit intent from \(appName)",
                    parameters: [],
                    returnsResult: false
                ))
            }
        }

        return intents
    }

    private func parseAppIntentsMetadata(at url: URL, bundleID: String, appName: String) async throws -> [DiscoveredIntent] {
        var intents: [DiscoveredIntent] = []

        // Look for extract.actionsdata (JSON format in newer macOS)
        let actionsDataURL = url.appendingPathComponent("extract.actionsdata")
        if let data = try? Data(contentsOf: actionsDataURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let actions = json["actions"] as? [[String: Any]] {
            for action in actions {
                if let identifier = action["identifier"] as? String,
                   let title = (action["title"] as? [String: Any])?["key"] as? String {
                    let description = (action["descriptionMetadata"] as? [String: Any])?["descriptionText"] as? [String: Any]
                    let descText = description?["key"] as? String

                    intents.append(DiscoveredIntent(
                        id: identifier,
                        appBundleID: bundleID,
                        name: title,
                        description: descText ?? "App Intent from \(appName)",
                        parameters: parseParameters(from: action),
                        returnsResult: action["returnsValue"] as? Bool ?? false
                    ))
                }
            }
        }

        return intents
    }

    private func parseParameters(from action: [String: Any]) -> [IntentParameter] {
        guard let params = action["parameters"] as? [[String: Any]] else { return [] }

        return params.compactMap { param in
            guard let name = param["name"] as? String else { return nil }
            let type = param["valueType"] as? String ?? "unknown"
            let isOptional = param["isOptional"] as? Bool ?? false
            return IntentParameter(
                name: name,
                type: type,
                description: nil,
                required: !isOptional
            )
        }
    }
}

extension String {
    func splitCamelCase() -> String {
        var result = ""
        for char in self {
            if char.isUppercase && !result.isEmpty {
                result += " "
            }
            result += String(char)
        }
        return result
    }
}
