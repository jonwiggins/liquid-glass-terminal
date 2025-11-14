//
//  PTYController.swift
//  LiquidGlassTerminal
//
//  Manages pseudo-terminal (PTY) and shell process
//

import Foundation
import Darwin
import Combine

/// Errors that can occur during PTY operations
enum PTYError: Error, LocalizedError {
    case openFailed
    case forkFailed
    case execFailed
    case ioError
    case alreadyRunning
    case notRunning

    var errorDescription: String? {
        switch self {
        case .openFailed: return "Failed to open PTY"
        case .forkFailed: return "Failed to fork process"
        case .execFailed: return "Failed to execute shell"
        case .ioError: return "I/O error occurred"
        case .alreadyRunning: return "PTY is already running"
        case .notRunning: return "PTY is not running"
        }
    }
}

/// Manages a pseudo-terminal and shell process
class PTYController: ObservableObject, @unchecked Sendable {
    // MARK: - Published Properties

    @MainActor @Published private(set) var isRunning: Bool = false

    // MARK: - Properties

    nonisolated(unsafe) private var internalRunning: Bool = false
    nonisolated(unsafe) private var masterFD: Int32 = -1
    nonisolated(unsafe) private var childPID: pid_t = -1
    nonisolated(unsafe) private var readSource: DispatchSourceRead?
    nonisolated(unsafe) private var processMonitor: DispatchSourceProcess?

    /// Callback for received data
    nonisolated(unsafe) var onDataReceived: (@Sendable (Data) -> Void)?

    /// Callback for process exit
    nonisolated(unsafe) var onProcessExit: (@Sendable (Int32) -> Void)?

    // MARK: - Shell Configuration

    private var shellPath: String
    private var shellArgs: [String]
    private var environment: [String: String]
    private var workingDirectory: String

    // MARK: - Initialization

    init(
        shellPath: String? = nil,
        shellArgs: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: String? = nil
    ) {
        // Determine shell
        if let shell = shellPath {
            self.shellPath = shell
        } else if let envShell = ProcessInfo.processInfo.environment["SHELL"] {
            self.shellPath = envShell
        } else {
            self.shellPath = "/bin/zsh"
        }

        self.shellArgs = shellArgs

        // Merge with current environment
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            env[key] = value
        }

        // Ensure essential terminal environment variables are set
        if env["TERM"] == nil {
            env["TERM"] = "xterm-256color"
        }
        if env["LANG"] == nil {
            env["LANG"] = "en_US.UTF-8"
        }

        self.environment = env

