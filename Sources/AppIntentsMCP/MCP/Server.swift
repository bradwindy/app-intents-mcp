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
        let parameters = args["parameters"]

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
