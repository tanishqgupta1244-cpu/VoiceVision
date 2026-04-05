import Foundation
import Vision

/// Represents a single frame's OCR result
struct FrameResult {
    let texts: [RecognizedText]
    let timestamp: Date
    let quality: ImageQuality
}

/// Multi-frame fusion system for improved OCR accuracy
/// Accumulates multiple frames and uses consensus to determine best results
final class MultiFrameFusion {

    // MARK: - Configuration

    private let maxFramesToAccumulate: Int = 5
    private let minFramesForConsensus: Int = 3
    private let frameWindowDuration: TimeInterval = 1.5 // seconds

    // MARK: - State

    private var accumulatedFrames: [FrameResult] = []
    private var lastFusionTime: Date = .distantPast

    // MARK: - Fusion Logic

    /// Adds a new frame's results and returns fused results if available
    /// - Parameters:
    ///   - texts: Recognized texts from current frame
    ///   - quality: Quality assessment of current frame
    /// - Returns: Fused results if consensus achieved, nil otherwise
    func addFrame(texts: [RecognizedText], quality: ImageQuality) -> [RecognizedText]? {
        let now = Date()

        // Clear old frames outside time window
        accumulatedFrames.removeAll { now.timeIntervalSince($0.timestamp) > frameWindowDuration }

        // Add new frame
        let frameResult = FrameResult(texts: texts, timestamp: now, quality: quality)
        accumulatedFrames.append(frameResult)

        // Maintain maximum frame count
        if accumulatedFrames.count > maxFramesToAccumulate {
            accumulatedFrames.removeFirst()
        }

        // Check if we have enough frames for fusion
        guard accumulatedFrames.count >= minFramesForConsensus else {
            return nil
        }

        // Only perform fusion periodically to avoid excessive processing
        guard now.timeIntervalSince(lastFusionTime) >= 0.3 else {
            return nil
        }

        lastFusionTime = now

        // Perform fusion
        return fuseFrames()
    }

    /// Resets accumulated frames (call when scene changes significantly)
    func reset() {
        accumulatedFrames.removeAll()
        lastFusionTime = .distantPast
    }

    // MARK: - Private Fusion Methods

    /// Fuses accumulated frames using consensus and weighted voting
    private func fuseFrames() -> [RecognizedText] {
        var fusedTexts: [RecognizedText] = []

        // Group similar text regions across all frames
        let textGroups = groupSimilarTexts()

        // For each group, compute consensus result
        for group in textGroups {
            let consensusText = computeConsensus(for: group)
            fusedTexts.append(consensusText)
        }

        return fusedTexts
    }

    /// Groups similar texts from all frames
    private func groupSimilarTexts() -> [[RecognizedText]] {
        var groups: [[RecognizedText]] = []
        var processed: Set<Int> = []

        // Flatten all texts from all frames
        let allTexts: [(RecognizedText, Int)] = accumulatedFrames.enumerated().flatMap { frameIndex, frameResult in
            return frameResult.texts.map { ($0, frameIndex) }
        }

        for (index, text) in allTexts.enumerated() {
            if processed.contains(index) { continue }

            var group = [text.0]
            processed.insert(index)

            // Find similar texts
            for (otherIndex, otherText) in allTexts.enumerated() {
                if index == otherIndex { continue }
                if processed.contains(otherIndex) { continue }

                if areTextsSimilar(text.0, otherText.0) {
                    group.append(otherText.0)
                    processed.insert(otherIndex)
                }
            }

            // Only keep groups with multiple detections (consensus)
            if group.count >= 2 {
                groups.append(group)
            }
        }

        return groups
    }

    /// Computes consensus text for a group of similar texts
    private func computeConsensus(for group: [RecognizedText]) -> RecognizedText {
        // Use text with highest confidence as base
        guard let bestText = group.max(by: { $0.confidence < $1.confidence }) else {
            return group[0]
        }

        // If we have multiple variations of similar text, use weighted voting
        let textVariations = Dictionary(grouping: group) { $0.text.lowercased().trimmingCharacters(in: .whitespaces) }

        if textVariations.count > 1 {
            // Find most common text variation
            let mostCommon = textVariations.max(by: { $0.value.count < $1.value.count })!

            // Use the bounding box from highest confidence text, but text from most common
            return RecognizedText(
                text: mostCommon.key,
                confidence: bestText.confidence,
                boundingBox: bestText.boundingBox
            )
        }

        // All texts are the same or very similar, return highest confidence
        return bestText
    }

    /// Checks if two recognized texts are similar (same content and location)
    private func areTextsSimilar(_ text1: RecognizedText, _ text2: RecognizedText) -> Bool {
        // Check text similarity (allowing for minor OCR differences)
        let textSimilar = areTextContentsSimilar(text1.text, text2.text)

        // Check spatial proximity
        let locationSimilar = areLocationsSimilar(text1.boundingBox, text2.boundingBox)

        return textSimilar && locationSimilar
    }

