import Foundation

/// Lightweight SAX walker that hands out local element names and attributes
/// (namespace prefixes stripped).
private final class XMLWalker: NSObject, XMLParserDelegate {
    var onStart: (String, [String: String]) -> Void = { _, _ in }
    var onEnd: (String) -> Void = { _ in }
    var onText: (String) -> Void = { _ in }

    func walk(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = self
        parser.parse()
    }

    private static func local(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        var attrs: [String: String] = [:]
        for (key, value) in attributeDict { attrs[XMLWalker.local(key)] = value }
        onStart(XMLWalker.local(elementName), attrs)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        onEnd(XMLWalker.local(elementName))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        onText(string)
    }
}

enum DocxReader {
    static func read(_ data: Data) throws -> [Block] {
        let zip = try ZipArchive(data: data)
        guard let documentXML = try zip.data(for: "word/document.xml") else {
            throw ConversionError.invalidDocx("word/document.xml is missing")
        }

        var context = Context()
        if let styles = try zip.data(for: "word/styles.xml") { context.loadStyles(styles) }
        if let numbering = try zip.data(for: "word/numbering.xml") { context.loadNumbering(numbering) }
        if let rels = try zip.data(for: "word/_rels/document.xml.rels") { context.loadRelationships(rels) }
        return context.parseDocument(documentXML)
    }

    private struct Context {
        var styleNames: [String: String] = [:]
        var styleNumIds: [String: String] = [:]
        var relationships: [String: String] = [:]
        var abstractFormats: [String: [Int: Bool]] = [:]  // abstractNumId -> level -> ordered?
        var numToAbstract: [String: String] = [:]

        mutating func loadStyles(_ data: Data) {
            var names: [String: String] = [:]
            var numIds: [String: String] = [:]
            var current: String? = nil
            let walker = XMLWalker()
            walker.onStart = { name, attrs in
                switch name {
                case "style": current = attrs["styleId"]
                case "name": if let id = current, let v = attrs["val"] { names[id] = v }
                case "numId": if let id = current, let v = attrs["val"] { numIds[id] = v }
                default: break
                }
            }
            walker.onEnd = { name in if name == "style" { current = nil } }
            walker.walk(data)
            styleNames = names
            styleNumIds = numIds
        }

        mutating func loadNumbering(_ data: Data) {
            var formats: [String: [Int: Bool]] = [:]
            var toAbstract: [String: String] = [:]
            var abstractId: String? = nil
            var level: Int? = nil
            var numId: String? = nil
            let walker = XMLWalker()
            walker.onStart = { name, attrs in
                switch name {
                case "abstractNum": abstractId = attrs["abstractNumId"]
                case "lvl": level = attrs["ilvl"].flatMap { Int($0) }
                case "numFmt":
                    if let a = abstractId, let l = level, let v = attrs["val"] {
                        formats[a, default: [:]][l] = v != "bullet" && v != "none"
                    }
                case "num": numId = attrs["numId"]
                case "abstractNumId": if let n = numId, let v = attrs["val"] { toAbstract[n] = v }
                default: break
                }
            }
            walker.onEnd = { name in
                switch name {
                case "abstractNum": abstractId = nil
                case "lvl": level = nil
                case "num": numId = nil
                default: break
                }
            }
            walker.walk(data)
            abstractFormats = formats
            numToAbstract = toAbstract
        }

        mutating func loadRelationships(_ data: Data) {
            var rels: [String: String] = [:]
            let walker = XMLWalker()
            walker.onStart = { name, attrs in
                if name == "Relationship", let id = attrs["Id"], let target = attrs["Target"] { rels[id] = target }
            }
            walker.walk(data)
            relationships = rels
        }

        func isOrdered(numId: String, level: Int) -> Bool {
            guard let abstract = numToAbstract[numId] else { return false }
            return abstractFormats[abstract]?[level] ?? false
        }

