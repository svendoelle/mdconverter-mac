# MD Converter

A small native macOS app (SwiftUI, no dependencies) that converts a single file
between Markdown (`.md`) and Word (`.docx`). Drop a file on the window or use
**Choose File…**; the direction is picked from the file extension.

Supported: headings, paragraphs, bold/italic/strikethrough, inline code, links,
nested bullet and numbered lists, block quotes, code blocks, horizontal rules, tables.
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
