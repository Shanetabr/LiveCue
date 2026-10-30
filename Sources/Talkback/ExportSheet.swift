import SwiftUI
import AppKit

// Ableton Live Theme Colors
private let abletonBg = Color(red: 0.11, green: 0.11, blue: 0.11)
private let abletonCard = Color(red: 0.20, green: 0.20, blue: 0.20)
private let abletonBorder = Color(red: 0.28, green: 0.28, blue: 0.28)
private let abletonMint = Color(red: 0.0, green: 0.90, blue: 0.46)     // #00E575

struct ExportSheet: View {
    var model: Model
    @Binding var isPresented: Bool

    @State private var selectedFormat: ExportFormat = .txt
    @State private var copiedNotice = false

    @State private var exportedContent = ""
    @State private var exportError: String?
    @State private var exportedLineCount = 0

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("EXPORT SHOW TRANSCRIPT")
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
            }

            Picker("Format", selection: $selectedFormat) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 6) {
                Text("PREVIEW (\(exportedLineCount) LINES):")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(white: 0.6))

                ScrollView {
                    Text(exportError ?? (exportedContent.isEmpty ? "(Transcript is empty)" : exportedContent))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color(white: 0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(abletonBorder, lineWidth: 1))
                .frame(height: 220)
            }
            .padding(.horizontal)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if copiedNotice {
                    Text("COPIED TO CLIPBOARD")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(abletonMint)
                }

                Button("COPY CLIPBOARD") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(exportedContent, forType: .string)
                    copiedNotice = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedNotice = false
                    }
                }
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(abletonCard)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(abletonBorder, lineWidth: 1))
                .disabled(exportedContent.isEmpty || exportError != nil)

                Button("SAVE FILE…") {
                    saveToFile()
                }
                .buttonStyle(.borderedProminent)
                .tint(abletonMint)
                .foregroundStyle(.black)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .disabled(exportedContent.isEmpty || exportError != nil)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(16)
        .frame(minWidth: 540, minHeight: 400)
        .onAppear { refreshExport() }
        .onChange(of: selectedFormat) { _, _ in
            refreshExport()
        }
        .background(abletonBg)
    }

    private func refreshExport() {
        do {
            exportedContent = try model.exportTranscript(format: selectedFormat)
            exportedLineCount = model.transcriptLineCount
            exportError = nil
        } catch {
            exportedContent = ""
            exportError = "Could not read transcript: \(error.localizedDescription)"
        }
    }

    private func saveToFile() {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let timestamp = formatter.string(from: Date())
        savePanel.nameFieldStringValue = "LiveCue_Transcript_\(timestamp).\(selectedFormat.fileExtension)"
        savePanel.allowedContentTypes = []

        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? exportedContent.write(to: url, atomically: true, encoding: .utf8)
            isPresented = false
        }
    }
}
