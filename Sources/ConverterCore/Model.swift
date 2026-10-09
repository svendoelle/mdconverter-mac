import Foundation

/// A span of text with uniform formatting.
struct Run: Equatable {
    var text: String
    var bold = false
    var italic = false
    var strike = false
    var code = false
    var link: String? = nil

    func sameFormat(as other: Run) -> Bool {
        bold == other.bold && italic == other.italic && strike == other.strike
            && code == other.code && link == other.link
    }
}

/// Format-independent document model shared by both converters.
enum Block: Equatable {
    case heading(Int, [Run])
    case paragraph([Run])
    case quote([Run])
    /// Lists are stored flat; `level` is the nesting depth (0-based).
    case listItem(ordered: Bool, level: Int, runs: [Run])
    case code(String)
    case rule
    /// Rows of cells; the first row is the header.
    case table([[[Run]]])
}

public enum ConversionError: LocalizedError {
    case invalidDocx(String)
    case unreadableText

    public var errorDescription: String? {
        switch self {
        case .invalidDocx(let reason): return "This is not a valid .docx file (\(reason))."
        case .unreadableText: return "The file could not be read as text."
        }
    }
}

public enum Converter {
    public static func markdownToDocx(_ markdown: String) throws -> Data {
        DocxWriter.write(MarkdownParser.parse(markdown))
    }

    public static func docxToMarkdown(_ docx: Data) throws -> String {
        MarkdownRenderer.render(try DocxReader.read(docx))
    }

    public static func decodeText(_ data: Data) throws -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        throw ConversionError.unreadableText
    }
}
