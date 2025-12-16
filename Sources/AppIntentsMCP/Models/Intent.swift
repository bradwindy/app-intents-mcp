import Foundation

public struct IntentParameter: Codable, Sendable, Equatable {
    public let name: String
    public let type: String
    public let description: String?
    public let required: Bool

    public init(name: String, type: String, description: String? = nil, required: Bool = true) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
    }
}

public struct DiscoveredIntent: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let appBundleID: String
    public let name: String
    public let description: String?
    public let parameters: [IntentParameter]
    public let returnsResult: Bool

    public init(
        id: String,
        appBundleID: String,
        name: String,
        description: String? = nil,
        parameters: [IntentParameter] = [],
        returnsResult: Bool = false
    ) {
        self.id = id
        self.appBundleID = appBundleID
        self.name = name
        self.description = description
        self.parameters = parameters
        self.returnsResult = returnsResult
    }
}
