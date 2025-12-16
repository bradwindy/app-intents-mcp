import Testing
import Foundation
@testable import AppIntentsMCP

@Suite("Transport Tests")
struct TransportTests {

    @Test("Send uses newline-delimited framing")
    func sendNewlineDelimited() async throws {
        // Create a pipe to capture output
        let pipe = Pipe()
        let transport = StdioTransport(output: pipe.fileHandleForWriting)

        // Send a response
        let result = JSONValue.object(["status": .string("ok")])
        let response = JSONRPCResponse(id: .number(1), result: result)
        try await transport.send(response)

        // Read the output
        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""

        // Should end with newline
        #expect(output.hasSuffix("\n"))

        // Should not contain Content-Length headers
        #expect(!output.contains("Content-Length"))

        // Should be valid JSON when stripped of newline
        let json = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonData = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(JSONRPCResponse.self, from: jsonData)

        // Verify it's the same response
        #expect(decoded.id == .number(1))
        #expect(decoded.result != nil)
    }

    @Test("Receive parses newline-delimited JSON-RPC request")
    func receiveNewlineDelimited() async throws {
        // Create a pipe with a JSON-RPC request
        let pipe = Pipe()
        let request = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}

        """
        pipe.fileHandleForWriting.write(request.data(using: .utf8)!)

        // Close write end so read doesn't hang
        try pipe.fileHandleForWriting.close()

        let transport = StdioTransport(input: pipe.fileHandleForReading)

        // Should parse the request
        let parsed = try await transport.receive()
        #expect(parsed.jsonrpc == "2.0")
        #expect(parsed.id == .number(1))
        #expect(parsed.method == "initialize")
    }

    @Test("Messages do not contain embedded newlines")
    func noEmbeddedNewlines() async throws {
        let pipe = Pipe()
        let transport = StdioTransport(output: pipe.fileHandleForWriting)

        // Send a response that might contain newlines in formatted JSON
        let result = JSONValue.object(["message": .string("multi\nline\ntext")])
        let response = JSONRPCResponse(id: .number(1), result: result)
        try await transport.send(response)

        let data = pipe.fileHandleForReading.availableData
        let output = String(data: data, encoding: .utf8) ?? ""

        // Count newlines - should only have the trailing one
        let newlineCount = output.filter { $0 == "\n" }.count
        #expect(newlineCount == 1)

        // Should be on a single line (excluding the trailing newline)
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 1)
    }
}
