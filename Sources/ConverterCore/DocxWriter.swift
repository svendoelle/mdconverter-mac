import Foundation

/// Builds a minimal but complete WordprocessingML package from the document model.
enum DocxWriter {
    static func write(_ blocks: [Block]) -> Data {
        let builder = Builder()
        let body = builder.body(blocks)

        var zip = ZipWriter()
        zip.add("[Content_Types].xml", contentTypes)
        zip.add("_rels/.rels", rootRels)
        zip.add("word/document.xml", builder.documentXML(body: body))
        zip.add("word/_rels/document.xml.rels", builder.relsXML())
        zip.add("word/styles.xml", stylesXML)
        zip.add("word/numbering.xml", numberingXML(orderedLists: builder.orderedLists))
        return zip.finish()
    }

    private static let xmlHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    private static let wNS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    private static let rNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    private static let contentTypes = xmlHeader + """
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
    <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>\
    <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>\
    </Types>
    """

    private static let rootRels = xmlHeader + """
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="\(rNS)/officeDocument" Target="word/document.xml"/>\
    </Relationships>
    """

    // MARK: Styles

    private static let stylesXML: String = {
        let headingSizes = [40, 32, 28, 24, 22, 22]
        var headings = ""
        for level in 1...6 {
            let size = headingSizes[level - 1]
            let color = level <= 2 ? "1F3864" : "2F5496"
            headings += """
            <w:style w:type="paragraph" w:styleId="Heading\(level)"><w:name w:val="heading \(level)"/>\
            <w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:uiPriority w:val="9"/><w:qFormat/>\
            <w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="\(level == 1 ? 360 : 240)" w:after="120"/><w:outlineLvl w:val="\(level - 1)"/></w:pPr>\
            <w:rPr><w:b/><w:color w:val="\(color)"/><w:sz w:val="\(size)"/><w:szCs w:val="\(size)"/></w:rPr></w:style>
            """
        }
        return xmlHeader + """
        <w:styles xmlns:w="\(wNS)">\
        <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/>\
        <w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault>\
        <w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="259" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>\
        <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>\
        <w:style w:type="character" w:default="1" w:styleId="DefaultParagraphFont"><w:name w:val="Default Paragraph Font"/><w:uiPriority w:val="1"/><w:semiHidden/></w:style>\
        <w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/><w:uiPriority w:val="99"/><w:semiHidden/>\
        <w:tblPr><w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>\
        \(headings)\
        <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:uiPriority w:val="29"/><w:qFormat/>\
        <w:pPr><w:pBdr><w:left w:val="single" w:sz="18" w:space="8" w:color="BFBFBF"/></w:pBdr><w:ind w:left="567"/></w:pPr><w:rPr><w:i/><w:color w:val="595959"/></w:rPr></w:style>\
        <w:style w:type="paragraph" w:styleId="Code"><w:name w:val="Code"/><w:basedOn w:val="Normal"/><w:qFormat/>\
        <w:pPr><w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>\
        <w:rPr><w:rFonts w:ascii="Menlo" w:hAnsi="Menlo" w:cs="Menlo"/><w:sz w:val="19"/><w:szCs w:val="19"/></w:rPr></w:style>\
        <w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:uiPriority w:val="34"/><w:qFormat/>\
        <w:pPr><w:spacing w:after="60"/><w:ind w:left="720"/></w:pPr></w:style>\
        <w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:uiPriority w:val="99"/><w:rPr><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr></w:style>\
        <w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:basedOn w:val="TableNormal"/><w:uiPriority w:val="39"/>\
        <w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/><w:left w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>\
        <w:bottom w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/><w:right w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>\
        <w:insideH w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/></w:tblBorders></w:tblPr></w:style>\
        </w:styles>
        """
    }()

    // MARK: Numbering

