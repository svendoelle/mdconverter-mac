import AppKit

/// Renders the document model to a paginated A4 PDF via TextKit + the print system.
@MainActor
enum PDFRenderer {
    static func render(_ blocks: [Block]) throws -> Data {
        let attributed = AttributedBuilder().build(blocks)

        let pageSize = NSSize(width: 595.28, height: 841.89)
        let margin: CGFloat = 56
        let width = pageSize.width - 2 * margin

        let info = NSPrintInfo()
        info.paperSize = pageSize
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.jobDisposition = .save
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        defer { try? FileManager.default.removeItem(at: url) }

        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: pageSize.height))
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.textStorage?.setAttributedString(attributed)
        if let container = view.textContainer, let layout = view.layoutManager {
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container)
            view.setFrameSize(NSSize(width: width, height: ceil(used.height) + 1))
        }

        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run(), let data = try? Data(contentsOf: url), !data.isEmpty else {
            throw ConversionError.pdfFailed
        }
        return data
    }
}

/// Converts blocks into a styled attributed string (headings, lists, quotes, code, tables).
struct AttributedBuilder {
    private let bodySize: CGFloat = 11
    private let ink = NSColor.black
    private let gray = NSColor(white: 0.35, alpha: 1)

    func build(_ blocks: [Block]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var prevWasList = false
        var counters = [Int](repeating: 0, count: 10)
        var kinds = [Bool?](repeating: nil, count: 10)
        let headingSizes: [CGFloat] = [24, 19, 16, 14, 12, 11]
        let bullets = ["•", "◦", "▪"]

        for block in blocks {
            if case .listItem(let ordered, let rawLevel, let runs) = block {
                let level = min(rawLevel, 9)
                if !prevWasList {
                    counters = [Int](repeating: 0, count: 10)
                    kinds = [Bool?](repeating: nil, count: 10)
                }
                if level < 9 {
                    for l in (level + 1)..<10 {
                        counters[l] = 0
                        kinds[l] = nil
                    }
                }
                if kinds[level] != ordered {
                    counters[level] = 0
                    kinds[level] = ordered
                }
                var marker = bullets[level % 3]
                if ordered {
                    counters[level] += 1
                    marker = "\(counters[level])."
                }
                let content = NSMutableAttributedString(string: marker + "\t", attributes: [.font: font(bodySize), .foregroundColor: ink])
                content.append(inline(runs, size: bodySize))
                let head = CGFloat(level) * 20 + 24
                let style = paragraphStyle(after: 3, head: head, first: head - 18, tabs: [NSTextTab(textAlignment: .left, location: head)])
                append(content, style: style, to: out)
                prevWasList = true
                continue
            }
            prevWasList = false

            switch block {
            case .heading(let level, let runs):
                let size = headingSizes[min(max(level, 1), 6) - 1]
                let style = paragraphStyle(before: 10, after: 6)
                append(inline(runs, size: size, bold: true), style: style, to: out)
            case .paragraph(let runs):
                append(inline(runs, size: bodySize), style: paragraphStyle(after: 8), to: out)
            case .quote(let runs):
                let quote = NSTextBlock()
                quote.setBorderColor(NSColor(white: 0.75, alpha: 1), for: .minX)
                quote.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
                quote.setWidth(10, type: .absoluteValueType, for: .padding, edge: .minX)
                append(inline(runs, size: bodySize, italic: true, color: gray),
                       style: paragraphStyle(after: 8, blocks: [quote]), to: out)
            case .code(let code):
                let box = NSTextBlock()
                box.backgroundColor = NSColor(white: 0.95, alpha: 1)
                box.setWidth(6, type: .absoluteValueType, for: .padding)
                let text = code.replacingOccurrences(of: "\n", with: "\u{2028}").replacingOccurrences(of: "\t", with: "    ")
                let content = NSAttributedString(string: text.isEmpty ? " " : text, attributes: [.font: font(bodySize, mono: true), .foregroundColor: ink])
                append(content, style: paragraphStyle(after: 10, blocks: [box]), to: out)
            case .rule:
                let line = NSTextBlock()
                line.setBorderColor(NSColor(white: 0.65, alpha: 1))
                line.setWidth(0.5, type: .absoluteValueType, for: .border)
                let content = NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: 1)])
                append(content, style: paragraphStyle(before: 6, after: 10, blocks: [line]), to: out)
            case .table(let rows):
                appendTable(rows, to: out)
            case .listItem:
                break
            }
        }
        return out
    }

    private func appendTable(_ rows: [[[Run]]], to out: NSMutableAttributedString) {
        guard !rows.isEmpty else { return }
        let cols = max(rows.map { $0.count }.max() ?? 1, 1)
        let table = NSTextTable()
        table.numberOfColumns = cols
        table.collapsesBorders = true
        table.setContentWidth(100, type: .percentageValueType)
        for (r, row) in rows.enumerated() {
            for c in 0..<cols {
                let cell = NSTextTableBlock(table: table, startingRow: r, rowSpan: 1, startingColumn: c, columnSpan: 1)
                cell.setWidth(0.5, type: .absoluteValueType, for: .border)
                cell.setBorderColor(NSColor(white: 0.7, alpha: 1))
                cell.setWidth(4, type: .absoluteValueType, for: .padding)
                if r == 0 { cell.backgroundColor = NSColor(white: 0.94, alpha: 1) }
                let runs = c < row.count ? row[c] : []
                let content = runs.isEmpty
                    ? NSAttributedString(string: " ", attributes: [.font: font(bodySize)])
                    : inline(runs, size: bodySize, bold: r == 0)
                append(content, style: paragraphStyle(blocks: [cell]), to: out)
            }
        }
        let spacer = NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: 6)])
        append(spacer, style: paragraphStyle(), to: out)
    }

    // MARK: Helpers

    private func append(_ content: NSAttributedString, style: NSParagraphStyle, to out: NSMutableAttributedString) {
        let paragraph = NSMutableAttributedString(attributedString: content)
        let lastFont = content.length > 0
            ? content.attribute(.font, at: content.length - 1, effectiveRange: nil) ?? font(bodySize)
            : font(bodySize)
        paragraph.append(NSAttributedString(string: "\n", attributes: [.font: lastFont]))
        paragraph.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: paragraph.length))
        out.append(paragraph)
    }

    private func paragraphStyle(before: CGFloat = 0, after: CGFloat = 0, head: CGFloat = 0, first: CGFloat = 0,
                                blocks: [NSTextBlock] = [], tabs: [NSTextTab] = []) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.lineSpacing = 2
        style.headIndent = head
        style.firstLineHeadIndent = first
        style.textBlocks = blocks
        style.tabStops = tabs
        style.lineBreakMode = .byWordWrapping
        return style
    }

    private func inline(_ runs: [Run], size: CGFloat, bold: Bool = false, italic: Bool = false, color: NSColor? = nil) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for run in runs {
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font(size, bold: bold || run.bold, italic: italic || run.italic, mono: run.code),
                .foregroundColor: color ?? ink,
            ]
            if run.strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if run.code { attrs[.backgroundColor] = NSColor(white: 0.93, alpha: 1) }
            if let link = run.link, let url = URL(string: link) {
                attrs[.link] = url
                attrs[.foregroundColor] = NSColor(calibratedRed: 0.02, green: 0.39, blue: 0.76, alpha: 1)
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            out.append(NSAttributedString(string: run.text.replacingOccurrences(of: "\n", with: "\u{2028}"), attributes: attrs))
        }
        return out
    }

    private func font(_ size: CGFloat, bold: Bool = false, italic: Bool = false, mono: Bool = false) -> NSFont {
        var f: NSFont
        if mono {
            f = NSFont(name: "Menlo", size: size * 0.9) ?? NSFont.monospacedSystemFont(ofSize: size * 0.9, weight: .regular)
        } else {
            f = NSFont(name: "Helvetica Neue", size: size) ?? NSFont.systemFont(ofSize: size)
        }
        if bold { f = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) }
        if italic { f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) }
        return f
    }
}
