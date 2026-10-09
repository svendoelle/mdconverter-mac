import Foundation

/// Line-based Markdown block parser (CommonMark/GFM subset: headings, lists,
/// quotes, fenced code, rules, pipe tables, paragraphs).
enum MarkdownParser {
    static func parse(_ source: String) -> [Block] {
        var text = source
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = text.components(separatedBy: "\n")

        var blocks: [Block] = []
        var paragraph: [String] = []
        var pending: (ordered: Bool, level: Int, text: String)? = nil
        var indentStack: [Int] = []
        var i = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(InlineParser.parse(joinLines(paragraph))))
            paragraph = []
        }
        func flushList() {
            if let item = pending {
                blocks.append(.listItem(ordered: item.ordered, level: item.level, runs: InlineParser.parse(item.text)))
                pending = nil
            }
        }
        func flushAll() {
            flushParagraph()
            flushList()
            indentStack = []
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                flushList()
                i += 1
                continue
            }

            // Fenced code block
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushAll()
                let fence = String(trimmed.prefix(3))
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[i])
                    i += 1
                }
                i += 1
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }

            // ATX heading
            if let (level, headingText) = parseHeading(trimmed) {
                flushAll()
                blocks.append(.heading(level, InlineParser.parse(headingText)))
                i += 1
                continue
            }

            // Setext heading
            if !paragraph.isEmpty, pending == nil, trimmed.allSatisfy({ $0 == "=" }) || trimmed.allSatisfy({ $0 == "-" }) {
                let level = trimmed.hasPrefix("=") ? 1 : 2
                let content = joinLines(paragraph)
                paragraph = []
                blocks.append(.heading(level, InlineParser.parse(content)))
                i += 1
                continue
            }

            // Horizontal rule
            if isRule(trimmed) {
                flushAll()
                blocks.append(.rule)
                i += 1
                continue
            }

            // Pipe table
            if trimmed.contains("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flushAll()
                var rows = [splitRow(trimmed)]
                i += 2
                while i < lines.count, lines[i].contains("|"),
                      !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(splitRow(lines[i]))
                    i += 1
                }
                let cols = rows.map { $0.count }.max() ?? 1
                let parsed: [[[Run]]] = rows.map { row -> [[Run]] in
                    (0..<cols).map { c -> [Run] in c < row.count ? InlineParser.parse(row[c]) : [] }
                }
                blocks.append(.table(parsed))
                continue
            }

            // Block quote
            if trimmed.hasPrefix(">") {
                flushAll()
                var quoteLines: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var l = lines[i].trimmingCharacters(in: .whitespaces)
                    while l.hasPrefix(">") {
                        l.removeFirst()
                        if l.hasPrefix(" ") { l.removeFirst() }
                    }
                    quoteLines.append(l)
                    i += 1
                }
                var group: [String] = []
                for l in quoteLines + [""] {
                    if l.trimmingCharacters(in: .whitespaces).isEmpty {
                        if !group.isEmpty {
                            blocks.append(.quote(InlineParser.parse(joinLines(group))))
                            group = []
                        }
                    } else {
                        group.append(l)
                    }
                }
                continue
            }

            // List item
            if let marker = parseListMarker(line) {
                flushParagraph()
                flushList()
                while let last = indentStack.last, marker.indent < last { indentStack.removeLast() }
                if indentStack.isEmpty || marker.indent > indentStack[indentStack.count - 1] {
                    indentStack.append(marker.indent)
                }
                pending = (marker.ordered, indentStack.count - 1, marker.content)
                i += 1
                continue
            }

            // Continuation of the previous list item
            if pending != nil {
                pending?.text += " " + trimmed
                i += 1
                continue
            }

            paragraph.append(line.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression))
            i += 1
        }
        flushAll()
        return blocks
    }

    private static func joinLines(_ lines: [String]) -> String {
        var result = ""
        for (idx, raw) in lines.enumerated() {
            var line = raw
            var hardBreak = false
            if idx < lines.count - 1 {
                if line.hasSuffix("  ") {
                    hardBreak = true
                } else if line.hasSuffix("\\") {
                    hardBreak = true
                    line.removeLast()
                }
            }
            result += line.trimmingCharacters(in: .whitespaces)
            if idx < lines.count - 1 { result += hardBreak ? "\n" : " " }
        }
        return result
    }

    private static func parseHeading(_ s: String) -> (Int, String)? {
        var n = 0
        for ch in s {
            if ch == "#" { n += 1 } else { break }
        }
        guard n >= 1, n <= 6 else { return nil }
        let rest = s.dropFirst(n)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        var stripped = text
        while stripped.hasSuffix("#") { stripped.removeLast() }
        if stripped.isEmpty || stripped.hasSuffix(" ") {
            text = stripped.trimmingCharacters(in: .whitespaces)
        }
        return (n, text)
    }

    private static func isRule(_ s: String) -> Bool {
        let compact = s.filter { $0 != " " }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func parseListMarker(_ line: String) -> (ordered: Bool, indent: Int, content: String)? {
        let chars = Array(line)
        var idx = 0
        var indent = 0
        while idx < chars.count, chars[idx] == " " || chars[idx] == "\t" {
            indent += chars[idx] == "\t" ? 4 : 1
            idx += 1
        }
        guard idx < chars.count else { return nil }
        let c = chars[idx]
        if "-*+".contains(c) {
            guard idx + 1 < chars.count, chars[idx + 1] == " " else { return nil }
            return (false, indent, String(chars[(idx + 2)...]).trimmingCharacters(in: .whitespaces))
        }
        if c.isASCII, c.isNumber {
            var j = idx
            while j < chars.count, chars[j].isASCII, chars[j].isNumber { j += 1 }
            guard j + 1 < chars.count, chars[j] == "." || chars[j] == ")", chars[j + 1] == " " else { return nil }
            return (true, indent, String(chars[(j + 2)...]).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        guard line.contains("|"), line.contains("-") else { return false }
        let cells = splitRow(line)
        return !cells.isEmpty && cells.allSatisfy { cell in
            cell.contains("-") && cell.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func splitRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|"), !s.hasSuffix("\\|") { s.removeLast() }
        var cells: [String] = []
        var cur = ""
        var escaped = false
        for ch in s {
            if escaped {
                if ch != "|" { cur.append("\\") }
                cur.append(ch)
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "|" {
                cells.append(cur.trimmingCharacters(in: .whitespaces))
                cur = ""
            } else {
                cur.append(ch)
            }
        }
        if escaped { cur.append("\\") }
        cells.append(cur.trimmingCharacters(in: .whitespaces))
        return cells
    }
}
