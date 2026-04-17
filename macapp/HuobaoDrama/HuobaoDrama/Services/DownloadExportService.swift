import Foundation
import AppKit

@MainActor
final class DownloadExportService {
    static let shared = DownloadExportService()
    private let session = URLSession.shared
    private init() {}

    func downloadFile(from urlString: String) async throws -> URL {
        let baseURL = ConnectionSettingsStore.shared.baseURL
        let fullURLString = urlString.hasPrefix("http") ? urlString : baseURL + urlString
        guard let url = URL(string: fullURLString) else { throw APIError.invalidURL }

        let (tmpURL, _) = try await session.download(from: url)

        let fileName = url.lastPathComponent
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmpURL, to: dest)
        return dest
    }

    func saveToDownloads(from urlString: String) async throws -> URL {
        let localURL = try await downloadFile(from: urlString)
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let dest = downloads.appendingPathComponent(localURL.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: localURL, to: dest)
        return dest
    }

    func saveWithPanel(from urlString: String, suggestedName: String? = nil) async throws {
        let localURL = try await downloadFile(from: urlString)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName ?? localURL.lastPathComponent
        panel.allowedContentTypes = []
        let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow())
        if response == .OK, let dest = panel.url {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: localURL, to: dest)
        }
    }
}
