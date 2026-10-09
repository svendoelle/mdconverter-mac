# MD Converter

A small native macOS app (SwiftUI, no dependencies) that converts a single file
between Markdown (`.md`), Word (`.docx`) and PDF: Markdown → Word/PDF,
Word → Markdown/PDF, PDF → Markdown. Drop a file on the window or use
**Choose File…**; the source format comes from the file extension and you pick the target.

Supported: headings, paragraphs, bold/italic/strikethrough, inline code, links,
nested bullet and numbered lists, block quotes, code blocks, horizontal rules, tables.
PDF → Markdown is heuristic (headings from font size, lists, bold/italic) and text only: images,
tables and columns are not recovered, and scanned PDFs without a text layer are rejected.
Not supported yet: images, footnotes, comments, tracked changes.

## Build

Requires macOS 13+ and the Xcode command line tools (`xcode-select --install`).
`swift test` additionally needs the full Xcode app (XCTest); CI runs the tests on every push.

```sh
swift test               # run the tests (needs full Xcode)
./scripts/build_app.sh   # creates build/MD Converter.app (universal, ad-hoc signed)
```

For development you can also run `swift run MDConverter`.

An app downloaded from CI is not notarized: right-click → Open the first time,
or run `xattr -dr com.apple.quarantine "MD Converter.app"`.
