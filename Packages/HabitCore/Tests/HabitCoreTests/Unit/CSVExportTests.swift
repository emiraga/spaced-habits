import Foundation
@testable import HabitCore
import Testing

struct CSVExportTests {
    @Test func everyDayOfEveryHabitHasASource() throws {
        let export = try ExportSample.export()
        let days = try #require(export.csvFiles().first { $0.name == "days.csv" })
        let rows = parseCSV(days.contents)
        #expect(rows.first?[4] == "source")
        #expect(rows.count - 1 == export.projected.records.values.map(\.count).reduce(0, +))
        let sources = Set(DaySource.allCases.map(\.rawValue))
        #expect(rows.dropFirst().allSatisfy { $0.count == 8 && sources.contains($0[4]) })
        #expect(rows.contains { $0[1] == "Stretch, \"daily\"" })
    }

    @Test func quotesFieldsThatNeedIt() {
        var table = CSVTable(["a", "b", "c", "d"])
        table.append(["plain", "with, comma", "say \"hi\"", "two\nlines"])
        #expect(table.file("t.csv").contents == "a,b,c,d\nplain,\"with, comma\",\"say \"\"hi\"\"\",\"two\nlines\"\n")
    }

    @Test func everyFileParsesBackToItsHeaderWidth() throws {
        for file in try ExportSample.export().csvFiles() {
            let rows = parseCSV(file.contents)
            #expect(rows.allSatisfy { $0.count == rows[0].count }, "\(file.name)")
        }
    }

    /// RFC 4180, enough to read the export back.
    private func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var characters = text.makeIterator()
        var pending = characters.next()
        while let character = pending {
            pending = characters.next()
            if quoted {
                if character == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = characters.next()
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                quoted = true
            } else if character == "," {
                row.append(field)
                field = ""
            } else if character == "\n" {
                rows.append(row + [field])
                row = []
                field = ""
            } else {
                field.append(character)
            }
        }
        return rows
    }

    @Test func crc32MatchesTheStandardCheckValue() {
        #expect(ZipArchive.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    /// The system `unzip` reads every file back unchanged, and the same files zip to the same bytes.
    @Test func archiveUnzipsToTheCSVFiles() throws {
        let export = try ExportSample.export()
        let archive = try export.csvArchive()
        #expect(try archive == export.csvArchive())
        let url = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString).zip")
        try archive.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try unzip(["-tq", url.path]).hasPrefix("No errors detected"))
        for file in export.csvFiles() {
            #expect(try unzip(["-p", url.path, file.name]) == file.contents)
        }
    }

    private func unzip(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/unzip")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
