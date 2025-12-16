import Testing
import Foundation
@testable import AppIntentsMCP

@Suite("Server Tests")
struct ServerTests {

    @Test("Server handles initialize request")
    func handleInitialize() async throws {
        let server = MCPServer()
        let request = JSONRPCRequest(
            id: .number(1),
            method: "initialize",
            params: .object([
                "protocolVersion": .string("2024-11-05"),
                "capabilities": .object([:]),
                "clientInfo": .object([
                    "name": .string("test-client"),
                    "version": .string("1.0.0")
                ])
            ])
        )

        let response = await server.handleRequest(request)

        #expect(response.id == .number(1))
        #expect(response.error == nil)
        if case .object(let result) = response.result {
            #expect(result["protocolVersion"] == .string("2024-11-05"))
            if case .object(let serverInfo) = result["serverInfo"] {
                #expect(serverInfo["name"] == .string("app-intents-mcp"))
            }
        } else {
            Issue.record("Expected object result")
        }
    }
}
