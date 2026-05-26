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

        // Start in new process group so we can kill all children
        proc.qualityOfService = .userInitiated

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

        // Move to new process group so killpg works
        setpgid(proc.processIdentifier, proc.processIdentifier)

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

    func sendSIGTERM() {
        guard let proc = process else { return }
        let pgid = getpgid(proc.processIdentifier)
        if pgid > 0 {
            // Kill entire process group — catches zsh + python3 children
            killpg(pgid, SIGTERM)
        } else {
            proc.terminate()
        }
    }

    func sendSIGKILL() {
        guard let proc = process else { return }
        let pgid = getpgid(proc.processIdentifier)
        if pgid > 0 {
            killpg(pgid, SIGKILL)
        } else {
            kill(proc.processIdentifier, SIGKILL)
        }
    }
}