        // swiftlint:disable:next function_body_length
        func parseDocument(_ data: Data) -> [Block] {
            var blocks: [Block] = []
            var codeLines: [String] = []

            var inParagraph = false
            var inParagraphProps = false
            var inRun = false
            var inRunProps = false
            var inText = false
            var pStyle: String? = nil
            var numId: String? = nil
            var level = 0
            var hasBottomBorder = false
            var runs: [Run] = []
            var current = Run(text: "")
            var linkTarget: String? = nil

            var tableDepth = 0
            var rows: [[[Run]]] = []
            var cells: [[Run]] = []
            var cellRuns: [Run] = []

            func flushCode() {
                if !codeLines.isEmpty {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines = []
                }
            }

            func isOn(_ attrs: [String: String]) -> Bool {
                guard let v = attrs["val"] else { return true }
                return !["0", "false", "off"].contains(v)
            }

            func finishParagraph() {
                inParagraph = false
                let merged = InlineParser.merge(runs)

                if tableDepth > 0 {
                    if !merged.isEmpty {
                        if !cellRuns.isEmpty { cellRuns.append(Run(text: " ")) }
                        cellRuns += merged
                    }
                    return
                }

                let name = (pStyle.flatMap { styleNames[$0] } ?? pStyle ?? "").lowercased()
                let plain = merged.map { $0.text }.joined()

                if name.contains("code") || name.contains("preformatted") || name.contains("verbatim") {
                    codeLines.append(plain)
                    return
                }
                flushCode()

                if name.hasPrefix("heading") || name == "title" {
                    if merged.isEmpty { return }
                    let digits = name.filter { $0.isNumber }
                    let lvl = name == "title" ? 1 : min(max(Int(digits) ?? 1, 1), 6)
                    blocks.append(.heading(lvl, merged))
                    return
                }

                var effectiveNumId = numId
                if effectiveNumId == nil, let style = pStyle { effectiveNumId = styleNumIds[style] }
                var ordered: Bool? = nil
                var itemLevel = level
                if let id = effectiveNumId, id != "0" {
                    ordered = isOrdered(numId: id, level: level)
                } else if name.contains("list bullet") || name.contains("list number") {
                    ordered = name.contains("list number")
                    if let d = Int(name.filter { $0.isNumber }), d > 1 { itemLevel = d - 1 }
                }
                if let ordered {
                    if !merged.isEmpty { blocks.append(.listItem(ordered: ordered, level: itemLevel, runs: merged)) }
                    return
                }

                if merged.isEmpty {
                    if hasBottomBorder { blocks.append(.rule) }
                    return
                }
                if name.contains("quote") || name.contains("block text") {
                    blocks.append(.quote(merged))
                } else {
                    blocks.append(.paragraph(merged))
                }
            }

            let walker = XMLWalker()
            walker.onStart = { name, attrs in
                switch name {
                case "tbl":
                    tableDepth += 1
                    if tableDepth == 1 { rows = [] }
                case "tr": if tableDepth == 1 { cells = [] }
                case "tc": if tableDepth == 1 { cellRuns = [] }
                case "p":
                    inParagraph = true
                    pStyle = nil
                    numId = nil
                    level = 0
                    hasBottomBorder = false
                    runs = []
                case "pPr": if inParagraph { inParagraphProps = true }
                case "pStyle": if inParagraphProps { pStyle = attrs["val"] }
                case "ilvl": if inParagraphProps { level = attrs["val"].flatMap { Int($0) } ?? 0 }
                case "numId": if inParagraphProps { numId = attrs["val"] }
                case "bottom": if inParagraphProps { hasBottomBorder = true }
                case "hyperlink": linkTarget = attrs["id"].flatMap { relationships[$0] }
                case "r":
                    inRun = true
                    current = Run(text: "", link: linkTarget)
                case "rPr": if inRun { inRunProps = true }
                case "b": if inRunProps { current.bold = isOn(attrs) }
                case "i": if inRunProps { current.italic = isOn(attrs) }
                case "strike", "dstrike": if inRunProps { current.strike = isOn(attrs) }
                case "rFonts":
                    if inRunProps {
                        let font = (attrs["ascii"] ?? attrs["hAnsi"] ?? "").lowercased()
                        if ["consolas", "courier", "menlo", "monaco", "mono"].contains(where: { font.contains($0) }) {
                            current.code = true
                        }
                    }
                case "t": if inRun { inText = true }
                case "tab": if inRun { current.text += " " }
                case "br", "cr": if inRun, attrs["type"] != "page" { current.text += "\n" }
                default: break
                }
            }
            walker.onEnd = { name in
                switch name {
                case "t": inText = false
                case "rPr": inRunProps = false
                case "r":
                    if !current.text.isEmpty { runs.append(current) }
                    inRun = false
                case "pPr": inParagraphProps = false
                case "hyperlink": linkTarget = nil
                case "p": finishParagraph()
                case "tc": if tableDepth == 1 { cells.append(InlineParser.merge(cellRuns)) }
                case "tr": if tableDepth == 1 { rows.append(cells) }
                case "tbl":
                    if tableDepth == 1, !rows.isEmpty {
                        flushCode()
                        blocks.append(.table(rows))
                    }
                    tableDepth -= 1
                default: break
                }
            }
            walker.onText = { string in if inText { current.text += string } }
            walker.walk(data)
            flushCode()
            return blocks
        }
    }
}
