#if os(macOS)
import Foundation
import Darwin
#if SWIFT_PACKAGE
import QuotaCore
#endif

struct CodexClient: Sendable {
    let executable: String

    static var detectedExecutable: String {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            NSHomeDirectory() + "/.npm-global/bin/codex"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }

    func fetch() async throws -> UsageSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let session = try RPCSession(executable: executable, timeout: 25)
                    defer { session.close() }
                    try session.initialize()
                    let response = try session.request(id: 2, method: "account/rateLimits/read")
                    let snapshot = try UsageSnapshot.decodeResponse(response)
                    guard !snapshot.buckets.isEmpty else { throw ClientError.noQuota }
                    continuation.resume(returning: snapshot)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func login(openURL: @escaping @Sendable (URL) -> Void) async throws {
        try await Task.detached(priority: .utility) {
            let session = try RPCSession(executable: executable, timeout: 180)
            defer { session.close() }
            try session.initialize()
            let result = try session.request(id: 2, method: "account/login/start", params: ["type": "chatgpt"])
            guard let object = try JSONSerialization.jsonObject(with: result) as? [String: Any],
                  let auth = object["authUrl"] as? String, let url = URL(string: auth),
                  url.scheme == "https", let host = url.host,
                  host == "auth.openai.com" || host == "chatgpt.com" || host == "auth.chatgpt.com" else {
                throw ClientError.protocolFailure
            }
            openURL(url)
            while true {
                let message = try session.readMessage()
                if message["method"] as? String == "account/login/completed",
                   let params = message["params"] as? [String: Any] {
                    guard params["success"] as? Bool == true else { throw ClientError.loginFailed }
                    return
                }
            }
        }.value
    }
}

enum ClientError: LocalizedError {
    case missingExecutable, disconnected, protocolFailure, service(String), noQuota, loginFailed
    var errorDescription: String? {
        switch self {
        case .missingExecutable: "Codex est introuvable. Choisis son exécutable dans les réglages."
        case .disconnected: "Codex n’a pas répondu ou la connexion a été interrompue. Réessaie."
        case .protocolFailure: "La réponse de Codex n’est pas compatible. Mets Codex à jour."
        case .service(let message): "Codex : \(message)"
        case .noQuota: "Aucun quota disponible pour ce compte. Vérifie la connexion à ton abonnement ChatGPT."
        case .loginFailed: "La connexion ChatGPT n’a pas abouti. Réessaie."
        }
    }
}

// Own the subprocess descriptors directly. Foundation Process teardown can block in
// an LSUIElement app even after a successful account response. No shell is used.
private final class RPCSession {
    private var childPID: pid_t = 0
    private var inputFD: Int32 = -1
    private var outputFD: Int32 = -1
    private var buffer = Data()
    private let deadline: Date

