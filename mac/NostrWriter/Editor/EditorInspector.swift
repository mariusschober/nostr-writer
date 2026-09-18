import SwiftUI
import WriterFoundation

/// Observable projection of the document's local-observation state for the
/// passage inspector. It shows what the app actually observed — origins, gaps,
/// annotations and the current proof-absence state — never a human score.
@MainActor
final class EditorInspectorModel: ObservableObject {
    struct AnnotationRow: Identifiable {
        let id: UUID
        let title: String
        let detail: String
        let isStale: Bool
    }

    @Published var recording = "Recording off"
    @Published var recordingDetail = "No detailed history is being stored."
    @Published var summary = ""
    @Published var gaps = ""
    @Published var notice = ""
    @Published var dictation = "Off"
    @Published var annotations: [AnnotationRow] = []
    @Published var selectedText = ""
    @Published var annotationKind: AnnotationKind = .quotation
    @Published var annotationDescription = ""
    @Published var annotationURL = ""
    @Published var canAnnotate = false

    var onMarkSource: ((AnnotationKind, String, String?) -> Void)?
    var onDeleteHistory: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onRemoveAnnotation: ((UUID) -> Void)?
    var onToggleDictation: (() -> Void)?

    let proofMessage = "NOT PROVABLE — no approved Mac capture profile and model are installed."
}

/// The passage inspector: recording state, source annotations bound to exact
/// ranges, honest capture gaps and the current proof-absence message.
struct EditorInspectorView: View {
    @ObservedObject var model: EditorInspectorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                group("Recording") {
                    Text(model.recording).font(.headline)
                    Text(model.recordingDetail).font(.caption).foregroundStyle(.secondary)
                    if !model.summary.isEmpty {
                        Text(model.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    if !model.gaps.isEmpty {
                        Text(model.gaps).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Pause / Resume") { model.onTogglePause?() }
                        Button("Delete Local History") { model.onDeleteHistory?() }
                    }
                    .controlSize(.small)
                }

                group("Dictation") {
                    Text(model.dictation).font(.caption).foregroundStyle(.secondary)
                    Button("Dictate On This Mac") { model.onToggleDictation?() }
                        .controlSize(.small)
                }

                group("Selected Passage") {
                    Text(model.selectedText.isEmpty ? "Select text to mark an external source." : model.selectedText)
                        .font(.caption)
                        .foregroundStyle(model.selectedText.isEmpty ? .secondary : .primary)
                        .lineLimit(6)
                    Picker("Category", selection: $model.annotationKind) {
                        Text("Quotation").tag(AnnotationKind.quotation)
                        Text("Citation / Reference").tag(AnnotationKind.citation)
                        Text("Assisted").tag(AnnotationKind.assisted)
                        Text("Imported").tag(AnnotationKind.imported)
                    }
                    .pickerStyle(.menu)
                    TextField("Source description", text: $model.annotationDescription)
                    TextField("Optional URL", text: $model.annotationURL)
                    Text("This material is not claimed as freshly composed.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Mark External Source") {
                        let url = model.annotationURL.trimmingCharacters(in: .whitespaces)
                        model.onMarkSource?(model.annotationKind, model.annotationDescription,
                                            url.isEmpty ? nil : url)
                    }
                    .disabled(!model.canAnnotate || model.annotationDescription.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                group("Marked Spans") {
                    if model.annotations.isEmpty {
                        Text("No marked spans.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(model.annotations) { row in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title).font(.caption).bold()
                                    Text(row.detail).font(.caption2).foregroundStyle(.secondary)
                                    if row.isStale {
                                        Text("Needs review — the marked wording changed.")
                                            .font(.caption2).foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                Button {
                                    model.onRemoveAnnotation?(row.id)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                group("Human Writing Proof") {
                    Text(model.proofMessage).font(.caption)
                    Text("This is not a judgment about who wrote your text.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                if !model.notice.isEmpty {
                    Text(model.notice).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 240)
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2).foregroundStyle(.secondary)
            content()
        }
    }
}
