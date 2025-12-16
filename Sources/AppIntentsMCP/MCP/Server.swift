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
