import XCTest

final class SlotProcessTests: XCTestCase {

    // MARK: - Basic lifecycle

    func test_launch_processIsRunning() throws {
        let proc = SlotProcess()
        try proc.launch(command: "sleep 10", workingDir: "/tmp", port: 9001)
        XCTAssertTrue(proc.isRunning)
        proc.sendSIGTERM()
    }

    func test_sigterm_stopsProcess() throws {
        let proc = SlotProcess()
        try proc.launch(command: "sleep 10", workingDir: "/tmp", port: 9001)
        XCTAssertTrue(proc.isRunning)

        proc.sendSIGTERM()
        let deadline = Date().addingTimeInterval(3)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertFalse(proc.isRunning, "Process should be dead after SIGTERM")
    }

    func test_sigkill_stopsProcess() throws {
        let proc = SlotProcess()
        // Use a process that ignores SIGTERM
        try proc.launch(command: "trap '' TERM; sleep 10", workingDir: "/tmp", port: 9001)
        XCTAssertTrue(proc.isRunning)

        proc.sendSIGKILL()
        let deadline = Date().addingTimeInterval(3)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertFalse(proc.isRunning, "Process should be dead after SIGKILL")
    }

    // MARK: - Process group (critical: kills children too)

    func test_sigterm_killsEntireProcessGroup() throws {
        // Launch a shell that spawns a child — simulates zsh start.sh -> python3
        let proc = SlotProcess()
        try proc.launch(command: "sleep 30 & sleep 30", workingDir: "/tmp", port: 9001)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(proc.isRunning)

        // Get process group before kill
        let pid = proc.pid
        XCTAssertGreaterThan(pid, 0)

        proc.sendSIGTERM()
        Thread.sleep(forTimeInterval: 1.0)

        // Verify no processes remain in the group
        XCTAssertFalse(proc.isRunning)
        XCTAssertFalse(processGroupAlive(pid: pid),
            "All processes in group should be dead after SIGTERM")
    }

    func test_sigterm_killsChildScript() throws {
        // Simulates: zsh start.sh -> python3 server.py
        let script = """
        #!/bin/zsh
        sleep 30
        """
        let scriptURL = URL(fileURLWithPath: "/tmp/test_slot_script.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: scriptURL.path
        )

        let proc = SlotProcess()
        try proc.launch(command: "zsh /tmp/test_slot_script.sh",
                        workingDir: "/tmp", port: 9001)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(proc.isRunning)

        proc.sendSIGTERM()
        Thread.sleep(forTimeInterval: 1.5)

        XCTAssertFalse(proc.isRunning)
        try? FileManager.default.removeItem(at: scriptURL)
    }

    // MARK: - Output capture

    func test_output_isCapured() throws {
        let proc = SlotProcess()
        var output = ""
        proc.onOutput = { output += $0 }

        try proc.launch(command: "echo 'hello from slot'", workingDir: "/tmp", port: 9001)
        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertTrue(output.contains("hello from slot"),
            "stdout should be captured. Got: \(output)")
        proc.sendSIGTERM()
    }

    func test_terminationCallback_isCalled() throws {
        let proc = SlotProcess()
        let expectation = expectation(description: "onTerminate called")
        proc.onTerminate = { expectation.fulfill() }

        try proc.launch(command: "exit 0", workingDir: "/tmp", port: 9001)
        wait(for: [expectation], timeout: 3.0)
    }

    func test_envVar_pylonPortIsSet() throws {
        let proc = SlotProcess()
        var output = ""
        proc.onOutput = { output += $0 }

        try proc.launch(command: "echo \"PORT=$PYLON_PORT\"",
                        workingDir: "/tmp", port: 9876)
        Thread.sleep(forTimeInterval: 0.5)

        XCTAssertTrue(output.contains("PORT=9876"),
            "PYLON_PORT env var should be set. Got: \(output)")
    }

    // MARK: - Helpers

    private func processGroupAlive(pid: pid_t) -> Bool {
        // Check if any process in the group still exists
        return kill(-pid, 0) == 0
    }
}
