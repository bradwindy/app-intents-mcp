import Testing
import Foundation
@testable import AppIntentsMCP

@Suite("Protocol Tests")
struct ProtocolTests {

    @Test("Can parse JSON-RPC request")
    func parseRequest() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
        """
        let data = json.data(using: .utf8)!
        let request = try JSONDecoder().decode(JSONRPCRequest.self, from: data)

        #expect(request.jsonrpc == "2.0")
        #expect(request.id == .number(1))
        #expect(request.method == "initialize")
    }

    @Test("Can encode JSON-RPC response")
    func encodeResponse() throws {
        let response = JSONRPCResponse(
            id: .number(1),
            result: .object(["status": .string("ok")])
        )
        let data = try JSONEncoder().encode(response)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("\"jsonrpc\":\"2.0\""))
        #expect(json.contains("\"result\""))
    }
}