    private static func numberingXML(orderedLists: Int) -> String {
        var bullets = ""
        var decimals = ""
        let bulletChars = ["•", "◦", "▪"]
        let formats = ["decimal", "lowerLetter", "lowerRoman"]
        for level in 0..<9 {
            let left = 720 + 360 * level
            bullets += """
            <w:lvl w:ilvl="\(level)"><w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="\(bulletChars[level % 3])"/>\
            <w:lvlJc w:val="left"/><w:pPr><w:ind w:left="\(left)" w:hanging="360"/></w:pPr></w:lvl>
            """
            decimals += """
            <w:lvl w:ilvl="\(level)"><w:start w:val="1"/><w:numFmt w:val="\(formats[level % 3])"/><w:lvlText w:val="%\(level + 1)."/>\
            <w:lvlJc w:val="left"/><w:pPr><w:ind w:left="\(left)" w:hanging="360"/></w:pPr></w:lvl>
            """
        }
        var nums = "<w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num>"
        if orderedLists > 0 {
            for k in 1...orderedLists {
                nums += "<w:num w:numId=\"\(k + 1)\"><w:abstractNumId w:val=\"1\"/>"
                    + "<w:lvlOverride w:ilvl=\"0\"><w:startOverride w:val=\"1\"/></w:lvlOverride></w:num>"
            }
        }
        return xmlHeader + """
        <w:numbering xmlns:w="\(wNS)">\
        <w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="hybridMultilevel"/>\(bullets)</w:abstractNum>\
        <w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="hybridMultilevel"/>\(decimals)</w:abstractNum>\
        \(nums)</w:numbering>
        """
    }

    // MARK: Body

    final class Builder {
        private(set) var orderedLists = 0
        private var linkIds: [String: String] = [:]
        private var linkOrder: [String] = []

        func documentXML(body: String) -> String {
            xmlHeader + "<w:document xmlns:w=\"\(wNS)\" xmlns:r=\"\(rNS)\"><w:body>" + body
                + "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/>"
                + "<w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"708\" w:footer=\"708\" w:gutter=\"0\"/>"
                + "</w:sectPr></w:body></w:document>"
        }

        func relsXML() -> String {
            var xml = xmlHeader + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            xml += "<Relationship Id=\"rId1\" Type=\"\(rNS)/styles\" Target=\"styles.xml\"/>"
            xml += "<Relationship Id=\"rId2\" Type=\"\(rNS)/numbering\" Target=\"numbering.xml\"/>"
            for url in linkOrder {
                xml += "<Relationship Id=\"\(linkIds[url]!)\" Type=\"\(rNS)/hyperlink\" Target=\"\(escape(url))\" TargetMode=\"External\"/>"
            }
            return xml + "</Relationships>"
        }

        func body(_ blocks: [Block]) -> String {
            var xml = ""
            var orderedActive = false
            for block in blocks {
                switch block {
                case .heading(let level, let runs):
                    xml += paragraph(style: "Heading\(min(max(level, 1), 6))", runs: runs)
                    orderedActive = false
                case .paragraph(let runs):
                    xml += paragraph(style: nil, runs: runs)
                    orderedActive = false
                case .quote(let runs):
                    xml += paragraph(style: "Quote", runs: runs)
                    orderedActive = false
                case .listItem(let ordered, let rawLevel, let runs):
                    let level = min(rawLevel, 8)
                    var numId = 1
                    if ordered {
                        if !orderedActive {
                            orderedLists += 1
                            orderedActive = true
                        }
                        numId = orderedLists + 1
                    } else if level == 0 {
                        orderedActive = false
                    }
                    let props = "<w:pStyle w:val=\"ListParagraph\"/><w:numPr><w:ilvl w:val=\"\(level)\"/><w:numId w:val=\"\(numId)\"/></w:numPr>"
                    xml += "<w:p><w:pPr>\(props)</w:pPr>\(runsXML(runs))</w:p>"
                case .code(let code):
                    for line in code.components(separatedBy: "\n") {
                        let text = line.replacingOccurrences(of: "\t", with: "    ")
                        let run = text.isEmpty ? "" : "<w:r><w:t xml:space=\"preserve\">\(escape(text))</w:t></w:r>"
                        xml += "<w:p><w:pPr><w:pStyle w:val=\"Code\"/></w:pPr>\(run)</w:p>"
                    }
                    orderedActive = false
                case .rule:
                    xml += "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"A6A6A6\"/></w:pBdr></w:pPr></w:p>"
                    orderedActive = false
                case .table(let rows):
                    xml += table(rows)
                    orderedActive = false
                }
            }
            return xml.isEmpty ? "<w:p/>" : xml
        }

