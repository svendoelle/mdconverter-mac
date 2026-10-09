import AppKit
import PDFKit

/// Heuristic PDF text extraction: headings from font size, bold/italic from font traits,
/// bullet/numbered lists from line prefixes, paragraphs from vertical gaps. Images are ignored.
enum PDFReader {
    private struct Line {
        var runs: [Run]
        var size: CGFloat
        var minX: CGFloat
        var minY: CGFloat
        var maxY: CGFloat
        var page: Int
        var mono: Bool
        var text: String { runs.map { $0.text }.joined() }
    }

    static func read(_ data: Data) throws -> [Block] {
        guard let document = PDFDocument(data: data) else { throw ConversionError.invalidPDF }
        if document.isLocked, !document.unlock(withPassword: "") { throw ConversionError.pdfLocked }
        var lines: [Line] = []
        for index in 0..<document.pageCount {
            if let page = document.page(at: index) { lines += extractLines(page, index: index) }
        }
        guard !lines.isEmpty else { throw ConversionError.noPDFText }
        return assemble(lines)
    }

    // MARK: Extraction

    private static func extractLines(_ page: PDFPage, index: Int) -> [Line] {
        let bounds = page.bounds(for: .cropBox)
        guard let selection = page.selection(for: bounds) else { return [] }
        var result: [Line] = []

        for part in selection.selectionsByLine() {
            guard let attributed = part.attributedString else { continue }
            let plain = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if plain.isEmpty { continue }
            let rect = part.bounds(for: page)

            // Drop bare page numbers in the top/bottom margin.
            let edge = bounds.height * 0.07
            if plain.count <= 4, plain.allSatisfy({ $0.isNumber }),
               rect.midY < bounds.minY + edge || rect.midY > bounds.maxY - edge {
                continue
            }

            var runs: [Run] = []
            var weights: [CGFloat: Int] = [:]
            let nsString = attributed.string as NSString
            attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
                let text = normalize(nsString.substring(with: range))
                guard !text.isEmpty else { return }
                let info = traits(of: attrs[.font] as? NSFont)
                var run = Run(text: text)
                run.code = info.mono
                run.bold = info.bold && !info.mono
                run.italic = info.italic && !info.mono
                runs.append(run)
                let visible = text.filter { !$0.isWhitespace }.count
                if visible > 0 { weights[(info.size * 2).rounded() / 2, default: 0] += visible }
            }
            runs = InlineParser.merge(runs)
            guard !runs.isEmpty else { continue }
            runs[0].text = String(runs[0].text.drop { $0.isWhitespace })
            runs[runs.count - 1].text = runs[runs.count - 1].text.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            runs = runs.filter { !$0.text.isEmpty }
            guard !runs.isEmpty else { continue }

            let size = weights.max { $0.value < $1.value }?.key ?? 11
            let mono = runs.allSatisfy { $0.code || $0.text.allSatisfy { $0.isWhitespace } }
            result.append(Line(runs: runs, size: size, minX: rect.minX, minY: rect.minY, maxY: rect.maxY, page: index, mono: mono))
        }
        return result
    }

    private static func traits(of font: NSFont?) -> (size: CGFloat, bold: Bool, italic: Bool, mono: Bool) {
        guard let font else { return (11, false, false, false) }
        let name = font.fontName.lowercased()
        let t = font.fontDescriptor.symbolicTraits
        let bold = t.contains(.bold) || ["bold", "black", "heavy", "semibold"].contains { name.contains($0) }
        let italic = t.contains(.italic) || name.contains("italic") || name.contains("oblique")
        let mono = t.contains(.monoSpace) || ["mono", "courier", "menlo", "consolas", "code"].contains { name.contains($0) }
        return (font.pointSize, bold, italic, mono)
    }

    private static func normalize(_ text: String) -> String {
        var s = text
        for (from, to) in [("\u{FB00}", "ff"), ("\u{FB01}", "fi"), ("\u{FB02}", "fl"), ("\u{FB03}", "ffi"), ("\u{FB04}", "ffl"),
                           ("\u{00A0}", " "), ("\t", " "), ("\u{00AD}", ""), ("\n", " "), ("\r", " ")] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        return s
    }

    // MARK: Layout analysis

    private static func assemble(_ lines: [Line]) -> [Block] {
        var weights: [CGFloat: Int] = [:]
        for line in lines where !line.mono { weights[line.size, default: 0] += line.text.count }
        let body = weights.max { $0.value < $1.value }?.key ?? 11
        let headingSizes = Set(lines.filter { !$0.mono && $0.size >= body * 1.12 }.map { $0.size }).sorted(by: >)

        var blocks: [Block] = []
        var previous: Line? = nil
        var listBaseX: CGFloat? = nil

        for line in lines {
            let sameFlow = previous.map { $0.page == line.page } ?? false
            let gap = sameFlow ? (previous!.minY - line.maxY) : 0
            let tightGap = previous != nil && gap <= line.size * 0.45
            defer { previous = line }

            if line.mono {
                listBaseX = nil
                if previous?.mono == true, case .code(let existing)? = blocks.last {
                    let blank = sameFlow && gap > line.size * 0.9 ? "\n" : ""
                    blocks[blocks.count - 1] = .code(existing + "\n" + blank + line.text)
                } else {
                    blocks.append(.code(line.text))
                }
                continue
            }

            if let idx = headingSizes.firstIndex(of: line.size) {
                listBaseX = nil
                let level = min(idx + 1, 6)
                if case .heading(let l, let runs)? = blocks.last, l == level, previous?.size == line.size, tightGap {
                    blocks[blocks.count - 1] = .heading(l, join(runs, line.runs))
                } else {
                    blocks.append(.heading(level, line.runs))
                }
                continue
            }

            if let marker = listMarker(line.text) {
                let base = listBaseX ?? line.minX
                if listBaseX == nil { listBaseX = line.minX }
                let offset = line.minX - base
                let level = offset > 12 ? min(Int(offset / 18 + 0.5), 5) : 0
                blocks.append(.listItem(ordered: marker.ordered, level: level, runs: stripPrefix(line.runs, count: marker.length)))
                continue
            }

            let continues = tightGap && previous?.mono == false
                && abs((previous?.size ?? 0) - line.size) < 0.6
            switch blocks.last {
            case .paragraph(let runs)? where continues:
                blocks[blocks.count - 1] = .paragraph(join(runs, line.runs))
            case .listItem(let ordered, let level, let runs)? where continues:
                blocks[blocks.count - 1] = .listItem(ordered: ordered, level: level, runs: join(runs, line.runs))
            default:
                // A paragraph continuing across a page break (no sentence end, no gap info).
                if !sameFlow, previous != nil, case .paragraph(let runs)? = blocks.last,
                   let end = runs.last?.text.last, !".!?:;".contains(end),
                   line.runs.first?.text.first?.isLowercase == true {
                    blocks[blocks.count - 1] = .paragraph(join(runs, line.runs))
                } else {
                    listBaseX = nil
                    blocks.append(.paragraph(line.runs))
                }
            }
        }
        return blocks
    }

    private static func listMarker(_ text: String) -> (ordered: Bool, length: Int)? {
        let chars = Array(text)
        guard let first = chars.first else { return nil }
        func skipSpaces(_ from: Int) -> Int {
            var i = from
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            return i
        }
        if "•◦▪▫●○■□‣⁃".contains(first) {
            let end = skipSpaces(1)
            return end < chars.count ? (false, end) : nil
        }
        if "-–—*".contains(first), chars.count > 1, chars[1].isWhitespace {
            let end = skipSpaces(1)
            return end < chars.count ? (false, end) : nil
        }
        var digits = 0
        while digits < chars.count, chars[digits].isASCII, chars[digits].isNumber { digits += 1 }
        if (1...3).contains(digits), digits + 1 < chars.count, chars[digits] == "." || chars[digits] == ")",
           chars[digits + 1].isWhitespace {
            let end = skipSpaces(digits + 1)
            return end < chars.count ? (true, end) : nil
        }
        return nil
    }

    private static func stripPrefix(_ runs: [Run], count: Int) -> [Run] {
        var remaining = count
        var out: [Run] = []
        for var run in runs {
            if remaining > 0 {
                let drop = min(remaining, run.text.count)
                run.text = String(run.text.dropFirst(drop))
                remaining -= drop
            }
            if !run.text.isEmpty { out.append(run) }
        }
        return out
    }

    private static func join(_ a: [Run], _ b: [Run]) -> [Run] {
        guard var last = a.last else { return b }
        var head = Array(a.dropLast())
        let dehyphenate = last.text.hasSuffix("-")
            && last.text.dropLast().last?.isLetter == true
            && b.first?.text.first?.isLowercase == true
        if dehyphenate { last.text.removeLast() } else { last.text += " " }
        head.append(last)
        return InlineParser.merge(head + b)
    }
}
