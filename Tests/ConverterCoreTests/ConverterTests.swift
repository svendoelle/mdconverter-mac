import XCTest
@testable import ConverterCore

final class ConverterTests: XCTestCase {
    private let sample = """
    # Title

    Some **bold**, *italic* and `code` text with a [link](https://example.com).

    - one
    - two
        - nested

    1. first
    2. second

    > quoted words

    ```
    let x = 1
    ```

    | A | B |
    | --- | --- |
    | 1 | 2 |

    ---

    Last paragraph.
    """

    func testInlineParsing() {
        let runs = InlineParser.parse("a **b** *c* [d](http://x.y)")
        XCTAssertEqual(runs.map { $0.text }, ["a ", "b", " ", "c", " ", "d"])
        XCTAssertTrue(runs[1].bold)
        XCTAssertTrue(runs[3].italic)
        XCTAssertEqual(runs[5].link, "http://x.y")
    }

    func testBlockParsing() {
        let blocks = MarkdownParser.parse(sample)
        XCTAssertEqual(blocks.first, .heading(1, [Run(text: "Title")]))
        XCTAssertTrue(blocks.contains(.rule))
        XCTAssertTrue(blocks.contains(.code("let x = 1")))
        XCTAssertTrue(blocks.contains { if case .table(let rows) = $0 { return rows.count == 2 } else { return false } })
        let levels = blocks.compactMap { b -> Int? in
            if case .listItem(false, let level, _) = b { return level } else { return nil }
        }
        XCTAssertEqual(levels, [0, 0, 1])
    }

    func testZipRoundTrip() throws {
        var writer = ZipWriter()
        writer.add("a.txt", "hello")
        writer.add("dir/b.txt", "world")
        let archive = try ZipArchive(data: writer.finish())
        XCTAssertEqual(try archive.data(for: "a.txt"), Data("hello".utf8))
        XCTAssertEqual(try archive.data(for: "dir/b.txt"), Data("world".utf8))
        XCTAssertNil(try archive.data(for: "missing"))
    }

    func testMarkdownToDocxAndBack() throws {
        let docx = try Converter.markdownToDocx(sample)
        let md = try Converter.docxToMarkdown(docx)
        XCTAssertTrue(md.contains("# Title"), md)
        XCTAssertTrue(md.contains("**bold**"), md)
        XCTAssertTrue(md.contains("*italic*"), md)
        XCTAssertTrue(md.contains("`code`"), md)
        XCTAssertTrue(md.contains("[link](https://example.com)"), md)
        XCTAssertTrue(md.contains("- one\n- two\n    - nested"), md)
        XCTAssertTrue(md.contains("1. first\n2. second"), md)
        XCTAssertTrue(md.contains("> quoted words"), md)
        XCTAssertTrue(md.contains("```\nlet x = 1\n```"), md)
        XCTAssertTrue(md.contains("| A | B |\n| --- | --- |\n| 1 | 2 |"), md)
        XCTAssertTrue(md.contains("---"), md)
        XCTAssertTrue(md.contains("Last paragraph."), md)
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try Converter.docxToMarkdown(Data("not a zip".utf8)))
    }
}