    /// Checks if two text strings are semantically similar
    private func areTextContentsSimilar(_ text1: String, _ text2: String) -> Bool {
        let t1 = text1.lowercased().trimmingCharacters(in: .whitespaces)
        let t2 = text2.lowercased().trimmingCharacters(in: .whitespaces)

        // Exact match
        if t1 == t2 { return true }

        // One is substring of the other (common in OCR)
        if t1.contains(t2) || t2.contains(t1) {
            // Ensure they're reasonably close in length
            let lengthRatio = Double(min(t1.count, t2.count)) / Double(max(t1.count, t2.count))
            return lengthRatio > 0.7
        }

        // Levenshtein distance for similar strings
        let distance = levenshteinDistance(t1, t2)
        let maxLength = max(t1.count, t2.count)
        let similarity = 1.0 - (Double(distance) / Double(maxLength))

        return similarity > 0.8 // 80% similarity threshold
    }

    /// Calculates Levenshtein distance between two strings
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let s1Count = s1Array.count
        let s2Count = s2Array.count

        var matrix = Array(repeating: Array(repeating: 0, count: s2Count + 1), count: s1Count + 1)

        for i in 0...s1Count {
            matrix[i][0] = i
        }

        for j in 0...s2Count {
            matrix[0][j] = j
        }

        for i in 1...s1Count {
            for j in 1...s2Count {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return matrix[s1Count][s2Count]
    }

    /// Checks if two bounding boxes are spatially similar
    private func areLocationsSimilar(_ box1: CGRect, _ box2: CGRect) -> Bool {
        let centerDistance = sqrt(
            pow(box1.midX - box2.midX, 2) +
            pow(box1.midY - box2.midY, 2)
        )

        // Centers must be within 0.15 normalized coordinates
        let centerSimilar = centerDistance < 0.15

        // Sizes must be reasonably similar
        let widthRatio = min(box1.width, box2.width) / max(box1.width, box2.width)
        let heightRatio = min(box1.height, box2.height) / max(box1.height, box2.height)
        let sizeSimilar = widthRatio > 0.5 && heightRatio > 0.5

        return centerSimilar && sizeSimilar
    }

    /// Returns quality weight for frame scoring
    private func qualityWeight(for quality: ImageQuality) -> Int {
        switch quality {
        case .excellent: return 4
        case .good: return 3
        case .fair: return 2
        case .poor: return 1
        }
    }

    /// Gets current frame count
    var frameCount: Int {
        accumulatedFrames.count
    }
}

// MARK: - Text Quality Enhancement

extension MultiFrameFusion {

    /// Enhances text using multiple frame consensus
    /// Applies common corrections based on frame voting
    static func enhanceText(_ text: String, using frames: [FrameResult]) -> String {
        guard frames.count >= 2 else { return text }

        // Extract all text variations
        let variations = frames.compactMap { $0.texts.first?.text }

        // If all variations are the same, return as-is
        let unique = Set(variations.map { $0.lowercased() })
        if unique.count == 1 {
            return text
        }

        // Apply common OCR corrections
        var enhanced = text

        // Common OCR errors and their corrections
        let corrections = [
            "0": "O",  // Zero to O in text context
            "|": "I",  // Pipe to I
            "5": "S",  // 5 to S in certain contexts
        ]

        // Only apply if context suggests letter not number
        for (wrong, right) in corrections {
            // Heuristic: if surrounded by letters, it's likely a letter
            enhanced = enhanceWithContext(enhanced, wrong: wrong, right: right)
        }

        return enhanced
    }

    private static func enhanceWithContext(_ text: String, wrong: String, right: String) -> String {
        // Simple heuristic-based correction
        var result = text

        // Find all occurrences of wrong character
        var ranges: [Range<String.Index>] = []
        var searchRange = text.startIndex..<text.endIndex

        while let range = text.range(of: wrong, range: searchRange) {
            ranges.append(range)
            searchRange = range.upperBound..<text.endIndex
        }

        // Replace each occurrence if surrounded by letters
        for range in ranges.reversed() { // Reverse to maintain indices
            let charIndex = range.lowerBound

            // Check previous character
            var prevIsLetter = false
            if charIndex > text.startIndex {
                let prevCharIndex = text.index(before: charIndex)
                prevIsLetter = text[prevCharIndex].isLetter
            }

            // Check next character
            var nextIsLetter = false
            let nextCharIndex = range.upperBound
            if nextCharIndex < text.endIndex {
                nextIsLetter = text[nextCharIndex].isLetter
            }

            // If surrounded by letters, replace
            if prevIsLetter || nextIsLetter {
                result.replaceSubrange(range, with: right)
            }
        }

        return result
    }
}
