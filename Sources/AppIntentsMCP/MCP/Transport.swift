import Foundation

public actor StdioTransport {
    private let input: FileHandle
    private let output: FileHandle
    private var buffer = Data()

    public init(input: FileHandle = .standardInput, output: FileHandle = .standardOutput) {
        self.input = input
        self.output = output
    }

    public func send(_ response: JSONRPCResponse) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(response)
        guard var json = String(data: data, encoding: .utf8) else {
            throw TransportError.encodingFailed
        }

        // Ensure JSON doesn't contain embedded newlines
        json = json.replacingOccurrences(of: "\n", with: "")
        json = json.replacingOccurrences(of: "\r", with: "")

        // Append newline for message framing
        json += "\n"

        guard let messageData = json.data(using: .utf8) else {
            throw TransportError.encodingFailed
        }
        try output.write(contentsOf: messageData)
    }

    public func receive() async throws -> JSONRPCRequest {
        // Read one line (newline-delimited JSON-RPC message)
        let line = try await readLine()

        guard let data = line.data(using: .utf8) else {
            throw TransportError.encodingFailed
        }

        let decoder = JSONDecoder()
        return try decoder.decode(JSONRPCRequest.self, from: data)
    }

    private func readLine() async throws -> String {
        var line = Data()
        while true {
            if buffer.isEmpty {
                buffer = try await readFromInput()
            }
            guard !buffer.isEmpty else {
                throw TransportError.endOfInput
            }
            let byte = buffer.removeFirst()
            if byte == UInt8(ascii: "\n") {
                // Remove trailing \r if present
                if line.last == UInt8(ascii: "\r") {
                    line.removeLast()
                }
                return String(data: line, encoding: .utf8) ?? ""
            }
            line.append(byte)
        }
    }

    private func readFromInput() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let data = try input.availableData
                continuation.resume(returning: data)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

public enum TransportError: Error {
    case encodingFailed
    case endOfInput
}
