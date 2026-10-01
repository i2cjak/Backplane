import PDFKit
import SwiftUI

// The viewer's Files tab (client.bend's Fm, mobile/view.bend's Files.json):
// the project's folders and files; a board, schematic or model opens in the
// viewer, an image or a PDF here (a PDF in PDFKit's own view).

// a row's icon, by the name core/icons.bend gives it
private func fileSymbol(_ name: String) -> String {
    switch name {
    case "folder": return "folder.fill"
    case "circuit-board": return "cpu"
    case "cpu": return "memorychip"
    case "box": return "cube"
    case "image": return "photo"
    case "file-text": return "doc.richtext"
    default: return "doc"
    }
}

// the viewer's choices (Board, Schematic, 3D, Mech, Files) and its close button
private struct ViewerChoices: View {
    let model: AppModel
    let viewer: Viewer

    var body: some View {
        HStack {
            Picker("Source", selection: Binding(get: { viewer.choices.first(where: { $0.on })?.value ?? viewer.open }, set: { model.act("view", $0) })) {
                ForEach(viewer.choices, id: \.value) { Text($0.label).tag($0.value) }
            }
            .pickerStyle(.segmented)
            Spacer()
            Button { model.act("view", "") } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                .accessibilityLabel("Close")
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}

struct FilesScreen: View {
    let model: AppModel
    let viewer: Viewer
    let page: FilesPage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewerChoices(model: model, viewer: viewer)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(page.trail, id: \.self) { c in
                        Button(c.label) { model.act(c.action, c.value) }
                            .buttonStyle(.borderless)
                            .foregroundStyle(c == page.trail.last ? .primary : .secondary)
                        if c != page.trail.last { Text("/").foregroundStyle(.tertiary) }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            Divider()
            if !page.ready {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if page.rows.isEmpty {
                Text("This folder is empty").foregroundStyle(.secondary).padding()
                Spacer()
            } else {
                List(page.rows, id: \.value) { r in
                    Button { model.act(r.action, r.value) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: fileSymbol(r.icon))
                                .foregroundStyle(r.kind == "folder" ? Color.accentColor : (r.action.isEmpty ? .secondary : .primary))
                                .frame(width: 22)
                            Text(r.label).lineLimit(1).truncationMode(.middle)
                                .foregroundStyle(r.action.isEmpty ? .secondary : .primary)
                            Spacer()
                            if !r.detail.isEmpty { Text(r.detail).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .disabled(r.action.isEmpty)
                }
                .listStyle(.plain)
            }
        }
    }
}

// a PDF from the hub, in PDFKit's view (scroll, pinch, find)
private struct PDFPages: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.document = document
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        if v.document !== document { v.document = document }
    }
}

// an image or a PDF opened from the Files tab, under its name and a way back
struct FileScreen: View {
    let model: AppModel
    let viewer: Viewer
    let file: FileView
    @State private var shown: Shown?
    @State private var pdf: PDFDocument?
    @State private var failed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewerChoices(model: model, viewer: viewer)
            HStack {
                Button { model.act("fm") } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Back to the folder")
                Text(file.name).lineLimit(1).truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            Divider()
            if file.kind == "pdf" {
                if let d = pdf { PDFPages(document: d) }
                else if !failed.isEmpty { Text(failed).foregroundStyle(.secondary).padding(); Spacer() }
                else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else if let u = model.web(file.url) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit().onTapGesture { shown = Shown(url: u) }
                    case .failure: Text("This image cannot be shown here").foregroundStyle(.secondary)
                    default: ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .task(id: file.url) { await load() }
        .fullScreenCover(item: $shown) { s in Lightbox(shown: s) { shown = nil } }
    }

    // the PDF fetched whole, then handed to PDFKit
    private func load() async {
        guard file.kind == "pdf", let u = model.web(file.url) else { return }
        pdf = nil
        failed = ""
        do {
            let (data, resp) = try await URLSession.shared.data(from: u)
            if (resp as? HTTPURLResponse)?.statusCode != 200 { failed = "The hub could not send this PDF (it may be over 12 MB)"; return }
            if let d = PDFDocument(data: data) { pdf = d } else { failed = "This PDF cannot be shown here" }
        } catch {
            failed = "This PDF cannot be shown here"
        }
    }
}
