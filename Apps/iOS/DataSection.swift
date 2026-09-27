import HabitCore
import HabitUI
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Your data (DESIGN.md §11): JSON and CSV export through the share sheet, JSON import from Files.
struct DataSection: View {
    @Environment(AppModel.self) private var model
    @Environment(ErrorPresenter.self) private var errors
    @State private var importing = false
    @State private var summary: ImportSummary?

    var body: some View {
        Section {
            ShareLink(
                item: ExportFile(export: model.dataExport(), day: model.today, format: .json),
                preview: SharePreview("Spaced Habits data (JSON)")
            ) {
                Label("Export JSON", systemImage: "square.and.arrow.up")
            }
            ShareLink(
                item: ExportFile(export: model.dataExport(), day: model.today, format: .csv),
                preview: SharePreview("Spaced Habits data (CSV)")
            ) {
                Label("Export CSV", systemImage: "tablecells")
            }
            Button {
                importing = true
            } label: {
                Label("Import JSON…", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Your data")
        } footer: {
            Text(
                "JSON holds everything and can be imported again. CSV opens in Numbers or Excel. Importing adds and updates habits and answers, and never deletes any."
            )
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            errors.attempt { summary = try model.importJSON(Self.read(result.get())) }
        }
        .alert(
            "Import finished",
            isPresented: Binding(get: { summary != nil }, set: {
                if !$0 {
                    summary = nil
                }
            }),
            presenting: summary
        ) { _ in
            Button("OK") {}
        } message: { summary in
            Text(Self.describe(summary))
        }
    }

    /// Files hands out a security-scoped URL.
    private static func read(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try Data(contentsOf: url)
    }

    private static func describe(_ summary: ImportSummary) -> String {
        if summary.changedNothing {
            return String(localized: "Everything in the file was already here.")
        }
        var parts = [
            String(localized: "\(summary.added) new records"),
            String(localized: "\(summary.updated) updated"),
        ]
        if summary.settingsChanged {
            parts.append(String(localized: "settings replaced"))
        }
        return String(localized: "\(parts.formatted(.list(type: .and))).")
    }
}

/// An export the share sheet writes on demand, as a named file: `SpacedHabits-2026-09-28.json` or
/// `SpacedHabits-2026-09-28-csv.zip`.
struct ExportFile: Transferable {
    enum Format: Sendable {
        case json, csv
    }

    let export: DataExport
    let day: DayKey
    let format: Format

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { try SentTransferredFile($0.write()) }
            .exportingCondition { $0.format == .json }
        FileRepresentation(exportedContentType: .zip) { try SentTransferredFile($0.write()) }
            .exportingCondition { $0.format == .csv }
    }

    /// Into a fresh temporary folder, so the file keeps its plain name.
    func write() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let (name, data) = switch format {
        case .json: try ("SpacedHabits-\(day).json", export.json())
        case .csv: try ("SpacedHabits-\(day)-csv.zip", export.csvArchive())
        }
        let url = folder.appending(path: name)
        try data.write(to: url)
        return url
    }
}
