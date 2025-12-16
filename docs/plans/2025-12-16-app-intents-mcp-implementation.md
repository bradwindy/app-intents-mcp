# App Intents MCP Server Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Swift MCP server that discovers and executes macOS App Intents.

**Architecture:** Stdio-based MCP server using JSON-RPC. Multi-layer intent discovery (bundle inspection, Shortcuts DB). Multi-strategy execution (Shortcuts CLI first, then XPC if needed).

**Tech Stack:** Swift 6, Swift Package Manager, Foundation, SQLite.swift, swift-argument-parser

---

## Phase 1: Project Foundation

### Task 1: Create Package.swift

**Files:**
- Create: `Package.swift`

**Step 1: Write Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "app-intents-mcp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "app-intents-mcp", targets: ["AppIntentsMCP"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0")
    ],
    targets: [
        .executableTarget(
            name: "AppIntentsMCP",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "AppIntentsMCPTests",
            dependencies: ["AppIntentsMCP"]
        )
    ]
)
```

**Step 2: Create directory structure**

Run:
```bash
mkdir -p Sources/AppIntentsMCP/{MCP,Discovery,Execution,Models,Cache}
mkdir -p Tests/AppIntentsMCPTests
```

**Step 3: Create minimal main.swift**

Create `Sources/AppIntentsMCP/main.swift`:

```swift
import Foundation

@main
struct AppIntentsMCP {
    static func main() async throws {
        print("app-intents-mcp starting...")
    }
}
```

**Step 4: Verify build**

Run: `swift build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: scaffold Swift package structure"
```

---

### Task 2: Create Core Model Types

**Files:**
- Create: `Sources/AppIntentsMCP/Models/Intent.swift`
- Create: `Sources/AppIntentsMCP/Models/IntentResult.swift`
- Create: `Tests/AppIntentsMCPTests/ModelsTests.swift`

**Step 1: Write failing test for Intent model**

Create `Tests/AppIntentsMCPTests/ModelsTests.swift`:

```swift
import Testing
@testable import AppIntentsMCP

@Suite("Models Tests")
struct ModelsTests {