        // Working directory
        if let cwd = workingDirectory {
            self.workingDirectory = cwd
        } else {
            self.workingDirectory = FileManager.default.currentDirectoryPath
        }
    }

    deinit {
        // Can't call async/MainActor methods in deinit
        // Clean up directly
        stopMonitoring()

        if childPID > 0 {
            kill(childPID, SIGTERM)
            usleep(100_000)
            var status: Int32 = 0
            if waitpid(childPID, &status, WNOHANG) == 0 {
                kill(childPID, SIGKILL)
                waitpid(childPID, &status, 0)
            }
        }

        if masterFD >= 0 {
            close(masterFD)
        }
    }

    // MARK: - Lifecycle

    /// Start the PTY and spawn shell
    func start(rows: Int = 24, cols: Int = 80) throws {
        try openPTY()
        try configurePTY(rows: rows, cols: cols)

        internalRunning = true
        Task { @MainActor in
            self.isRunning = true
        }
        startMonitoring()
    }

    /// Stop the PTY and terminate shell
    func stop() {
        internalRunning = false
        stopMonitoring()

        // Terminate child process
        if childPID > 0 {
            kill(childPID, SIGTERM)

            // Wait briefly for clean shutdown
            usleep(100_000)  // 100ms

            // Force kill if still running
            var status: Int32 = 0
            if waitpid(childPID, &status, WNOHANG) == 0 {
                kill(childPID, SIGKILL)
                waitpid(childPID, &status, 0)
            }

            childPID = -1
        }

        // Close master FD
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }

        Task { @MainActor in
            self.isRunning = false
        }
    }

    // MARK: - PTY Management

    private func openPTY() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var slavePath = [CChar](repeating: 0, count: 1024)

        // Open PTY pair
        let result = openpty(&master, &slave, &slavePath, nil, nil)
        guard result == 0 else {
            print("❌ openpty failed with result: \(result), errno: \(errno)")
            throw PTYError.openFailed
        }

        print("✅ PTY opened: master=\(master), slave=\(slave)")
        self.masterFD = master

        // Set non-blocking I/O on master
        let flags = fcntl(master, F_GETFL, 0)
        fcntl(master, F_SETFL, flags | O_NONBLOCK)

        // Spawn shell in child process
        try spawnProcess(slaveFD: slave)

        // Close slave in parent (only child needs it)
        close(slave)
    }

    private func configurePTY(rows: Int, cols: Int) throws {
        var size = winsize()
        size.ws_row = UInt16(rows)
        size.ws_col = UInt16(cols)
        size.ws_xpixel = 0
        size.ws_ypixel = 0

        let result = ioctl(masterFD, TIOCSWINSZ, &size)
        guard result == 0 else {
            throw PTYError.ioError
        }
    }

    private func spawnProcess(slaveFD: Int32) throws {
        // Setup file actions for posix_spawn
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        // Redirect stdio to slave
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slaveFD, STDERR_FILENO)

        // Close slave FD in child
        posix_spawn_file_actions_addclose(&fileActions, slaveFD)

        // Setup spawn attributes
        var spawnAttrs: posix_spawnattr_t?
        posix_spawnattr_init(&spawnAttrs)
        defer { posix_spawnattr_destroy(&spawnAttrs) }

        // Set flags for new session
        var flags: Int16 = 0
        #if os(macOS)
        // POSIX_SPAWN_SETSID is available on macOS 10.15+
        if #available(macOS 10.15, *) {
            flags |= Int16(POSIX_SPAWN_SETSID)
        }
        flags |= Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)
        #endif
        if flags != 0 {
            posix_spawnattr_setflags(&spawnAttrs, flags)
        }

        // Prepare environment
        let envVars = environment.map { "\($0.key)=\($0.value)" }
        var envPointers = envVars.map { strdup($0) }
        envPointers.append(nil)
        defer {
            for ptr in envPointers where ptr != nil {
                free(ptr)
            }
        }

        // Prepare arguments
        // argv[0] should be the shell name (with leading '-' for login shell)
        let shellName = (shellPath as NSString).lastPathComponent
        let loginShellName = "-" + shellName
        let argv = [loginShellName] + shellArgs
        var argvPointers = argv.map { strdup($0) }
        argvPointers.append(nil)
        defer {
            for ptr in argvPointers where ptr != nil {
                free(ptr)
            }
        }

        // Change to working directory (do this before spawn)
        let originalDir = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(workingDirectory)

        // Spawn process
        var pid: pid_t = 0
        let result = posix_spawn(
            &pid,
            shellPath,
            &fileActions,
            &spawnAttrs,
            argvPointers,
            envPointers
        )

        // Restore original directory
        FileManager.default.changeCurrentDirectoryPath(originalDir)

        guard result == 0 else {
            print("❌ posix_spawn failed with result: \(result), errno: \(errno)")
            throw PTYError.forkFailed
        }

        print("✅ Shell process spawned with PID: \(pid)")
        self.childPID = pid
    }

    // MARK: - I/O Operations

    func write(_ data: Data) throws {
        guard internalRunning else {
            throw PTYError.notRunning
        }

        try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let baseAddress = bytes.baseAddress else { return }

            var totalWritten = 0
            while totalWritten < data.count {
                let bytesWritten = Darwin.write(
                    masterFD,
                    baseAddress.advanced(by: totalWritten),
                    data.count - totalWritten
                )

                if bytesWritten < 0 {
                    if errno == EAGAIN || errno == EINTR {
                        continue
                    }
                    throw PTYError.ioError
                }

                totalWritten += bytesWritten
            }
        }
    }

    func write(_ string: String) throws {
        guard let data = string.data(using: .utf8) else { return }
        try write(data)
    }

    nonisolated private func read() -> Data? {
        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytesRead = Darwin.read(masterFD, &buffer, buffer.count)

        if bytesRead > 0 {
            return Data(buffer[..<bytesRead])
        } else if bytesRead == 0 {
            // EOF
            return nil
        } else {
            // Error
            if errno == EAGAIN || errno == EINTR {
                return nil
            }
            // Other error
            return nil
        }
    }

    // MARK: - Terminal Control

    func resize(rows: Int, cols: Int) throws {
        guard internalRunning else {
            throw PTYError.notRunning
        }

        try configurePTY(rows: rows, cols: cols)
    }

    func sendSignal(_ signal: Int32) throws {
        guard internalRunning && childPID > 0 else {
            throw PTYError.notRunning
        }

        kill(childPID, signal)
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        // Monitor for readable data
        readSource = DispatchSource.makeReadSource(
            fileDescriptor: masterFD,
            queue: .global(qos: .userInteractive)
        )

        readSource?.setEventHandler { [weak self] in
            guard let self = self else { return }

            // Read all available data
            while let data = self.read() {
                print("📥 PTY received \(data.count) bytes")
                if let str = String(data: data, encoding: .utf8) {
                    print("📥 Data: '\(str)'")
                }
                let callback = self.onDataReceived
                DispatchQueue.main.async {
                    callback?(data)
                }
            }
        }

        readSource?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.masterFD >= 0 {
                close(self.masterFD)
                self.masterFD = -1
            }
        }

        readSource?.resume()

        // Monitor child process
        if childPID > 0 {
            processMonitor = DispatchSource.makeProcessSource(
                identifier: childPID,
                eventMask: .exit,
                queue: .main
            )

            processMonitor?.setEventHandler { [weak self] in
                guard let self = self else { return }

                let pid = self.childPID
                var status: Int32 = 0
                waitpid(pid, &status, 0)

                let exitCode: Int32
                if WIFEXITED(status) {
                    exitCode = WEXITSTATUS(status)
                } else {
                    exitCode = -1
                }

                let callback = self.onProcessExit
                Task { @MainActor [weak self] in
                    self?.isRunning = false
                    callback?(exitCode)
                }
            }

            processMonitor?.resume()
        }
    }

    nonisolated private func stopMonitoring() {
        readSource?.cancel()
        readSource = nil

        processMonitor?.cancel()
        processMonitor = nil
    }
}

// MARK: - Process Status Helpers

private func WIFEXITED(_ status: Int32) -> Bool {
    return (status & 0x7f) == 0
}

private func WEXITSTATUS(_ status: Int32) -> Int32 {
    return (status >> 8) & 0xff
}
