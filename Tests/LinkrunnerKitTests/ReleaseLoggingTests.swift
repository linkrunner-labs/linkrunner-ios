import XCTest

/// Release builds must print nothing: every SDK print sits inside `#if DEBUG`.
final class ReleaseLoggingTests: XCTestCase {

    func testNoPrintOutsideDebugBlocks() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Linkrunner")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "no sources found at \(sources.path)")

        let printCall = try NSRegularExpression(pattern: #"\b(print|debugPrint|NSLog|os_log)\s*\("#)
        var offenders: [String] = []
        for file in files {
            var stack: [Bool] = []
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, raw) in lines.enumerated() {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#if") {
                    stack.append(line == "#if DEBUG")
                } else if line.hasPrefix("#else") || line.hasPrefix("#elseif") {
                    if !stack.isEmpty { stack[stack.count - 1] = false }
                } else if line.hasPrefix("#endif") {
                    _ = stack.popLast()
                } else if !line.hasPrefix("//") && !stack.contains(true),
                          printCall.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    offenders.append("\(file.lastPathComponent):\(index + 1): \(line)")
                }
            }
        }
        XCTAssertEqual(offenders, [], "print outside #if DEBUG")
    }
}
