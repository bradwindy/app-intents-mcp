import Foundation
import ArgumentParser

@main
struct AppIntentsMCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app-intents-mcp",
        abstract: "MCP server exposing macOS App Intents to AI assistants"
    )

    @Flag(name: .long, help: "Print version and exit")
    var version = false

    func run() async throws {
        if version {
            print("app-intents-mcp 1.0.0")
            return
        }

        let transport = StdioTransport()
        let server = MCPServer()

        // Log to stderr so it doesn't interfere with MCP protocol on stdout
        fputs("app-intents-mcp: starting server\n", stderr)

        while true {
            do {
                let request = try await transport.receive()
                let response = await server.handleRequest(request)
                try await transport.send(response)
            } catch TransportError.endOfInput {
                fputs("app-intents-mcp: client disconnected\n", stderr)
                break
            } catch {
                fputs("app-intents-mcp: error - \(error)\n", stderr)
            }
        }
    }
}