    init(executable: String, timeout: TimeInterval) throws {
        deadline = Date.now.addingTimeInterval(timeout)
        guard executable.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executable) else {
            throw ClientError.missingExecutable
        }
        var input: [Int32] = [0, 0]
        var output: [Int32] = [0, 0]
        guard pipe(&input) == 0 else { throw ClientError.disconnected }
        guard pipe(&output) == 0 else {
            Darwin.close(input[0]); Darwin.close(input[1])
            throw ClientError.disconnected
        }
        // Finder-launched menu apps may have closed stdin/stdout/stderr. Move
        // pipe descriptors above 2 before dup2/close actions to avoid collisions.
        for index in input.indices where input[index] < 3 {
            let replacement = fcntl(input[index], F_DUPFD_CLOEXEC, 3)
            guard replacement >= 0 else { throw ClientError.disconnected }
            Darwin.close(input[index]); input[index] = replacement
        }
        for index in output.indices where output[index] < 3 {
            let replacement = fcntl(output[index], F_DUPFD_CLOEXEC, 3)
            guard replacement >= 0 else { throw ClientError.disconnected }
            Darwin.close(output[index]); output[index] = replacement
        }
        let descriptors = input + output
        for fd in descriptors { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, input[0], STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        for fd in descriptors { posix_spawn_file_actions_addclose(&actions, fd) }
        if #available(macOS 26.0, *) {
            posix_spawn_file_actions_addchdir(&actions, NSHomeDirectory())
        } else {
            posix_spawn_file_actions_addchdir_np(&actions, NSHomeDirectory())
        }
        let arguments = [executable, "app-server", "--listen", "stdio://"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        var argv = arguments.map { strdup($0) } + [nil]
        var envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for pointer in argv { free(pointer) }
            for pointer in envp { free(pointer) }
        }
        let result = posix_spawn(&childPID, executable, &actions, nil, &argv, &envp)
        guard result == 0 else {
            for fd in descriptors { Darwin.close(fd) }
            throw ClientError.disconnected
        }
        Darwin.close(input[0]); Darwin.close(output[1])
        inputFD = input[1]
        outputFD = output[0]
        _ = fcntl(inputFD, F_SETFL, O_NONBLOCK)
        _ = fcntl(inputFD, F_SETNOSIGPIPE, 1)
    }

    func close() {
        guard childPID > 0 else { return }
        Darwin.close(inputFD)
        Darwin.close(outputFD)
        let pid = childPID
        childPID = 0
        // Give the server time to exit on EOF, then reap it without blocking UI
        // or the Swift executor. Until waitpid reaps it, this PID cannot be reused.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            var status: Int32 = 0
            if waitpid(pid, &status, WNOHANG) == 0 {
                Darwin.kill(pid, SIGTERM)
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                    var finalStatus: Int32 = 0
                    if waitpid(pid, &finalStatus, WNOHANG) == 0 {
                        Darwin.kill(pid, SIGKILL)
                        _ = waitpid(pid, &finalStatus, 0)
                    }
                }
            }
        }
    }

    func initialize() throws {
        _ = try request(id: 1, method: "initialize", params: [
            "clientInfo": ["name": "quotabar", "title": "QuotaBar", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"]
        ])
        try send(["method": "initialized"])
    }

    func request(id: Int, method: String, params: [String: Any]? = nil) throws -> Data {
        var object: [String: Any] = ["id": id, "method": method]
        if let params { object["params"] = params }
        try send(object)
        while true {
            let reply = try readMessage()
            guard reply["id"] as? Int == id else { continue }
            if let error = reply["error"] as? [String: Any] {
                throw ClientError.service(String((error["message"] as? String ?? "Erreur de lecture").prefix(300)))
            }
            guard let result = reply["result"] as? [String: Any] else { throw ClientError.protocolFailure }
            return try JSONSerialization.data(withJSONObject: result)
        }
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                guard Date.now < deadline else { throw ClientError.disconnected }
                var descriptor = pollfd(fd: inputFD, events: Int16(POLLOUT), revents: 0)
                let ready = poll(&descriptor, 1, 250)
                if ready == 0 || (ready < 0 && errno == EINTR) { continue }
                guard ready > 0 else { throw ClientError.disconnected }
                let count = Darwin.write(inputFD, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
                guard count > 0 else { throw ClientError.disconnected }
                offset += count
            }
        }
    }

    func readMessage() throws -> [String: Any] {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if line.isEmpty { continue }
                guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw ClientError.protocolFailure
                }
                return message
            }
            guard Date.now < deadline else { throw ClientError.disconnected }
            var descriptor = pollfd(fd: outputFD, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0)
            let ready = poll(&descriptor, 1, 250)
            if ready == 0 || (ready < 0 && errno == EINTR) { continue }
            guard ready > 0 else { throw ClientError.disconnected }
            var bytes = [UInt8](repeating: 0, count: 65536)
            let count = Darwin.read(outputFD, &bytes, bytes.count)
            guard count > 0 else { throw ClientError.disconnected }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count < 4 * 1024 * 1024 else { throw ClientError.protocolFailure }
        }
    }
}
#endif