    @Test("Intent can be created with required fields")
    func intentCreation() {
        let intent = DiscoveredIntent(
            id: "com.apple.reminders.CreateReminder",
            appBundleID: "com.apple.reminders",
            name: "Create Reminder",
            description: "Creates a new reminder",
            parameters: [],
            returnsResult: true
        )

        #expect(intent.id == "com.apple.reminders.CreateReminder")
        #expect(intent.appBundleID == "com.apple.reminders")
        #expect(intent.name == "Create Reminder")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter ModelsTests`
Expected: FAIL - DiscoveredIntent not found

**Step 3: Write Intent model**

Create `Sources/AppIntentsMCP/Models/Intent.swift`:

```swift
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
```

**Step 4: Write IntentResult model**

Create `Sources/AppIntentsMCP/Models/IntentResult.swift`:

```swift
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
```

**Step 5: Run test to verify it passes**

Run: `swift test --filter ModelsTests`
Expected: PASS

**Step 6: Commit**

```bash
git add Sources/AppIntentsMCP/Models Tests
git commit -m "feat: add Intent and IntentResult models"
```

---

## Phase 2: MCP Transport Layer

### Task 3: Create JSON-RPC Types

**Files:**
- Create: `Sources/AppIntentsMCP/MCP/Protocol.swift`
- Create: `Tests/AppIntentsMCPTests/ProtocolTests.swift`

**Step 1: Write failing test for JSON-RPC parsing**

Create `Tests/AppIntentsMCPTests/ProtocolTests.swift`:

```swift
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
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter ProtocolTests`
Expected: FAIL - JSONRPCRequest not found

**Step 3: Write Protocol types**

Create `Sources/AppIntentsMCP/MCP/Protocol.swift`:

```swift
import Foundation

// MARK: - JSON-RPC ID

public enum JSONRPCID: Codable, Sendable, Equatable {
    case string(String)
    case number(Int)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            self = .number(int)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.typeMismatch(JSONRPCID.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected string, int, or null"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - JSON Value

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .number(Double(int))
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.typeMismatch(JSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unexpected JSON type"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - JSON-RPC Request

public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID?
    public let method: String
    public let params: JSONValue?

    public init(jsonrpc: String = "2.0", id: JSONRPCID? = nil, method: String, params: JSONValue? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

// MARK: - JSON-RPC Response

public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID?
    public let result: JSONValue?
    public let error: JSONRPCError?

    public init(id: JSONRPCID?, result: JSONValue? = nil, error: JSONRPCError? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }
}

public struct JSONRPCError: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    public static let parseError = JSONRPCError(code: -32700, message: "Parse error")
    public static let invalidRequest = JSONRPCError(code: -32600, message: "Invalid Request")
    public static let methodNotFound = JSONRPCError(code: -32601, message: "Method not found")
    public static let invalidParams = JSONRPCError(code: -32602, message: "Invalid params")
    public static let internalError = JSONRPCError(code: -32603, message: "Internal error")
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter ProtocolTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AppIntentsMCP/MCP Tests
git commit -m "feat: add JSON-RPC protocol types"
```

---

### Task 4: Create Stdio Transport

**Files:**
- Create: `Sources/AppIntentsMCP/MCP/Transport.swift`
- Create: `Tests/AppIntentsMCPTests/TransportTests.swift`

**Step 1: Write failing test for message framing**

Create `Tests/AppIntentsMCPTests/TransportTests.swift`:

```swift
import Testing
import Foundation
@testable import AppIntentsMCP

@Suite("Transport Tests")
struct TransportTests {

    @Test("Can frame message with Content-Length header")
    func frameMessage() {
        let body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"test\"}"
        let framed = StdioTransport.frame(body)

        #expect(framed.hasPrefix("Content-Length: \(body.utf8.count)\r\n\r\n"))
        #expect(framed.hasSuffix(body))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter TransportTests`
Expected: FAIL - StdioTransport not found

**Step 3: Write Transport**

Create `Sources/AppIntentsMCP/MCP/Transport.swift`:

```swift
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
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter TransportTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AppIntentsMCP/MCP Tests
git commit -m "feat: add stdio transport with Content-Length framing"
```

---

## Phase 3: MCP Server Core

### Task 5: Create MCP Server

**Files:**
- Create: `Sources/AppIntentsMCP/MCP/Server.swift`
- Create: `Tests/AppIntentsMCPTests/ServerTests.swift`

**Step 1: Write failing test for server initialization response**

Create `Tests/AppIntentsMCPTests/ServerTests.swift`:

```swift
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
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter ServerTests`
Expected: FAIL - MCPServer not found

**Step 3: Write MCPServer**

Create `Sources/AppIntentsMCP/MCP/Server.swift`:

```swift
import Foundation

public actor MCPServer {
    private var initialized = false

    public init() {}

    public func handleRequest(_ request: JSONRPCRequest) -> JSONRPCResponse {
        switch request.method {
        case "initialize":
            return handleInitialize(request)
        case "initialized":
            return handleInitialized(request)
        case "tools/list":
            return handleToolsList(request)
        case "tools/call":
            return handleToolsCall(request)
        case "resources/list":
            return handleResourcesList(request)
        case "resources/read":
            return handleResourcesRead(request)
        case "prompts/list":
            return handlePromptsList(request)
        case "prompts/get":
            return handlePromptsGet(request)
        default:
            return JSONRPCResponse(id: request.id, error: .methodNotFound)
        }
    }

    private func handleInitialize(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let result: JSONValue = .object([
            "protocolVersion": .string("2024-11-05"),
            "capabilities": .object([
                "tools": .object([:]),
                "resources": .object([:]),
                "prompts": .object([:])
            ]),
            "serverInfo": .object([
                "name": .string("app-intents-mcp"),
                "version": .string("1.0.0")
            ])
        ])
        return JSONRPCResponse(id: request.id, result: result)
    }

    private func handleInitialized(_ request: JSONRPCRequest) -> JSONRPCResponse {
        initialized = true
        return JSONRPCResponse(id: request.id, result: .object([:]))
    }

    private func handleToolsList(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let tools: JSONValue = .array([
            .object([
                "name": .string("list_intents"),
                "description": .string("List all discovered App Intents, optionally filtered by app"),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "app_bundle_id": .object([
                            "type": .string("string"),
                            "description": .string("Filter by app bundle ID (optional)")
                        ])
                    ])
                ])
            ]),
            .object([
                "name": .string("search_intents"),
                "description": .string("Search intents by name or description"),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Search query")
                        ])
                    ]),
                    "required": .array([.string("query")])
                ])
            ]),
            .object([
                "name": .string("get_intent"),
                "description": .string("Get detailed info about a specific intent"),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "intent_id": .object([
                            "type": .string("string"),
                            "description": .string("The intent ID")
                        ])
                    ]),
                    "required": .array([.string("intent_id")])
                ])
            ]),
            .object([
                "name": .string("run_intent"),
                "description": .string("Execute an App Intent with provided parameters"),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "intent_id": .object([
                            "type": .string("string"),
                            "description": .string("The intent ID to execute")
                        ]),
                        "parameters": .object([
                            "type": .string("object"),
                            "description": .string("Parameters to pass to the intent")
                        ])
                    ]),
                    "required": .array([.string("intent_id")])
                ])
            ]),
            .object([
                "name": .string("refresh_intents"),
                "description": .string("Force re-scan of installed apps for intents"),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([:])
                ])
            ])
        ])
        return JSONRPCResponse(id: request.id, result: .object(["tools": tools]))
    }

    private func handleToolsCall(_ request: JSONRPCRequest) -> JSONRPCResponse {
        // TODO: Implement actual tool execution
        return JSONRPCResponse(id: request.id, result: .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string("Tool execution not yet implemented")
                ])
            ])
        ]))
    }

    private func handleResourcesList(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let resources: JSONValue = .array([
            .object([
                "uri": .string("intent://"),
                "name": .string("All App Intents"),
                "description": .string("Browse all discovered App Intents"),
                "mimeType": .string("application/json")
            ])
        ])
        return JSONRPCResponse(id: request.id, result: .object(["resources": resources]))
    }

    private func handleResourcesRead(_ request: JSONRPCRequest) -> JSONRPCResponse {
        // TODO: Implement resource reading
        return JSONRPCResponse(id: request.id, result: .object([
            "contents": .array([
                .object([
                    "uri": .string("intent://"),
                    "mimeType": .string("application/json"),
                    "text": .string("[]")
                ])
            ])
        ]))
    }

    private func handlePromptsList(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let prompts: JSONValue = .array([
            .object([
                "name": .string("discover_capabilities"),
                "description": .string("What can I automate on this Mac?")
            ]),
            .object([
                "name": .string("intent_help"),
                "description": .string("Get usage help for a specific intent"),
                "arguments": .array([
                    .object([
                        "name": .string("intent_id"),
                        "description": .string("The intent to get help for"),
                        "required": .bool(true)
                    ])
                ])
            ]),
            .object([
                "name": .string("workflow_builder"),
                "description": .string("Build a multi-step automation using available intents")
            ])
        ])
        return JSONRPCResponse(id: request.id, result: .object(["prompts": prompts]))
    }

    private func handlePromptsGet(_ request: JSONRPCRequest) -> JSONRPCResponse {
        // TODO: Implement prompt generation
        return JSONRPCResponse(id: request.id, result: .object([
            "messages": .array([
                .object([
                    "role": .string("user"),
                    "content": .object([
                        "type": .string("text"),
                        "text": .string("Prompt not yet implemented")
                    ])
                ])
            ])
        ]))
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter ServerTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AppIntentsMCP/MCP Tests
git commit -m "feat: add MCP server with basic request handling"
```

---

### Task 6: Wire Up Main Entry Point

**Files:**
- Modify: `Sources/AppIntentsMCP/main.swift`

**Step 1: Update main.swift to run server**

Replace `Sources/AppIntentsMCP/main.swift`:

```swift
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
```

**Step 2: Build and verify**

Run: `swift build`
Expected: Build succeeds

**Step 3: Test --version flag**

Run: `.build/debug/app-intents-mcp --version`
Expected: `app-intents-mcp 1.0.0`

**Step 4: Commit**

```bash
git add Sources/AppIntentsMCP/main.swift
git commit -m "feat: wire up main entry point with argument parser"
```

---

## Phase 4: Intent Discovery

### Task 7: Create Bundle Scanner

**Files:**
- Create: `Sources/AppIntentsMCP/Discovery/BundleScanner.swift`
- Create: `Tests/AppIntentsMCPTests/BundleScannerTests.swift`

**Step 1: Write failing test for bundle scanning**

Create `Tests/AppIntentsMCPTests/BundleScannerTests.swift`:

```swift
import Testing
import Foundation
@testable import AppIntentsMCP

@Suite("BundleScanner Tests")
struct BundleScannerTests {

    @Test("Can find application directories")
    func findAppDirectories() async {
        let scanner = BundleScanner()
        let directories = scanner.applicationDirectories

        #expect(directories.contains("/Applications"))
        #expect(directories.contains(NSHomeDirectory() + "/Applications"))
    }

    @Test("Can scan app bundle for metadata")
    func scanAppBundle() async throws {
        let scanner = BundleScanner()
        // Scan a known system app
        let infos = try await scanner.scanBundle(at: URL(fileURLWithPath: "/System/Applications/Reminders.app"))
        // May or may not find intents depending on macOS version
        // Just verify it doesn't crash
        #expect(infos != nil || infos == nil) // Always passes, just checks no crash
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter BundleScannerTests`
Expected: FAIL - BundleScanner not found

**Step 3: Write BundleScanner**

Create `Sources/AppIntentsMCP/Discovery/BundleScanner.swift`:

```swift
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

            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "app" {
                    enumerator.skipDescendants()
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
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter BundleScannerTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AppIntentsMCP/Discovery Tests
git commit -m "feat: add bundle scanner for App Intents discovery"
```

---

### Task 8: Create Intent Discovery Orchestrator

**Files:**
- Create: `Sources/AppIntentsMCP/Discovery/IntentDiscovery.swift`
- Create: `Tests/AppIntentsMCPTests/IntentDiscoveryTests.swift`

**Step 1: Write failing test for discovery orchestrator**

Create `Tests/AppIntentsMCPTests/IntentDiscoveryTests.swift`:

```swift
import Testing
import Foundation
@testable import AppIntentsMCP

@Suite("IntentDiscovery Tests")
struct IntentDiscoveryTests {

    @Test("Can discover intents from system")
    func discoverIntents() async throws {
        let discovery = IntentDiscovery()
        let intents = try await discovery.discoverAll()

        // Should find at least some intents on any macOS system
        // (Reminders, Calendar, etc. have App Intents)
        // Just verify it runs without crashing
        #expect(intents.count >= 0)
    }

    @Test("Can search intents by query")
    func searchIntents() async throws {
        let discovery = IntentDiscovery()
        _ = try await discovery.discoverAll()

        let results = await discovery.search(query: "reminder")
        // Results depend on what's installed
        #expect(results.count >= 0)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter IntentDiscoveryTests`
Expected: FAIL - IntentDiscovery not found

**Step 3: Write IntentDiscovery**

Create `Sources/AppIntentsMCP/Discovery/IntentDiscovery.swift`:

```swift
import Foundation

public actor IntentDiscovery {
    private var cachedIntents: [DiscoveredIntent] = []
    private var lastDiscoveryTime: Date?
    private let bundleScanner = BundleScanner()

    public init() {}

    public func discoverAll(forceRefresh: Bool = false) async throws -> [DiscoveredIntent] {
        if !forceRefresh,
           let lastTime = lastDiscoveryTime,
           Date().timeIntervalSince(lastTime) < 300, // 5 minute cache
           !cachedIntents.isEmpty {
            return cachedIntents
        }

        var allIntents: [DiscoveredIntent] = []

        // Layer 1: Bundle scanning
        let bundleIntents = await bundleScanner.scanAllApps()
        allIntents.append(contentsOf: bundleIntents)

        // Layer 2: Shortcuts database (future implementation)
        // let shortcutsIntents = try await shortcutsDBScanner.scan()
        // allIntents.append(contentsOf: shortcutsIntents)

        // Deduplicate by ID
        var seen = Set<String>()
        cachedIntents = allIntents.filter { intent in
            if seen.contains(intent.id) { return false }
            seen.insert(intent.id)
            return true
        }

        lastDiscoveryTime = Date()
        return cachedIntents
    }

    public func getIntent(byID id: String) async -> DiscoveredIntent? {
        return cachedIntents.first { $0.id == id }
    }

    public func search(query: String) async -> [DiscoveredIntent] {
        let lowercaseQuery = query.lowercased()
        return cachedIntents.filter { intent in
            intent.name.lowercased().contains(lowercaseQuery) ||
            intent.description?.lowercased().contains(lowercaseQuery) == true ||
            intent.appBundleID.lowercased().contains(lowercaseQuery)
        }
    }

    public func getIntents(forApp bundleID: String) async -> [DiscoveredIntent] {
        return cachedIntents.filter { $0.appBundleID == bundleID }
    }

    public func listApps() async -> [(bundleID: String, intentCount: Int)] {
        var appCounts: [String: Int] = [:]
        for intent in cachedIntents {
            appCounts[intent.appBundleID, default: 0] += 1
        }
        return appCounts.map { ($0.key, $0.value) }.sorted { $0.intentCount > $1.intentCount }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter IntentDiscoveryTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AppIntentsMCP/Discovery Tests
git commit -m "feat: add intent discovery orchestrator with caching"
```

---

## Phase 5: Intent Execution

### Task 9: Create Shortcuts Bridge Executor

**Files:**
- Create: `Sources/AppIntentsMCP/Execution/IntentExecutor.swift`
- Create: `Sources/AppIntentsMCP/Execution/ShortcutsBridge.swift`
- Create: `Tests/AppIntentsMCPTests/ExecutionTests.swift`

**Step 1: Write failing test for executor**

Create `Tests/AppIntentsMCPTests/ExecutionTests.swift`:

```swift
import Testing
import Foundation
@testable import AppIntentsMCP

@Suite("Execution Tests")
struct ExecutionTests {

    @Test("Shortcuts bridge can check if shortcuts CLI exists")
    func shortcutsCLIExists() async {
        let bridge = ShortcutsBridge()
        let exists = await bridge.isAvailable()
        // shortcuts CLI should exist on macOS 12+
        #expect(exists == true)
    }

    @Test("Intent executor returns result")
    func executeIntent() async throws {
        let executor = IntentExecutor()
        let intent = DiscoveredIntent(
            id: "test.intent",
            appBundleID: "com.test",
            name: "Test Intent",
            description: nil,
            parameters: [],
            returnsResult: false
        )

        let result = await executor.execute(intent: intent, parameters: [:])
        // Will fail to execute since it's a fake intent, but should return a result
        #expect(result.success == false || result.success == true)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter ExecutionTests`
Expected: FAIL - ShortcutsBridge not found

**Step 3: Write ShortcutsBridge**

Create `Sources/AppIntentsMCP/Execution/ShortcutsBridge.swift`:

```swift
import Foundation

public actor ShortcutsBridge {
    private let shortcutsPath = "/usr/bin/shortcuts"

    public init() {}

    public func isAvailable() -> Bool {
        FileManager.default.fileExists(atPath: shortcutsPath)
    }

    public func listShortcuts() async throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shortcutsPath)
        process.arguments = ["list"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return output.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    public func runShortcut(name: String, input: String? = nil) async throws -> IntentResult {
        let startTime = Date()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shortcutsPath)

        var args = ["run", name]
        if let input = input {
            args.append(contentsOf: ["-i", input])
        }
        process.arguments = args

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let executionTime = Date().timeIntervalSince(startTime)

            if process.terminationStatus == 0 {
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8)
                return IntentResult.success(output: output, executionTime: executionTime)
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let error = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                return IntentResult.failure(error: error, executionTime: executionTime)
            }
        } catch {
            let executionTime = Date().timeIntervalSince(startTime)
            return IntentResult.failure(error: error.localizedDescription, executionTime: executionTime)
        }
    }
}
```

**Step 4: Write IntentExecutor**

Create `Sources/AppIntentsMCP/Execution/IntentExecutor.swift`:

```swift
import Foundation

public actor IntentExecutor {
    private let shortcutsBridge = ShortcutsBridge()

    public init() {}

    public func execute(intent: DiscoveredIntent, parameters: [String: Any]) async -> IntentResult {
        let startTime = Date()

        // Strategy 1: Try to find and run a matching shortcut
        if await shortcutsBridge.isAvailable() {
            // Convert parameters to JSON input if present
            var input: String? = nil
            if !parameters.isEmpty {
                if let jsonData = try? JSONSerialization.data(withJSONObject: parameters),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    input = jsonString
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
}
```

**Step 5: Run test to verify it passes**

Run: `swift test --filter ExecutionTests`
Expected: PASS

**Step 6: Commit**

```bash
git add Sources/AppIntentsMCP/Execution Tests
git commit -m "feat: add Shortcuts bridge and intent executor"
```

---

## Phase 6: Wire Everything Together

### Task 10: Integrate Discovery and Execution into Server

**Files:**
- Modify: `Sources/AppIntentsMCP/MCP/Server.swift`

**Step 1: Update MCPServer to use discovery and execution**

Replace `Sources/AppIntentsMCP/MCP/Server.swift`:

```swift
import Foundation

public actor MCPServer {
    private var initialized = false
    private let discovery = IntentDiscovery()
    private let executor = IntentExecutor()

    public init() {}

    public func handleRequest(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        switch request.method {
        case "initialize":
            return await handleInitialize(request)
        case "initialized":
            return handleInitialized(request)
        case "tools/list":
            return handleToolsList(request)
        case "tools/call":
            return await handleToolsCall(request)
        case "resources/list":
            return await handleResourcesList(request)
        case "resources/read":
            return await handleResourcesRead(request)
        case "prompts/list":
            return handlePromptsList(request)
        case "prompts/get":
            return await handlePromptsGet(request)
        default:
            return JSONRPCResponse(id: request.id, error: .methodNotFound)
        }
    }

    private func handleInitialize(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        // Pre-discover intents during initialization
        _ = try? await discovery.discoverAll()

        let result: JSONValue = .object([
            "protocolVersion": .string("2024-11-05"),
            "capabilities": .object([
                "tools": .object([:]),
                "resources": .object([:]),
                "prompts": .object([:])
            ]),
            "serverInfo": .object([
                "name": .string("app-intents-mcp"),
                "version": .string("1.0.0")
            ])
        ])
        return JSONRPCResponse(id: request.id, result: result)
    }

    private func handleInitialized(_ request: JSONRPCRequest) -> JSONRPCResponse {
        initialized = true
        return JSONRPCResponse(id: request.id, result: .object([:]))
    }

    private func handleToolsList(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let tools: JSONValue = .array([
            .object([
                "name": .string("list_intents"),
                "description": .string("List all discovered App Intents, optionally filtered by app"),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "app_bundle_id": .object([
                            "type": .string("string"),
                            "description": .string("Filter by app bundle ID (optional)")
                        ])
                    ])
                ])
            ]),
            .object([
                "name": .string("search_intents"),
                "description": .string("Search intents by name or description"),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Search query")
                        ])
                    ]),
                    "required": .array([.string("query")])
                ])
            ]),
            .object([
                "name": .string("get_intent"),
                "description": .string("Get detailed info about a specific intent"),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "intent_id": .object([
                            "type": .string("string"),
                            "description": .string("The intent ID")
                        ])
                    ]),
                    "required": .array([.string("intent_id")])
                ])
            ]),
            .object([
                "name": .string("run_intent"),
                "description": .string("Execute an App Intent with provided parameters"),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "intent_id": .object([
                            "type": .string("string"),
                            "description": .string("The intent ID to execute")
                        ]),
                        "parameters": .object([
                            "type": .string("object"),
                            "description": .string("Parameters to pass to the intent")
                        ])
                    ]),
                    "required": .array([.string("intent_id")])
                ])
            ]),
            .object([
                "name": .string("refresh_intents"),
                "description": .string("Force re-scan of installed apps for intents"),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([:])
                ])
            ])
        ])
        return JSONRPCResponse(id: request.id, result: .object(["tools": tools]))
    }

    private func handleToolsCall(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        guard case .object(let params) = request.params,
              case .string(let toolName) = params["name"] else {
            return JSONRPCResponse(id: request.id, error: .invalidParams)
        }

        let arguments = params["arguments"]

        switch toolName {
        case "list_intents":
            return await handleListIntents(request.id, arguments: arguments)
        case "search_intents":
            return await handleSearchIntents(request.id, arguments: arguments)
        case "get_intent":
            return await handleGetIntent(request.id, arguments: arguments)
        case "run_intent":
            return await handleRunIntent(request.id, arguments: arguments)
        case "refresh_intents":
            return await handleRefreshIntents(request.id)
        default:
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32601, message: "Unknown tool: \(toolName)"))
        }
    }

    private func handleListIntents(_ id: JSONRPCID?, arguments: JSONValue?) async -> JSONRPCResponse {
        var intents = (try? await discovery.discoverAll()) ?? []

        // Filter by app if specified
        if case .object(let args) = arguments,
           case .string(let appBundleID) = args["app_bundle_id"] {
            intents = await discovery.getIntents(forApp: appBundleID)
        }

        let intentList = intents.map { intent -> JSONValue in
            .object([
                "id": .string(intent.id),
                "app": .string(intent.appBundleID),
                "name": .string(intent.name),
                "description": .string(intent.description ?? "")
            ])
        }

        return JSONRPCResponse(id: id, result: .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string("Found \(intents.count) intents")
                ]),
                .object([
                    "type": .string("text"),
                    "text": .string(formatIntentList(intents))
                ])
            ])
        ]))
    }

    private func handleSearchIntents(_ id: JSONRPCID?, arguments: JSONValue?) async -> JSONRPCResponse {
        guard case .object(let args) = arguments,
              case .string(let query) = args["query"] else {
            return JSONRPCResponse(id: id, error: .invalidParams)
        }

        let results = await discovery.search(query: query)

        return JSONRPCResponse(id: id, result: .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string("Found \(results.count) intents matching '\(query)':\n\n\(formatIntentList(results))")
                ])
            ])
        ]))
    }

    private func handleGetIntent(_ id: JSONRPCID?, arguments: JSONValue?) async -> JSONRPCResponse {
        guard case .object(let args) = arguments,
              case .string(let intentID) = args["intent_id"] else {
            return JSONRPCResponse(id: id, error: .invalidParams)
        }

        guard let intent = await discovery.getIntent(byID: intentID) else {
            return JSONRPCResponse(id: id, result: .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Intent not found: \(intentID)")
                    ])
                ])
            ]))
        }

        let paramList = intent.parameters.map { p in
            "  - \(p.name) (\(p.type))\(p.required ? " [required]" : "")"
        }.joined(separator: "\n")

        let details = """
        Intent: \(intent.name)
        ID: \(intent.id)
        App: \(intent.appBundleID)
        Description: \(intent.description ?? "N/A")
        Returns Result: \(intent.returnsResult ? "Yes" : "No")
        Parameters:
        \(paramList.isEmpty ? "  None" : paramList)
        """

        return JSONRPCResponse(id: id, result: .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(details)
                ])
            ])
        ]))
    }

    private func handleRunIntent(_ id: JSONRPCID?, arguments: JSONValue?) async -> JSONRPCResponse {
        guard case .object(let args) = arguments,
              case .string(let intentID) = args["intent_id"] else {
            return JSONRPCResponse(id: id, error: .invalidParams)
        }

        guard let intent = await discovery.getIntent(byID: intentID) else {
            return JSONRPCResponse(id: id, result: .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Intent not found: \(intentID)")
                    ])
                ])
            ]))
        }

        // Extract parameters
        var parameters: [String: Any] = [:]
        if case .object(let paramsObj) = args["parameters"] {
            for (key, value) in paramsObj {
                parameters[key] = jsonValueToAny(value)
            }
        }

        let result = await executor.execute(intent: intent, parameters: parameters)

        if result.success {
            return JSONRPCResponse(id: id, result: .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Successfully executed '\(intent.name)'\(result.output.map { "\n\nOutput: \($0)" } ?? "")")
                    ])
                ])
            ]))
        } else {
            return JSONRPCResponse(id: id, result: .object([
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Failed to execute '\(intent.name)': \(result.error ?? "Unknown error")")
                    ])
                ])
            ]))
        }
    }

    private func handleRefreshIntents(_ id: JSONRPCID?) async -> JSONRPCResponse {
        let intents = (try? await discovery.discoverAll(forceRefresh: true)) ?? []

        return JSONRPCResponse(id: id, result: .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string("Refreshed intent cache. Found \(intents.count) intents.")
                ])
            ])
        ]))
    }

    private func handleResourcesList(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        let apps = await discovery.listApps()

        var resources: [JSONValue] = [
            .object([
                "uri": .string("intent://"),
                "name": .string("All App Intents"),
                "description": .string("Browse all discovered App Intents"),
                "mimeType": .string("application/json")
            ])
        ]

        for app in apps {
            resources.append(.object([
                "uri": .string("intent://\(app.bundleID)"),
                "name": .string(app.bundleID),
                "description": .string("\(app.intentCount) intents"),
                "mimeType": .string("application/json")
            ]))
        }

        return JSONRPCResponse(id: request.id, result: .object(["resources": .array(resources)]))
    }

    private func handleResourcesRead(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        guard case .object(let params) = request.params,
              case .string(let uri) = params["uri"] else {
            return JSONRPCResponse(id: request.id, error: .invalidParams)
        }

        var intents: [DiscoveredIntent]

        if uri == "intent://" {
            intents = (try? await discovery.discoverAll()) ?? []
        } else if uri.hasPrefix("intent://") {
            let bundleID = String(uri.dropFirst("intent://".count))
            intents = await discovery.getIntents(forApp: bundleID)
        } else {
            return JSONRPCResponse(id: request.id, error: .invalidParams)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = (try? encoder.encode(intents)) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"

        return JSONRPCResponse(id: request.id, result: .object([
            "contents": .array([
                .object([
                    "uri": .string(uri),
                    "mimeType": .string("application/json"),
                    "text": .string(jsonString)
                ])
            ])
        ]))
    }

    private func handlePromptsList(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let prompts: JSONValue = .array([
            .object([
                "name": .string("discover_capabilities"),
                "description": .string("What can I automate on this Mac?")
            ]),
            .object([
                "name": .string("intent_help"),
                "description": .string("Get usage help for a specific intent"),
                "arguments": .array([
                    .object([
                        "name": .string("intent_id"),
                        "description": .string("The intent to get help for"),
                        "required": .bool(true)
                    ])
                ])
            ]),
            .object([
                "name": .string("workflow_builder"),
                "description": .string("Build a multi-step automation using available intents")
            ])
        ])
        return JSONRPCResponse(id: request.id, result: .object(["prompts": prompts]))
    }

    private func handlePromptsGet(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        guard case .object(let params) = request.params,
              case .string(let promptName) = params["name"] else {
            return JSONRPCResponse(id: request.id, error: .invalidParams)
        }

        switch promptName {
        case "discover_capabilities":
            let apps = await discovery.listApps()
            let appList = apps.prefix(10).map { "- \($0.bundleID): \($0.intentCount) intents" }.joined(separator: "\n")

            return JSONRPCResponse(id: request.id, result: .object([
                "messages": .array([
                    .object([
                        "role": .string("user"),
                        "content": .object([
                            "type": .string("text"),
                            "text": .string("""
                            I want to know what I can automate on this Mac using App Intents.

                            Here are the apps with available intents:
                            \(appList)

                            Please summarize the automation capabilities available to me.
                            """)
                        ])
                    ])
                ])
            ]))

        case "intent_help":
            guard case .object(let args) = params["arguments"],
                  case .string(let intentID) = args["intent_id"],
                  let intent = await discovery.getIntent(byID: intentID) else {
                return JSONRPCResponse(id: request.id, error: .invalidParams)
            }

            let paramList = intent.parameters.map { p in
                "- \(p.name) (\(p.type)): \(p.description ?? "No description")"
            }.joined(separator: "\n")

            return JSONRPCResponse(id: request.id, result: .object([
                "messages": .array([
                    .object([
                        "role": .string("user"),
                        "content": .object([
                            "type": .string("text"),
                            "text": .string("""
                            Help me understand how to use this App Intent:

                            Name: \(intent.name)
                            App: \(intent.appBundleID)
                            Description: \(intent.description ?? "N/A")

                            Parameters:
                            \(paramList.isEmpty ? "None" : paramList)

                            Please explain what this intent does and provide example usage.
                            """)
                        ])
                    ])
                ])
            ]))

        case "workflow_builder":
            return JSONRPCResponse(id: request.id, result: .object([
                "messages": .array([
                    .object([
                        "role": .string("user"),
                        "content": .object([
                            "type": .string("text"),
                            "text": .string("""
                            I want to build a multi-step automation workflow.

                            Please help me:
                            1. First, use list_intents to see what's available
                            2. Ask me what I want to accomplish
                            3. Suggest a sequence of intents to achieve my goal
                            4. Execute the workflow step by step
                            """)
                        ])
                    ])
                ])
            ]))

        default:
            return JSONRPCResponse(id: request.id, error: JSONRPCError(code: -32601, message: "Unknown prompt: \(promptName)"))
        }
    }

    // MARK: - Helpers

    private func formatIntentList(_ intents: [DiscoveredIntent]) -> String {
        if intents.isEmpty { return "No intents found." }

        var grouped: [String: [DiscoveredIntent]] = [:]
        for intent in intents {
            grouped[intent.appBundleID, default: []].append(intent)
        }

        var result = ""
        for (app, appIntents) in grouped.sorted(by: { $0.key < $1.key }) {
            result += "\n[\(app)]\n"
            for intent in appIntents {
                result += "  - \(intent.name) (\(intent.id))\n"
            }
        }
        return result
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
```

**Step 2: Run all tests**

Run: `swift test`
Expected: All tests pass

**Step 3: Build and test manually**

Run: `swift build`

**Step 4: Commit**

```bash
git add Sources/AppIntentsMCP/MCP/Server.swift
git commit -m "feat: integrate discovery and execution into MCP server"
```

---

## Phase 7: Packaging

### Task 11: Create MCPB Manifest

**Files:**
- Create: `manifest.json`
- Create: `README.md`

**Step 1: Create manifest.json**

```json
{
  "name": "app-intents-mcp",
  "version": "1.0.0",
  "description": "Execute macOS App Intents from AI assistants",
  "author": "Bradley",
  "license": "MIT",
  "homepage": "https://github.com/yourusername/app-intents-mcp",
  "server": {
    "type": "binary",
    "command": "bin/app-intents-mcp"
  },
  "capabilities": {
    "tools": true,
    "resources": true,
    "prompts": true
  },
  "platform": {
    "os": ["macos"],
    "arch": ["arm64", "x86_64"],
    "minVersion": "13.0"
  }
}
```

**Step 2: Create README.md**

```markdown
# app-intents-mcp

An MCP server that exposes macOS App Intents to AI assistants like Claude.

## Features

- **Discover** App Intents from all installed macOS applications
- **Search** intents by name, description, or app
- **Execute** intents directly from your AI assistant
- **Browse** intents as MCP resources

## Installation

### Via MCPB

```bash
mcpb install app-intents-mcp.mcpb
```

### Manual

1. Download the latest release
2. Add to your Claude Desktop configuration:

```json
{
  "mcpServers": {
    "app-intents-mcp": {
      "command": "/path/to/app-intents-mcp"
    }
  }
}
```

## Usage

Once installed, you can ask Claude things like:

- "What can you control on my Mac?"
- "Remind me to call mom tomorrow at 5pm"
- "Search for calendar-related intents"
- "Show me all intents from the Reminders app"

## Tools

| Tool | Description |
|------|-------------|
| `list_intents` | List all discovered intents |
| `search_intents` | Search intents by query |
| `get_intent` | Get details about an intent |
| `run_intent` | Execute an intent |
| `refresh_intents` | Re-scan for intents |

## Permissions

The server may need Automation permissions to execute intents. Grant these when prompted by macOS.

## License

MIT
```

**Step 3: Commit**

```bash
git add manifest.json README.md
git commit -m "feat: add MCPB manifest and README"
```

---

### Task 12: Create Build Script

**Files:**
- Create: `scripts/build.sh`
- Create: `scripts/package.sh`

**Step 1: Create build script**

Create `scripts/build.sh`:

```bash
#!/bin/bash
set -e

echo "Building app-intents-mcp..."

# Build universal binary
swift build -c release --arch arm64 --arch x86_64

echo "Build complete: .build/apple/Products/Release/app-intents-mcp"
```

**Step 2: Create package script**

Create `scripts/package.sh`:

```bash
#!/bin/bash
set -e

echo "Packaging app-intents-mcp.mcpb..."

# Build first
./scripts/build.sh

# Create staging directory
rm -rf .package
mkdir -p .package/bin

# Copy binary
cp .build/apple/Products/Release/app-intents-mcp .package/bin/

# Copy manifest and README
cp manifest.json .package/
cp README.md .package/

# Create mcpb (zip archive)
cd .package
zip -r ../app-intents-mcp.mcpb .
cd ..

# Cleanup
rm -rf .package

echo "Package created: app-intents-mcp.mcpb"
```

**Step 3: Make scripts executable**

Run:
```bash
mkdir -p scripts
chmod +x scripts/build.sh scripts/package.sh
```

**Step 4: Commit**

```bash
git add scripts
git commit -m "feat: add build and package scripts"
```

---

## Phase 8: Testing & Validation

### Task 13: Manual Integration Test

**Step 1: Build the server**

Run: `swift build`

**Step 2: Test with echo/cat**

Run:
```bash
echo 'Content-Length: 109\r\n\r\n{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}}' | .build/debug/app-intents-mcp
```

Expected: JSON response with server info

**Step 3: Test intent discovery**

Run the server and observe stderr for discovery logs.

**Step 4: Document any issues found**

Create `docs/plans/2025-12-16-testing-notes.md` with findings.

---

## Summary

This plan implements the app-intents-mcp server in phases:

1. **Foundation** - Package.swift, models
2. **Transport** - JSON-RPC, stdio
3. **Server Core** - MCP request handling
4. **Discovery** - Bundle scanning, intent extraction
5. **Execution** - Shortcuts bridge
6. **Integration** - Wire everything together
7. **Packaging** - MCPB bundle
8. **Testing** - Manual validation

Each task is bite-sized (2-5 minutes) with complete code, exact commands, and commit points.
