// Checks keyword matching and the bridge ping format without audio or MIDI hardware.
//   swiftc -parse-as-library -swift-version 6 Sources/Talkback/KeywordMatcher.swift \
//     Sources/Talkback/KeywordRule.swift Sources/Talkback/MIDIEngine.swift \
//     Sources/Talkback/MIDIWire.swift scripts/LogicTest.swift -o /tmp/livecue-logic && /tmp/livecue-logic
import Foundation

@main
struct LogicTest {
    @MainActor static func main() {
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "PASS" : "FAIL", what)
            if !ok { failures += 1 }
        }
        func m(_ text: String, _ key: String, _ mode: MatchMode) -> Bool {
            KeywordMatcher.matches(text: text, keyword: key, mode: mode, caseSensitive: false)
        }

        check(m("Okay, front of house.", "Front of House", .contains), "contains ignores case and punctuation")
        check(m("Go to cue 1 now", "cue 1", .contains), "contains finds a whole phrase")
        check(!m("Go to cue 10 now", "cue 1", .contains), "\"cue 1\" does not match \"cue 10\"")
        check(!m("going home", "go", .contains), "\"go\" does not match \"going\"")
        check(m("Go.", "go", .exact), "exact ignores trailing punctuation")
        check(!m("Go now", "go", .exact), "exact needs the whole line")
        check(m("Go now", "go", .prefix), "prefix matches a first word")
        check(!m("Going now", "go", .prefix), "prefix needs a whole word")
        check(m("Cue 10.5 go", "cue 10.5", .contains), "decimal cue numbers stay together")
        check(m("Don’t stop", "don't stop", .contains), "curly and straight apostrophes match")
        check(!m("anything", "", .contains), "an empty keyword never matches")

        let ping = BridgePing.ping(nonce: 0x2A)
        check(ping == [0xF0, 0x7D, 0x4C, 0x43, 0x01, 0x2A, 0xF7], "ping bytes match the bridge")
        let reply = BridgePing.parseReply([0xF0, 0x7D, 0x4C, 0x43, 0x02, 0x2A, 0x01, 0x01, 0x01, 0xF7])
        check(reply?.nonce == 0x2A && reply?.wing == true && reply?.major == 1 && reply?.minor == 1, "reply parses nonce, WING flag and version")
        check(BridgePing.parseReply([0xB5, 0x10, 0x7F]) == nil, "lamp messages are not replies")
        check(BridgePing.isLiveCueSysEx(ping), "pings are recognised so they're never forwarded to a console")

        // Lamp flash patterns
        let d = LampFlashSettings.default
        check(d.schedule.count == 12 && d.schedule.first?.on == true && d.schedule.last?.on == false,
              "default pattern: 6 on/off pairs, starts ON, ends OFF")
        check(abs(d.totalSeconds - 2.75) < 0.001 && abs((d.schedule.last?.time ?? 0) - 2.75) < 0.001, "default lasts 2.75 s")
        let long = LampFlashSettings.presets.first { $0.name == "Long flash" }!.settings
        check(long.schedule.count == 2 && long.schedule[1].time == 3.0, "Long flash: on for 3 s, then off")
        let wild = LampFlashSettings(onSeconds: 0, offSeconds: 99, flashes: 500, brightness: 900).clamped
        check(wild.onSeconds == 0.1 && wild.offSeconds == 5 && wild.flashes == 20 && wild.brightness == 127,
              "out-of-range values are clamped to safe limits")
        let old = try? JSONDecoder().decode(LampFlashSettings.self, from: Data("{\"onSeconds\": 2}".utf8))
        check(old?.onSeconds == 2 && old?.flashes == 6 && old?.brightness == 127, "missing saved fields fall back to defaults")
        check(d.summary == "6 flashes, 0.25 s on / 0.25 s off, 2.75 s in all", "summary reads plainly: \(d.summary)")
        check(long.summary == "1 flash, 3 s on, 3 s in all", "single-flash summary: \(long.summary)")
        check(d.presetName == "Quick blink" && LampFlashSettings(onSeconds: 0.3).presetName == nil, "presets are recognised, custom isn't")

        print(failures == 0 ? "All logic checks passed" : "\(failures) check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
