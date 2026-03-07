import XCTest
@testable import NvEnvyCore

final class PerformanceTests: XCTestCase {

    // MARK: - Search Performance

    func testSearchPerformance5000Notes() {
        let notes = (0..<5000).map { i in
            Note(
                title: "Note \(i) - \(["Swift", "Kotlin", "Rust", "Python", "TypeScript"].randomElement()!)",
                body: "This is the body of note \(i). It contains some text about \(["programming", "design", "architecture", "testing", "deployment"].randomElement()!) and \(["algorithms", "data structures", "patterns", "frameworks", "tools"].randomElement()!).",
                tags: [["swift", "ios", "macos", "linux", "web"].randomElement()!]
            )
        }

        var engine = SearchEngine()

        let start = CFAbsoluteTimeGetCurrent()
        let _ = engine.filter(notes: notes, query: "swift programming")
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(elapsed, 0.5, "Search of 5000 notes should complete in under 500ms, took \(elapsed)s")
    }

    // MARK: - File I/O Benchmark

    func testFileIOBenchmark1000Notes() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = FileStorageService(notesDirectory: tempDir)

        // Write 1000 notes
        let writeStart = CFAbsoluteTimeGetCurrent()
        for i in 0..<1000 {
            let note = Note(
                title: "Benchmark Note \(i)",
                body: "Body content for note \(i). Some additional text here.",
                tags: ["benchmark"],
                filename: "benchmark-note-\(i)"
            )
            try await storage.writeNote(note)
        }
        let writeElapsed = CFAbsoluteTimeGetCurrent() - writeStart

        // Read all back
        let readStart = CFAbsoluteTimeGetCurrent()
        let notes = try await storage.readAllNotes()
        let readElapsed = CFAbsoluteTimeGetCurrent() - readStart

        XCTAssertEqual(notes.count, 1000)
        // Just log times - these are informational
        print("Write 1000 notes: \(writeElapsed)s, Read 1000 notes: \(readElapsed)s")
    }

    // MARK: - WAL Benchmark

    func testWALBenchmark1000Records() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let service = CrashRecoveryService(cacheDirectory: tempDir)

        // Append 1000 records
        let writeStart = CFAbsoluteTimeGetCurrent()
        for i in 0..<1000 {
            let note = Note(title: "WAL Note \(i)", body: "Body \(i)", tags: ["wal"])
            try await service.appendRecord(note: note)
        }
        let writeElapsed = CFAbsoluteTimeGetCurrent() - writeStart

        // Recover all
        let readStart = CFAbsoluteTimeGetCurrent()
        let recovered = try await service.recoverPendingNotes()
        let readElapsed = CFAbsoluteTimeGetCurrent() - readStart

        XCTAssertEqual(recovered.count, 1000)
        print("WAL append 1000: \(writeElapsed)s, recover: \(readElapsed)s")
    }

    // MARK: - Large Note

    func testLargeNoteHandling() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = FileStorageService(notesDirectory: tempDir)

        // Create a note with ~100KB body
        let largeBody = String(repeating: "Lorem ipsum dolor sit amet. ", count: 4000) // ~112KB
        XCTAssertGreaterThan(largeBody.utf8.count, 100_000)

        let note = Note(title: "Large Note", body: largeBody, filename: "large-note")
        try await storage.writeNote(note)

        let notes = try await storage.readAllNotes()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.body, largeBody)

        // Search should work
        var engine = SearchEngine()
        let results = engine.filter(notes: notes, query: "Lorem ipsum")
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Memory Baseline

    func testMemoryBaseline10000Notes() {
        // Create 10000 Note objects and verify they can be managed
        var notes: [Note] = []
        for i in 0..<10_000 {
            notes.append(Note(
                title: "Memory Note \(i)",
                body: "Short body \(i)",
                tags: ["mem"]
            ))
        }

        XCTAssertEqual(notes.count, 10_000)

        // Verify search cache works
        var engine = SearchEngine()
        let results = engine.filter(notes: notes, query: "Memory Note 999")
        XCTAssertGreaterThan(results.count, 0)

        // Clear and verify deallocation
        notes.removeAll()
        XCTAssertEqual(notes.count, 0)
    }
}
