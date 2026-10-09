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
    case invalidPDF
    case pdfLocked
    case noPDFText
    case pdfFailed

    public var errorDescription: String? {
        switch self {
        case .invalidDocx(let reason): return "This is not a valid .docx file (\(reason))."
        case .unreadableText: return "The file could not be read as text."
        case .invalidPDF: return "This is not a valid PDF file."
        case .pdfLocked: return "This PDF is password-protected."
        case .noPDFText: return "No text found in this PDF (scanned documents are not supported)."
        case .pdfFailed: return "The PDF could not be created."
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

    @MainActor
    public static func markdownToPdf(_ markdown: String) throws -> Data {
        try PDFRenderer.render(MarkdownParser.parse(markdown))
    }

    @MainActor
    public static func docxToPdf(_ docx: Data) throws -> Data {
        try PDFRenderer.render(DocxReader.read(docx))
    }

    public static func pdfToMarkdown(_ pdf: Data) throws -> String {
        MarkdownRenderer.render(try PDFReader.read(pdf))
    }

    public static func decodeText(_ data: Data) throws -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        throw ConversionError.unreadableText
    }
}
