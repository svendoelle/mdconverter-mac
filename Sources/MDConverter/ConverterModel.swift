import AppKit
import ConverterCore
import SwiftUI
import UniformTypeIdentifiers

enum Format: Hashable {
    case markdown
    case docx
    case pdf

    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "md", "markdown", "mdown", "txt": self = .markdown
        case "docx": self = .docx
        case "pdf": self = .pdf
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .markdown: return "Markdown"
        case .docx: return "Word"
        case .pdf: return "PDF"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .docx: return "docx"
        case .pdf: return "pdf"
        }
    }

    var type: UTType {
        switch self {
        case .markdown: return UTType("net.daringfireball.markdown") ?? .plainText
        case .docx: return UTType("org.openxmlformats.wordprocessingml.document") ?? .data
        case .pdf: return .pdf
        }
    }

    /// Formats this one can be converted to.
    var targets: [Format] {
        switch self {
        case .markdown: return [.docx, .pdf]
        case .docx: return [.markdown, .pdf]
        case .pdf: return [.markdown]
        }
    }
}

enum ConversionStatus {
    case idle
    case done(URL)
    case failed(String)
}

@MainActor
final class ConverterModel: ObservableObject {
    @Published var sourceURL: URL?
    @Published var target: Format?
    @Published var status: ConversionStatus = .idle

    var source: Format? { sourceURL.flatMap(Format.init(url:)) }

    func load(_ url: URL) {
        sourceURL = url
        target = Format(url: url)?.targets.first
        status = .idle
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [Format.markdown, .docx, .pdf].map { $0.type }
            + [UTType(filenameExtension: "md")].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    func convert() {
        guard let url = sourceURL, let source, let target else { return }
        do {
            let input = try Data(contentsOf: url)
            let output: Data
            switch (source, target) {
            case (.markdown, .docx):
                output = try Converter.markdownToDocx(try Converter.decodeText(input))
            case (.markdown, .pdf):
                output = try Converter.markdownToPdf(try Converter.decodeText(input))
            case (.docx, .markdown):
                output = Data(try Converter.docxToMarkdown(input).utf8)
            case (.docx, .pdf):
                output = try Converter.docxToPdf(input)
            case (.pdf, .markdown):
                output = Data(try Converter.pdfToMarkdown(input).utf8)
            default:
                return
            }

            let panel = NSSavePanel()
            panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + "." + target.fileExtension
            panel.directoryURL = url.deletingLastPathComponent()
            panel.allowedContentTypes = [target.type]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let destination = panel.url else { return }

            try output.write(to: destination, options: .atomic)
            status = .done(destination)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
