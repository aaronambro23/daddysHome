import Foundation
import PDFKit

enum OrchestratorAttachmentLoader {
    enum LoaderError: LocalizedError {
        case unsupportedFile
        case unreadableFile

        var errorDescription: String? {
            switch self {
            case .unsupportedFile: return "This file type is not supported"
            case .unreadableFile: return "Daddy could not read this file"
            }
        }
    }

    static func load(_ url: URL) throws -> OrchestratorAttachment {
        let kind: OrchestratorAttachmentKind
        let text: String

        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "webp", "gif":
            kind = .image
            text = ""
        case "pdf":
            guard let document = PDFDocument(url: url), let value = document.string else {
                throw LoaderError.unreadableFile
            }
            kind = .pdf
            text = limited(value)
        case "txt", "md", "markdown", "json", "yaml", "yml", "swift", "js", "ts", "tsx", "jsx", "html", "css":
            guard let value = try? String(contentsOf: url, encoding: .utf8) else {
                throw LoaderError.unreadableFile
            }
            kind = .text
            text = limited(value)
        default:
            throw LoaderError.unsupportedFile
        }

        return OrchestratorAttachment(
            name: url.lastPathComponent,
            path: url.path,
            kind: kind,
            extractedText: text
        )
    }

    private static func limited(_ value: String, maximum: Int = 80_000) -> String {
        guard value.count > maximum else { return value }
        return String(value.prefix(maximum)) + "\n[Context truncated by Daddy.]"
    }
}
