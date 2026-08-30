import Foundation

public struct CommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let output: String
    public let timedOut: Bool

    public init(exitCode: Int32, output: String, timedOut: Bool = false) {
        self.exitCode = exitCode
        self.output = output
        self.timedOut = timedOut
    }
}

public struct ProcessRunner: Sendable {
    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 15
    ) async -> CommandResult {
        await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            if let environment {
                process.environment = environment
            }

            do {
                try process.run()
            } catch {
                return CommandResult(exitCode: -1, output: error.localizedDescription)
            }

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }

            let timedOut = process.isRunning
            if timedOut {
                process.terminate()
                process.waitUntilExit()
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)
            return CommandResult(
                exitCode: timedOut ? -2 : process.terminationStatus,
                output: output,
                timedOut: timedOut
            )
        }.value
    }
}
