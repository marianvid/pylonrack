import Foundation

final class SlotProcess {
    private var process: Process?
    private var logPipe: Pipe?

    var onOutput:    ((String) -> Void)?
    var onTerminate: (() -> Void)?
    var isRunning:   Bool  { process?.isRunning ?? false }
    var pid:         Int32? { process?.processIdentifier }

    func launch(command: String, workingDir: String, port: Int) throws {
        let proc = Process()
        proc.executableURL       = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments           = ["-c", command]
        proc.currentDirectoryURL = URL(fileURLWithPath: workingDir)

        var env = ProcessInfo.processInfo.environment
        env["PARALLAX_PORT"] = String(port)
        proc.environment = env

        let pipe = Pipe()
        logPipe  = pipe
        proc.standardOutput = pipe
        proc.standardError  = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in self?.onOutput?(str) }
        }

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.logPipe?.fileHandleForReading.readabilityHandler = nil
                self?.onTerminate?()
            }
        }

        try proc.run()
        process = proc
    }

    func sendSIGTERM() { process?.terminate() }

    func sendSIGKILL() {
        guard let p = pid else { return }
        kill(p, SIGKILL)
    }

    func runScript(_ command: String, workingDir: String) async {
        await Task.detached(priority: .utility) {
            let proc = Process()
            proc.executableURL       = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments           = ["-c", command]
            proc.currentDirectoryURL = URL(fileURLWithPath: workingDir)
            try? proc.run()
            for _ in 0..<50 {
                if !proc.isRunning { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if proc.isRunning { proc.terminate() }
        }.value
    }
}
