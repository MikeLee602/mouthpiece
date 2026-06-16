import Foundation

/// Converts traditional Chinese to simplified using the bundled `opencc` binary.
/// Falls back to passing through unchanged on any error.
struct SimplifiedChineseConverter: Sendable {
    let binaryPath: String

    init(binaryPath: String = "/opt/homebrew/bin/opencc") {
        self.binaryPath = binaryPath
    }

    /// Convert traditional → simplified. Returns the input unchanged if opencc is missing
    /// or the conversion fails.
    func convert(_ text: String) -> String {
        guard !text.isEmpty,
              FileManager.default.isExecutableFile(atPath: binaryPath) else {
            return text
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["-c", "t2s"]
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            // Write input + close
            if let data = text.data(using: .utf8) {
                stdin.fileHandleForWriting.write(data)
            }
            try? stdin.fileHandleForWriting.close()
            // Read output before waiting (avoid pipe deadlock)
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            _ = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return text }
            let result = String(data: outData, encoding: .utf8) ?? text
            // opencc may add a trailing newline
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return text
        }
    }
}
