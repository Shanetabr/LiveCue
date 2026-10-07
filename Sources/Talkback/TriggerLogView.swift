import SwiftUI

// Ableton Live Theme Colors
private let abletonBg = Color(red: 0.11, green: 0.11, blue: 0.11)
private let abletonSurface = Color(red: 0.16, green: 0.16, blue: 0.16)
private let abletonCard = Color(red: 0.20, green: 0.20, blue: 0.20)
private let abletonBorder = Color(red: 0.28, green: 0.28, blue: 0.28)
private let abletonMint = Color(red: 0.0, green: 0.90, blue: 0.46)     // #00E575
private let abletonAmber = Color(red: 1.0, green: 0.65, blue: 0.10)    // #FFA71A

struct TriggerLogView: View {
    var model: Model

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SHOW CONTROL EVENT LOG")
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("Real-time audit history of fired keyword cues and dispatched MIDI packets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("CLEAR LOG") {
                    model.triggerLogs.removeAll()
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(white: 0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(abletonCard)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(abletonBorder, lineWidth: 1))
                .disabled(model.triggerLogs.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(abletonSurface)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(abletonBorder), alignment: .bottom)

            if model.triggerLogs.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 40))
                        .foregroundStyle(Color(white: 0.4))
                    Text("NO TRIGGER EVENTS RECORDED")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("When spoken keywords match active rules, fired cues will appear here with millisecond timestamps and track origins.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.triggerLogs) { log in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(Self.timeFormatter.string(from: log.timestamp))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color(white: 0.5))

                                if let ch = log.channelName {
                                    Text(ch.uppercased())
                                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(abletonMint)
                                        .cornerRadius(3)
                                }

                                Text("\"\(log.ruleKeyword)\"")
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(.white)

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(white: 0.45))

                                Text(log.description)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(abletonAmber)

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(abletonCard)
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(abletonBorder, lineWidth: 1))
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(abletonBg)
    }
}
