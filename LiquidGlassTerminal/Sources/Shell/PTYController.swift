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
class PTYController: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var isRunning: Bool = false

    // MARK: - Properties

    private var masterFD: Int32 = -1
    private var childPID: pid_t = -1
    private var readSource: DispatchSourceRead?
    private var processMonitor: DispatchSourceProcess?

    /// Callback for received data
    var onDataReceived: ((Data) -> Void)?

    /// Callback for process exit
    var onProcessExit: ((Int32) -> Void)?

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
        self.environment = env

        // Working directory
        if let cwd = workingDirectory {
            self.workingDirectory = cwd
        } else {
            self.workingDirectory = FileManager.default.currentDirectoryPath
        }
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Start the PTY and spawn shell
    func start(rows: Int = 24, cols: Int = 80) throws {
        guard !isRunning else {
            throw PTYError.alreadyRunning
        }

        try openPTY()
        try configurePTY(rows: rows, cols: cols)

        isRunning = true
        startMonitoring()
    }

    /// Stop the PTY and terminate shell
    func stop() {
        guard isRunning else { return }

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

        isRunning = false
    }

    // MARK: - PTY Management

    private func openPTY() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var slavePath = [CChar](repeating: 0, count: 1024)

        // Open PTY pair
        let result = openpty(&master, &slave, &slavePath, nil, nil)
        guard result == 0 else {
            throw PTYError.openFailed
        }

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
        let pid = fork()

        if pid == 0 {
            // Child process

            // Create new session
            setsid()

            // Set slave as controlling terminal
            ioctl(slaveFD, TIOCSCTTY, 0)

            // Redirect stdio to slave
            dup2(slaveFD, STDIN_FILENO)
            dup2(slaveFD, STDOUT_FILENO)
            dup2(slaveFD, STDERR_FILENO)

            // Close all other file descriptors
            #if os(macOS) || os(iOS)
            closefrom(3)
            #else
            let maxFD = min(Int(sysconf(_SC_OPEN_MAX)), 256)
            for fd in 3..<maxFD {
                close(Int32(fd))
            }
            #endif

            // Set environment variables
            let envVars = environment.map { "\($0.key)=\($0.value)" }
            var envPointers = envVars.map { strdup($0) }
            envPointers.append(nil)

            // Change to working directory
            chdir(workingDirectory)

            // Execute shell
            let shellName = (shellPath as NSString).lastPathComponent
            var argv = [shellPath, shellName] + shellArgs
            var argvPointers = argv.map { strdup($0) }
            argvPointers.append(nil)

            execve(shellPath, &argvPointers, &envPointers)

            // If we get here, exec failed
            perror("execve failed")
            _exit(1)
        } else if pid > 0 {
            // Parent process
            self.childPID = pid
        } else {
            throw PTYError.forkFailed
        }
    }

    // MARK: - I/O Operations

    func write(_ data: Data) throws {
        guard isRunning else {
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

    private func read() -> Data? {
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
        guard isRunning else {
            throw PTYError.notRunning
        }

        try configurePTY(rows: rows, cols: cols)
    }

    func sendSignal(_ signal: Int32) throws {
        guard isRunning && childPID > 0 else {
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
                DispatchQueue.main.async {
                    self.onDataReceived?(data)
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

                var status: Int32 = 0
                waitpid(self.childPID, &status, 0)

                let exitCode: Int32
                if WIFEXITED(status) {
                    exitCode = WEXITSTATUS(status)
                } else {
                    exitCode = -1
                }

                DispatchQueue.main.async {
                    self.isRunning = false
                    self.onProcessExit?(exitCode)
                }
            }

            processMonitor?.resume()
        }
    }

    private func stopMonitoring() {
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