        private func paragraph(style: String?, runs: [Run]) -> String {
            let pPr = style.map { "<w:pPr><w:pStyle w:val=\"\($0)\"/></w:pPr>" } ?? ""
            return "<w:p>\(pPr)\(runsXML(runs))</w:p>"
        }

        private func table(_ rows: [[[Run]]]) -> String {
            guard !rows.isEmpty else { return "" }
            let cols = max(rows.map { $0.count }.max() ?? 1, 1)
            let width = 9026 / cols
            var xml = "<w:tbl><w:tblPr><w:tblStyle w:val=\"TableGrid\"/><w:tblW w:w=\"5000\" w:type=\"pct\"/><w:tblLook w:val=\"0420\" w:firstRow=\"1\" w:lastRow=\"0\" w:firstColumn=\"0\" w:lastColumn=\"0\" w:noHBand=\"0\" w:noVBand=\"1\"/></w:tblPr>"
            xml += "<w:tblGrid>" + String(repeating: "<w:gridCol w:w=\"\(width)\"/>", count: cols) + "</w:tblGrid>"
            for (r, row) in rows.enumerated() {
                let header = r == 0
                xml += "<w:tr>" + (header ? "<w:trPr><w:tblHeader/></w:trPr>" : "")
                for c in 0..<cols {
                    let runs = c < row.count ? row[c] : []
                    let shade = header ? "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"F2F2F2\"/>" : ""
                    xml += "<w:tc><w:tcPr><w:tcW w:w=\"\(width)\" w:type=\"dxa\"/>\(shade)</w:tcPr>"
                    xml += "<w:p><w:pPr><w:spacing w:after=\"0\"/></w:pPr>\(runsXML(runs, forceBold: header))</w:p></w:tc>"
                }
                xml += "</w:tr>"
            }
            return xml + "</w:tbl><w:p/>"
        }

        private func runsXML(_ runs: [Run], forceBold: Bool = false) -> String {
            var xml = ""
            var i = 0
            while i < runs.count {
                if let url = runs[i].link {
                    var inner = ""
                    var j = i
                    while j < runs.count, runs[j].link == url {
                        inner += runXML(runs[j], forceBold: forceBold)
                        j += 1
                    }
                    xml += "<w:hyperlink r:id=\"\(relationshipId(for: url))\" w:history=\"1\">\(inner)</w:hyperlink>"
                    i = j
                } else {
                    xml += runXML(runs[i], forceBold: forceBold)
                    i += 1
                }
            }
            return xml
        }

        private func relationshipId(for url: String) -> String {
            if let id = linkIds[url] { return id }
            let id = "rId\(10 + linkOrder.count)"
            linkIds[url] = id
            linkOrder.append(url)
            return id
        }

        private func runXML(_ run: Run, forceBold: Bool) -> String {
            var props = ""
            if run.link != nil { props += "<w:rStyle w:val=\"Hyperlink\"/>" }
            if run.code { props += "<w:rFonts w:ascii=\"Menlo\" w:hAnsi=\"Menlo\" w:cs=\"Menlo\"/>" }
            if run.bold || forceBold { props += "<w:b/>" }
            if run.italic { props += "<w:i/>" }
            if run.strike { props += "<w:strike/>" }
            if run.code { props += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"F2F2F2\"/>" }
            let rPr = props.isEmpty ? "" : "<w:rPr>\(props)</w:rPr>"
            let parts = run.text.components(separatedBy: "\n")
            var content = ""
            for (idx, part) in parts.enumerated() {
                if idx > 0 { content += "<w:br/>" }
                if !part.isEmpty { content += "<w:t xml:space=\"preserve\">\(escape(part))</w:t>" }
            }
            return "<w:r>\(rPr)\(content)</w:r>"
        }

        private func escape(_ s: String) -> String {
            var out = ""
            for scalar in s.unicodeScalars {
                switch scalar {
                case "&": out += "&amp;"
                case "<": out += "&lt;"
                case ">": out += "&gt;"
                case "\"": out += "&quot;"
                default:
                    if scalar.value >= 0x20 || scalar == "\t" || scalar == "\n" || scalar == "\r" {
                        out.unicodeScalars.append(scalar)
                    }
                }
            }
            return out
        }
    }
}
