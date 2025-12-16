import Foundation

public struct IntentResult: Codable, Sendable {
    public let success: Bool
    public let output: String?
    public let error: String?
    public let executionTime: Double

    public init(success: Bool, output: String? = nil, error: String? = nil, executionTime: Double = 0) {
        self.success = success
        self.output = output
        self.error = error
        self.executionTime = executionTime
    }

    public static func success(output: String? = nil, executionTime: Double = 0) -> IntentResult {
        IntentResult(success: true, output: output, executionTime: executionTime)
    }

    public static func failure(error: String, executionTime: Double = 0) -> IntentResult {
        IntentResult(success: false, error: error, executionTime: executionTime)
    }
}
