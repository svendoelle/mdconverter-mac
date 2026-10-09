import AppKit
import ConverterCore
import SwiftUI
import UniformTypeIdentifiers

enum Direction {
    case markdownToWord
    case wordToMarkdown

    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "md", "markdown", "mdown", "txt": self = .markdownToWord
        case "docx": self = .wordToMarkdown
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .markdownToWord: return "Markdown → Word"
        case .wordToMarkdown: return "Word → Markdown"
        }
    }

    var actionTitle: String {
        switch self {
        case .markdownToWord: return "Convert to Word…"
        case .wordToMarkdown: return "Convert to Markdown…"
        }
    }

    var outputExtension: String {
        self == .markdownToWord ? "docx" : "md"
    }

    var outputType: UTType {
        switch self {
        case .markdownToWord:
            return UTType("org.openxmlformats.wordprocessingml.document") ?? .data
        case .wordToMarkdown:
            return UTType("net.daringfireball.markdown") ?? .plainText
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
    @Published var status: ConversionStatus = .idle

    var direction: Direction? { sourceURL.flatMap(Direction.init(url:)) }

    func load(_ url: URL) {
        sourceURL = url
        status = .idle
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType("net.daringfireball.markdown"), UTType("org.openxmlformats.wordprocessingml.document"),
            UTType(filenameExtension: "md"), UTType(filenameExtension: "docx"),
        ].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    func convert() {
        guard let source = sourceURL, let direction else { return }
        do {
            let input = try Data(contentsOf: source)
            let output: Data
            switch direction {
            case .markdownToWord:
                output = try Converter.markdownToDocx(try Converter.decodeText(input))
            case .wordToMarkdown:
                output = Data(try Converter.docxToMarkdown(input).utf8)
            }

            let panel = NSSavePanel()
            panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + "." + direction.outputExtension
            panel.directoryURL = source.deletingLastPathComponent()
            panel.allowedContentTypes = [direction.outputType]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let destination = panel.url else { return }

            try output.write(to: destination, options: .atomic)
            status = .done(destination)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
