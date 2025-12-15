import Foundation

public actor StdioTransport {
    private let input: FileHandle
    private let output: FileHandle
    private var buffer = Data()

    public init(input: FileHandle = .standardInput, output: FileHandle = .standardOutput) {
        self.input = input
        self.output = output
    }

    public static func frame(_ body: String) -> String {
        let bytes = body.utf8.count
        return "Content-Length: \(bytes)\r\n\r\n\(body)"
    }

    public func send(_ response: JSONRPCResponse) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(response)
        guard let body = String(data: data, encoding: .utf8) else {
            throw TransportError.encodingFailed
        }
        let framed = Self.frame(body)
        guard let framedData = framed.data(using: .utf8) else {
            throw TransportError.encodingFailed
        }
        try output.write(contentsOf: framedData)
    }

    public func receive() async throws -> JSONRPCRequest {
        // Read headers until we find Content-Length
        var contentLength: Int?

        while contentLength == nil {
            let line = try await readLine()
            if line.isEmpty {
                // Empty line means end of headers
                break
            }
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                contentLength = Int(value)
            }
        }

        guard let length = contentLength else {
            throw TransportError.missingContentLength
        }

        // Read body
        let body = try await readBytes(length)
        let decoder = JSONDecoder()
        return try decoder.decode(JSONRPCRequest.self, from: body)
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

    private func readBytes(_ count: Int) async throws -> Data {
        while buffer.count < count {
            let newData = try await readFromInput()
            guard !newData.isEmpty else {
                throw TransportError.endOfInput
            }
            buffer.append(newData)
        }
        let result = buffer.prefix(count)
        buffer.removeFirst(count)
        return Data(result)
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
    case missingContentLength
    case endOfInput
}
