import Foundation

/// Serialises the document model back to Markdown.
enum MarkdownRenderer {
    static func render(_ blocks: [Block]) -> String {
        var lines: [String] = []
        var prevWasList = false
        var counters = [Int](repeating: 0, count: 10)
        var kinds = [Bool?](repeating: nil, count: 10)

        func separate() {
            if !lines.isEmpty { lines.append("") }
        }

        for block in blocks {
            if case .listItem(let ordered, let rawLevel, let runs) = block {
                let level = min(rawLevel, 9)
                if !prevWasList || (level == 0 && kinds[0] != nil && kinds[0] != ordered) {
                    separate()
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
                let marker: String
                if ordered {
                    counters[level] += 1
                    marker = "\(counters[level])."
                } else {
                    marker = "-"
                }
                let text = inline(runs).replacingOccurrences(of: "  \n", with: " ").replacingOccurrences(of: "\n", with: " ")
                lines.append(String(repeating: " ", count: level * 4) + marker + " " + text.trimmingCharacters(in: .whitespaces))
                prevWasList = true
                continue
            }
            prevWasList = false
            separate()
            switch block {
            case .heading(let level, let runs):
                let plain = runs.map { r -> Run in var r = r; r.bold = false; return r }
                let text = inline(plain).replacingOccurrences(of: "  \n", with: " ").replacingOccurrences(of: "\n", with: " ")
                lines.append(String(repeating: "#", count: min(max(level, 1), 6)) + " " + text.trimmingCharacters(in: .whitespaces))
            case .paragraph(let runs):
                lines.append(escapeBlockStart(inline(runs).trimmingCharacters(in: .whitespacesAndNewlines)))
            case .quote(let runs):
                let text = inline(runs).trimmingCharacters(in: .whitespacesAndNewlines)
                for l in text.components(separatedBy: "\n") { lines.append("> " + l.trimmingCharacters(in: .whitespaces)) }
            case .code(let code):
                let fence = code.contains("```") ? "````" : "```"
                lines.append(fence)
                lines.append(code)
                lines.append(fence)
            case .rule:
                lines.append("---")
            case .table(let rows):
                renderTable(rows, into: &lines)
            case .listItem:
                break
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderTable(_ rows: [[[Run]]], into lines: inout [String]) {
        guard let header = rows.first else { return }
        let cols = rows.map { $0.count }.max() ?? header.count
        func row(_ cells: [[Run]]) -> String {
            let texts: [String] = (0..<cols).map { c -> String in
                guard c < cells.count else { return " " }
                var t = inline(cells[c]).trimmingCharacters(in: .whitespacesAndNewlines)
                t = t.replacingOccurrences(of: "|", with: "\\|")
                    .replacingOccurrences(of: "  \n", with: "<br>")
                    .replacingOccurrences(of: "\n", with: "<br>")
                return t.isEmpty ? " " : t
            }
            return "| " + texts.joined(separator: " | ") + " |"
        }
        let plainHeader = header.map { cell in cell.map { r -> Run in var r = r; r.bold = false; return r } }
        lines.append(row(plainHeader))
        lines.append("|" + String(repeating: " --- |", count: cols))
        for r in rows.dropFirst() { lines.append(row(r)) }
    }

    // MARK: Inline

    static func inline(_ runs: [Run]) -> String {
        var out = ""
        var i = 0
        while i < runs.count {
            if let url = runs[i].link {
                var label = ""
                var j = i
                while j < runs.count, runs[j].link == url {
                    label += styled(runs[j])
                    j += 1
                }
                let safe = url.replacingOccurrences(of: " ", with: "%20")
                    .replacingOccurrences(of: "(", with: "%28")
                    .replacingOccurrences(of: ")", with: "%29")
                out += "[\(label)](\(safe))"
                i = j
            } else {
                out += styled(runs[i])
                i += 1
            }
        }
        return out
    }

    private static func styled(_ run: Run) -> String {
        let text = run.text
        if run.code {
            let core = text.replacingOccurrences(of: "\n", with: " ")
            if core.trimmingCharacters(in: .whitespaces).isEmpty { return core }
            let fence = core.contains("`") ? "``" : "`"
            let pad = core.contains("`") ? " " : ""
            return fence + pad + core + pad + fence
        }
        let (lead, core, trail) = splitWhitespace(text)
        if core.isEmpty { return text.replacingOccurrences(of: "\n", with: "  \n") }
        var s = escape(core)
        if run.strike { s = "~~\(s)~~" }
        if run.bold && run.italic {
            s = "***\(s)***"
        } else if run.bold {
            s = "**\(s)**"
        } else if run.italic {
            s = "*\(s)*"
        }
        return (lead + s + trail).replacingOccurrences(of: "\n", with: "  \n")
    }

    private static func splitWhitespace(_ s: String) -> (String, String, String) {
        let chars = Array(s)
        var start = 0
        var end = chars.count
        while start < end, chars[start].isWhitespace { start += 1 }
        while end > start, chars[end - 1].isWhitespace { end -= 1 }
        return (String(chars[0..<start]), String(chars[start..<end]), String(chars[end...]))
    }

    private static func escape(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        for (idx, c) in chars.enumerated() {
            switch c {
            case "\\", "*", "`", "[", "]":
                out += "\\" + String(c)
            case "_":
                let prevWord = idx > 0 && (chars[idx - 1].isLetter || chars[idx - 1].isNumber)
                let nextWord = idx + 1 < chars.count && (chars[idx + 1].isLetter || chars[idx + 1].isNumber)
                out += (prevWord && nextWord) ? "_" : "\\_"
            default:
                out.append(c)
            }
        }
        return out
    }

    private static func escapeBlockStart(_ s: String) -> String {
        guard let first = s.first else { return s }
        if first == "#" || first == ">" { return "\\" + s }
        if (first == "-" || first == "+"), s.dropFirst().first == " " { return "\\" + s }
        if first == "-", s.allSatisfy({ $0 == "-" }), s.count >= 3 { return "\\" + s }
        if first.isASCII, first.isNumber {
            let digits = s.prefix { $0.isASCII && $0.isNumber }
            let rest = s.dropFirst(digits.count)
            if let d = rest.first, d == "." || d == ")", rest.dropFirst().first == " " {
                return String(digits) + "\\" + rest
            }
        }
        return s
    }
}
