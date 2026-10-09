import Foundation

/// Parses inline Markdown (emphasis, code, links) into formatted runs.
enum InlineParser {
    static func parse(_ source: String) -> [Run] {
        merge(parse(Array(source), base: Run(text: "")))
    }

    static func merge(_ runs: [Run]) -> [Run] {
        var result: [Run] = []
        for run in runs where !run.text.isEmpty {
            if var last = result.last, last.sameFormat(as: run) {
                last.text += run.text
                result[result.count - 1] = last
            } else {
                result.append(run)
            }
        }
        return result
    }

    private static let escapable = Set("\\`*_{}[]()#+-.!|~<>")

    private struct Link {
        var label: Range<Int>
        var url: String
        var end: Int
    }

    private static func parse(_ chars: [Character], base: Run) -> [Run] {
        var out: [Run] = []
        var buf = ""
        var i = 0
        let n = chars.count

        func flush() {
            if !buf.isEmpty {
                var r = base
                r.text = buf
                out.append(r)
                buf = ""
            }
        }

        while i < n {
            let c = chars[i]

            if c == "\\", i + 1 < n, escapable.contains(chars[i + 1]) {
                buf.append(chars[i + 1])
                i += 2
                continue
            }

            if c == "`" {
                var k = 0
                while i + k < n, chars[i + k] == "`" { k += 1 }
                if let close = findBacktickRun(chars, from: i + k, length: k) {
                    flush()
                    var code = String(chars[(i + k)..<close]).replacingOccurrences(of: "\n", with: " ")
                    if code.count > 2, code.hasPrefix(" "), code.hasSuffix(" ") {
                        code = String(code.dropFirst().dropLast())
                    }
                    var r = base
                    r.text = code
                    r.code = true
                    out.append(r)
                    i = close + k
                } else {
                    buf += String(repeating: "`", count: k)
                    i += k
                }
                continue
            }

            if c == "!", i + 1 < n, chars[i + 1] == "[", let link = parseLink(chars, at: i + 1) {
                flush()
                let alt = String(chars[link.label])
                var r = base
                r.text = alt.isEmpty ? "[image]" : alt
                out.append(r)
                i = link.end
                continue
            }

            if c == "[", let link = parseLink(chars, at: i) {
                flush()
                var b = base
                b.link = link.url
                out += parse(Array(chars[link.label]), base: b)
                i = link.end
                continue
            }

            if c == "<", let close = chars[i...].firstIndex(of: ">") {
                let inner = String(chars[(i + 1)..<close])
                let lower = inner.lowercased()
                if lower == "br" || lower == "br/" || lower == "br /" {
                    buf.append("\n")
                    i = close + 1
                    continue
                }
                if inner.contains("://"), !inner.contains(" ") {
                    flush()
                    var b = base
                    b.link = inner
                    b.text = inner
                    out.append(b)
                    i = close + 1
                    continue
                }
            }

            if c == "*" || c == "_" || c == "~" {
                var run = 1
                while i + run < n, chars[i + run] == c { run += 1 }
                let intraword = c == "_" && i > 0 && (chars[i - 1].isLetter || chars[i - 1].isNumber)
                let valid = !intraword && run <= 3 && (c != "~" || run == 2)
                if valid,
                   let close = findClosing(chars, from: i + run, marker: c, count: run),
                   close > i + run, !chars[i + run].isWhitespace {
                    flush()
                    var b = base
                    switch (c, run) {
                    case ("~", _): b.strike = true
                    case (_, 3): b.bold = true; b.italic = true
                    case (_, 2): b.bold = true
                    default: b.italic = true
                    }
                    out += parse(Array(chars[(i + run)..<close]), base: b)
                    i = close + run
                } else {
                    buf += String(repeating: c, count: run)
                    i += run
                }
                continue
            }

            buf.append(c)
            i += 1
        }
        flush()
        return out
    }

    private static func findBacktickRun(_ chars: [Character], from: Int, length: Int) -> Int? {
        var j = from
        let n = chars.count
        while j < n {
            if chars[j] == "`" {
                var k = 0
                while j + k < n, chars[j + k] == "`" { k += 1 }
                if k == length { return j }
                j += k
            } else {
                j += 1
            }
        }
        return nil
    }

    /// Finds the start index of the closing delimiter run for an emphasis span.
    private static func findClosing(_ chars: [Character], from: Int, marker: Character, count: Int) -> Int? {
        let n = chars.count
        var j = from
        while j < n {
            let c = chars[j]
            if c == "\\" { j += 2; continue }
            if c == "`" {
                var k = 0
                while j + k < n, chars[j + k] == "`" { k += 1 }
                if let close = findBacktickRun(chars, from: j + k, length: k) { j = close + k } else { j += k }
                continue
            }
            if c == marker {
                var run = 0
                while j + run < n, chars[j + run] == marker { run += 1 }
                let fits = count == 1 ? run == 1 : run >= count
                let start = j + run - count
                if fits, start > from - 1, j > from, !chars[j - 1].isWhitespace {
                    if marker == "_", j + run < n, chars[j + run].isLetter || chars[j + run].isNumber {
                        j += run
                        continue
                    }
                    return start
                }
                j += run
                continue
            }
            j += 1
        }
        return nil
    }

    private static func parseLink(_ chars: [Character], at start: Int) -> Link? {
        let n = chars.count
        var depth = 0
        var j = start
        while j < n {
            if chars[j] == "\\" { j += 2; continue }
            if chars[j] == "[" {
                depth += 1
            } else if chars[j] == "]" {
                depth -= 1
                if depth == 0 { break }
            }
            j += 1
        }
        guard j < n, j + 1 < n, chars[j + 1] == "(" else { return nil }
        var k = j + 2
        var parens = 1
        while k < n {
            if chars[k] == "(" {
                parens += 1
            } else if chars[k] == ")" {
                parens -= 1
                if parens == 0 { break }
            }
            k += 1
        }
        guard k < n else { return nil }
        var dest = String(chars[(j + 2)..<k]).trimmingCharacters(in: .whitespaces)
        if dest.hasPrefix("<"), let gt = dest.firstIndex(of: ">") {
            dest = String(dest[dest.index(after: dest.startIndex)..<gt])
        } else if let space = dest.firstIndex(of: " ") {
            dest = String(dest[..<space])
        }
        return Link(label: (start + 1)..<j, url: dest, end: k + 1)
    }
}
