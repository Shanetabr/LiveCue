import AVFoundation
import SwiftUI

struct LiveCueApp: App {
    @State private var model = Model()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onOpenURL { url in
                    model.openURL(url)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session") {
                    model.newSession()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open…") {
                    model.openFile()
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    if model.recentDocumentURLs.isEmpty {
                        Text("No Recent Sessions")
                    } else {
                        ForEach(model.recentDocumentURLs, id: \.self) { url in
                            Button(url.deletingPathExtension().lastPathComponent) {
                                model.openURL(url)
                            }
                        }
                        Divider()
                        Button("Clear Menu") {
                            model.clearRecentDocuments()
                        }
                    }
                }
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    model.save()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As…") {
                    model.saveAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}

/// `LiveCue --file speech.wav [channel]` runs a sound file through the same
/// path as the live input and prints what was heard. No microphone, no window.
@MainActor
func checkFile(_ path: String, channel: Int) async -> Int32 {
    do {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let transcriber = try await Transcriber.make { print($0) }
        let feeder = ChannelFeeder(channel: channel, target: transcriber.format)
        try await transcriber.start(
            onResult: { text, final in print(final ? "final:   \(text)" : "partial: \(text)") },
            onError: { print("error: \($0.localizedDescription)") })
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else { break }
            try file.read(into: buffer)
            if let out = feeder.feed(buffer) { transcriber.send(out) }
        }
        await transcriber.finish()
        return 0
    } catch {
        print("error: \(error.localizedDescription)")
        return 1
    }
}

let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--file"), arguments.count > flag + 1 {
    let channel = arguments.count > flag + 2 ? max(0, (Int(arguments[flag + 2]) ?? 1) - 1) : 0
    Task {
        exit(await checkFile(arguments[flag + 1], channel: channel))
    }
    dispatchMain()
} else {
    LiveCueApp.main()
}
