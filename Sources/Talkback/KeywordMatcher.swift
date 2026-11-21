import Foundation
import Observation

// Scans incoming transcript text against keyword rules and fires actions
@Observable
class KeywordMatcher {
    var rules: [KeywordRule] = []
    private var lastTriggerTimes: [UUID: Date] = [:]  // for cooldown
    
    init(rules: [KeywordRule] = []) {
        self.rules = rules
    }
    
    // Called by Model when new transcript text arrives (both partial and final)
    // Returns the list of rules that matched (so the caller can fire the actions)
    func match(text: String, channelID: UUID?, isFinal: Bool) -> [KeywordRule] {
        // Only trigger on final text by default (partial text causes jitter)
        // For now, we strictly only match on final text.
        // If rules opt-in to partial matching later, we can check it here.
        guard isFinal else {
            return []
        }
        
        let now = Date()
        var matchedRules: [KeywordRule] = []
        
        for rule in rules where rule.enabled {
            // Check channel filter
            if let filter = rule.channelFilter, filter != channelID {
                continue
            }
            
            // Check cooldown
            if let lastTime = lastTriggerTimes[rule.id] {
                if now.timeIntervalSince(lastTime) < rule.cooldownSeconds {
                    continue
                }
            }
            
            if Self.matches(text: text, keyword: rule.keyword, mode: rule.matchMode, caseSensitive: rule.caseSensitive) {
                matchedRules.append(rule)
                lastTriggerTimes[rule.id] = now
            }
        }
        
        return matchedRules
    }

    /// Whole-word matching on speech text. "cue 1" does not match "cue 10", and
    /// punctuation the speech engine adds ("Go.", "Front of House!") is ignored.
    static func matches(text: String, keyword: String, mode: MatchMode, caseSensitive: Bool) -> Bool {
        let source = normalize(text, caseSensitive: caseSensitive)
        let key = normalize(keyword, caseSensitive: caseSensitive)
        guard !key.isEmpty else { return false }
        switch mode {
        case .exact:
            return source == key
        case .prefix:
            return source == key || source.hasPrefix(key + " ")
        case .contains:
            return source == key || source.hasPrefix(key + " ") || source.hasSuffix(" " + key)
                || source.contains(" " + key + " ")
        }
    }

    /// Lowercases (unless case-sensitive), turns punctuation into spaces and
    /// collapses runs of whitespace, so words line up on single spaces.
    /// Apostrophes and decimal points inside words stay ("don't", "10.5").
    static func normalize(_ text: String, caseSensitive: Bool) -> String {
        let base = caseSensitive ? text : text.lowercased()
        let chars = Array(base)
        var out = ""
        for (i, ch) in chars.enumerated() {
            let inWord = i > 0 && i + 1 < chars.count && (chars[i - 1].isLetter || chars[i - 1].isNumber)
                && (chars[i + 1].isLetter || chars[i + 1].isNumber)
            if ch.isLetter || ch.isNumber || ((ch == "'" || ch == "’" || ch == ".") && inWord) {
                out.append(ch == "’" ? "'" : ch)
            } else {
                out.append(" ")
            }
        }
        return out.split(separator: " ").joined(separator: " ")
    }
}
