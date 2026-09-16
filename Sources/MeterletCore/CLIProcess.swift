import Foundation
import Darwin

/// Owns only a probe's child processes. Cancellation never touches an existing user CLI session.
public final class ProbeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var processes: [Process] = []
    public init() {}
    public var isCancelled: Bool { lock.withLock { cancelled } }
    public func check() throws { if isCancelled { throw UsageError.cancelled } }
    func register(_ process: Process) throws {
        try lock.withLock {
            guard !cancelled else { throw UsageError.cancelled }
            processes.append(process)
        }
    }
    func unregister(_ process: Process) { lock.withLock { processes.removeAll { $0 === process } } }
    public func cancel() {
        lock.withLock {
            cancelled = true
            for process in processes where process.isRunning {
                let pid = process.processIdentifier
                if getpgid(pid) == pid { kill(-pid, SIGTERM) }
                else { process.terminate() }
            }
        }
    }
}

final class CLIProcess {
    let process = Process()
    private let cancellation: ProbeCancellation
    private(set) var input: FileHandle
    private(set) var output: FileHandle
    private var stopped = false
    private var processGroup: pid_t?

    init(executable: URL, arguments: [String], directory: URL, environment: [String: String],
         mergeStandardError: Bool = false, nullStandardInput: Bool = false, cancellation: ProbeCancellation) throws {
        self.cancellation = cancellation
        let stdoutPipe = Pipe()
        output = stdoutPipe.fileHandleForReading
        process.standardOutput = stdoutPipe
        process.standardError = mergeStandardError ? stdoutPipe : FileHandle.nullDevice
        if nullStandardInput {
            input = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
        } else {
            let stdinPipe = Pipe()
            input = stdinPipe.fileHandleForWriting
            process.standardInput = stdinPipe
        }
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        try cancellation.register(process)
        do {
            try cancellation.check()
            try process.run()
            let pid = process.processIdentifier
            if getpgid(pid) == pid { processGroup = pid }
        } catch {
            cancellation.unregister(process)
            try? input.close()
            try? output.close()
            throw error
        }
    }

    func send(_ data: Data) throws {
        try cancellation.check()
        try input.write(contentsOf: data)
    }
    func sendJSON(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        try send(data)
    }

    /// poll sleeps in the kernel while the short-lived CLI is active; it is never used for idle refreshes.
    func read(waitMilliseconds: Int32 = 200) throws -> Data? {
        try cancellation.check()
        var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
        let status = poll(&descriptor, 1, waitMilliseconds)
        if status < 0 {
            if errno == EINTR { return nil }
            throw CocoaError(.fileReadUnknown)
        }
        guard status > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: 65_536)
        let count = Darwin.read(output.fileDescriptor, &bytes, bytes.count)
        if count > 0 { return Data(bytes.prefix(count)) }
        if count < 0 && errno != EIO && errno != EAGAIN { throw CocoaError(.fileReadUnknown) }
        return Data()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        try? input.close()
        try? output.close()
        if let group = processGroup { kill(-group, SIGTERM) }
        else if process.isRunning { process.terminate() }
        let deadline = Date().addingTimeInterval(0.5)
        while process.isRunning && Date() < deadline { usleep(10_000) }
        if let group = processGroup { kill(-group, SIGKILL) }
        else if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        cancellation.unregister(process)
    }
    deinit { stop() }
}
