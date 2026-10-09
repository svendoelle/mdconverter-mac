import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: ConverterModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            dropZone
            Button {
                model.convert()
            } label: {
                Text(model.direction?.actionTitle ?? "Convert").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(model.direction == nil)

            statusView.frame(height: 22)
        }
        .padding(20)
        .frame(width: 420, height: 320)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.load(url)
            return true
        } isTargeted: {
            isTargeted = $0
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
            VStack(spacing: 8) {
                if let url = model.sourceURL {
                    Image(systemName: "doc.text").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text(url.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
                    if let direction = model.direction {
                        Text(direction.label).foregroundStyle(.secondary)
                    } else {
                        Text("Unsupported file type — use .md or .docx").foregroundStyle(.red)
                    }
                    Button("Choose Another File…") { model.chooseFile() }
                } else {
                    Image(systemName: "arrow.down.doc").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text("Drop a Markdown or Word file here").font(.headline)
                    Text("or").foregroundStyle(.secondary)
                    Button("Choose File…") { model.chooseFile() }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 190)
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.status {
        case .idle:
            EmptyView()
        case .done(let url):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Saved \(url.lastPathComponent)").lineLimit(1).truncationMode(.middle)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(.link)
            }
        case .failed(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).lineLimit(1).truncationMode(.tail).help(message)
            }
        }
    }
}
