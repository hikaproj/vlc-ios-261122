//
//  UltimateBilingualSubtitleParser.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Bilingual Subtitle Parser with O(log N) Binary Search and Dictionary Lookup.
//

import Foundation
import UIKit

public struct SubtitleCue: Identifiable, Sendable {
    public let id: Int
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let primaryText: String
    public let secondaryText: String
    
    public init(id: Int, startTime: TimeInterval, endTime: TimeInterval, primaryText: String, secondaryText: String = "") {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.primaryText = primaryText
        self.secondaryText = secondaryText
    }
}

public final class UltimateBilingualSubtitleParser: @unchecked Sendable {
    
    public private(set) var cues: [SubtitleCue] = []
    
    public init() {}
    
    /// Parses SRT content into sorted SubtitleCue array.
    public func parseSRT(content: String, secondaryContent: String? = nil) {
        let primaryCues = parseSingleSRT(content: content)
        if let secContent = secondaryContent {
            let secondaryCues = parseSingleSRT(content: secContent)
            self.cues = mergeBilingualCues(primary: primaryCues, secondary: secondaryCues)
        } else {
            self.cues = primaryCues
        }
    }
    
    private func parseSingleSRT(content: String) -> [SubtitleCue] {
        var result: [SubtitleCue] = []
        let blocks = content.components(separatedBy: "\n\n")
        var cueIndex = 0
        
        for block in blocks {
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            guard lines.count >= 2 else { continue }
            
            // Look for timestamp line (contains "-->")
            var timeLineIdx = 0
            if !lines[0].contains("-->") && lines.count >= 3 && lines[1].contains("-->") {
                timeLineIdx = 1
            }
            
            guard lines[timeLineIdx].contains("-->") else { continue }
            let timeParts = lines[timeLineIdx].components(separatedBy: "-->")
            guard timeParts.count == 2,
                  let start = parseTimestamp(timeParts[0].trimmingCharacters(in: .whitespaces)),
                  let end = parseTimestamp(timeParts[1].trimmingCharacters(in: .whitespaces)) else { continue }
            
            let textLines = lines.dropFirst(timeLineIdx + 1).joined(separator: "\n")
            cueIndex += 1
            result.append(SubtitleCue(id: cueIndex, startTime: start, endTime: end, primaryText: textLines))
        }
        
        return result.sorted { $0.startTime < $1.startTime }
    }
    
    private func mergeBilingualCues(primary: [SubtitleCue], secondary: [SubtitleCue]) -> [SubtitleCue] {
        var merged: [SubtitleCue] = []
        for p in primary {
            // Find best matching secondary cue overlapping in time
            let midTime = (p.startTime + p.endTime) * 0.5
            let matchedSec = secondary.first { midTime >= $0.startTime && midTime <= $0.endTime }
            merged.append(SubtitleCue(
                id: p.id,
                startTime: p.startTime,
                endTime: p.endTime,
                primaryText: p.primaryText,
                secondaryText: matchedSec?.primaryText ?? ""
            ))
        }
        return merged
    }
    
    private func parseTimestamp(_ str: String) -> TimeInterval? {
        // Format: 00:01:20,500 or 00:01:20.500
        let cleaned = str.replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.components(separatedBy: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]) else { return nil }
        return h * 3600.0 + m * 60.0 + s
    }
    
    /// O(log N) Binary Search for active subtitle cue at specified playback time.
    public func findCue(at time: TimeInterval) -> SubtitleCue? {
        guard !cues.isEmpty else { return nil }
        var low = 0
        var high = cues.count - 1
        
        while low <= high {
            let mid = (low + high) / 2
            let cue = cues[mid]
            if time >= cue.startTime && time <= cue.endTime {
                return cue
            } else if time < cue.startTime {
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        return nil
    }
    
    /// Opens iOS Built-in Dictionary (UIReferenceLibraryViewController) for word definition.
    @MainActor
    public static func showDictionary(for term: String, from viewController: UIViewController) {
        let trimmed = term.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        guard !trimmed.isEmpty, UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: trimmed) else { return }
        let dictVC = UIReferenceLibraryViewController(term: trimmed)
        viewController.present(dictVC, animated: true)
    }
}
