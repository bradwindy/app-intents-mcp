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
