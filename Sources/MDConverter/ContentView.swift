import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: ConverterModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 16) {
            dropZone
            targetPicker
            Button {
                model.convert()
            } label: {
                Text(model.target.map { "Convert to \($0.label)…" } ?? "Convert").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(model.target == nil)

            statusView.frame(height: 22)
        }
        .padding(20)
        .frame(width: 420, height: 350)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.load(url)
            return true
        } isTargeted: {
            isTargeted = $0
        }
    }

    @ViewBuilder
    private var targetPicker: some View {
        if let source = model.source {
            HStack {
                Text("Convert to")
                if source.targets.count > 1 {
                    Picker("", selection: Binding(get: { model.target ?? source.targets[0] }, set: { model.target = $0 })) {
                        ForEach(source.targets, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } else {
                    Text(source.targets[0].label).bold()
                    Spacer()
                }
            }
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
                    if let source = model.source {
                        Text("\(source.label) file").foregroundStyle(.secondary)
                    } else {
                        Text("Unsupported file type — use .md, .docx or .pdf").foregroundStyle(.red)
                    }
                    Button("Choose Another File…") { model.chooseFile() }
                } else {
                    Image(systemName: "arrow.down.doc").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text("Drop a Markdown, Word or PDF file here").font(.headline)
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
