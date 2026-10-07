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
            
            // Prepare text and keyword for matching
            let sourceText = rule.caseSensitive ? text : text.lowercased()
            let searchKeyword = rule.caseSensitive ? rule.keyword : rule.keyword.lowercased()
            
            // Normalize whitespace
            let normalizedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedKeyword = searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
            
            var isMatch = false
            
            switch rule.matchMode {
            case .exact:
                isMatch = (normalizedSource == normalizedKeyword)
            case .contains:
                isMatch = normalizedSource.contains(normalizedKeyword)
            case .prefix:
                isMatch = normalizedSource.hasPrefix(normalizedKeyword)
            }
            
            if isMatch {
                matchedRules.append(rule)
                lastTriggerTimes[rule.id] = now
            }
        }
        
        return matchedRules
    }
}
