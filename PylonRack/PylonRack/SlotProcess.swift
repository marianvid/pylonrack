import Foundation

final class SlotProcess {
    var onOutput:    ((String) -> Void)?
    var onTerminate: (() -> Void)?

    private var process: Process?

    func launch(command: String, workingDir: String, port: Int) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments     = ["-c", command]
        proc.currentDirectoryURL = URL(fileURLWithPath: workingDir)

        var env = ProcessInfo.processInfo.environment
        env["PYLON_PORT"] = String(port)
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError  = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8) else { return }
            self?.onOutput?(text)
        }

        proc.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { self?.onTerminate?() }
        }

        try proc.run()
        self.process = proc
    }

    func runScript(_ command: String, workingDir: String) async {
        let proc = Process()
        proc.executableURL       = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments           = ["-c", command]
        proc.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        try? proc.run()
        proc.waitUntilExit()
    }

    var isRunning: Bool { process?.isRunning ?? false }
    func sendSIGTERM() { process?.terminate() }
    func sendSIGKILL()  { process.map { kill($0.processIdentifier, SIGKILL) } }
}
