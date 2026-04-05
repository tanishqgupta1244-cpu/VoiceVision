import Foundation
import CoreImage
import Vision

/// Scenario types for OCR optimization
enum OCRScenario: Equatable {
    case normal          // Standard conditions
    case lowLight        // Dark environment
    case distantText     // Text far away
    case smallText       // Small text close up
    case angledText      // Text at an angle
    case blurryImage     // Out of focus or motion blur
    case lowContrast     // Poor contrast between text and background
    case mixed           // Multiple challenging conditions
}

/// Detected text characteristics for scenario determination
struct TextCharacteristics {
    let averageHeight: CGFloat
    let averageConfidence: Float
    let textCount: Int
    let brightness: Float
    let sharpness: Float
    let contrast: Float
    let hasSmallText: Bool
    let hasLowConfidence: Bool
}

/// Optimizes OCR parameters based on detected scenario
final class OCRScenarioOptimizer {

    // MARK: - Scenario Detection

    /// Detects the current OCR scenario based on image and text characteristics
    static func detectScenario(
        imageQuality: (quality: ImageQuality, brightness: Float, sharpness: Float, contrast: Float),
        textCharacteristics: TextCharacteristics
    ) -> OCRScenario {
        let (quality, brightness, sharpness, contrast) = imageQuality

        // Count challenging conditions
        var challengingConditions: [OCRScenario] = []

        // Check brightness
        if brightness < 40 {
            challengingConditions.append(.lowLight)
        }

        // Check sharpness
        if sharpness < 100 {
            challengingConditions.append(.blurryImage)
        }

        // Check contrast
        if contrast < 30 {
            challengingConditions.append(.lowContrast)
        }

        // Check text characteristics
        if textCharacteristics.hasSmallText {
            challengingConditions.append(.smallText)
        }

        if textCharacteristics.hasLowConfidence {
            // Low confidence could be due to distance or angle
            if textCharacteristics.averageHeight < 0.02 {
                challengingConditions.append(.distantText)
            } else {
                challengingConditions.append(.angledText)
            }
        }

        // Determine scenario based on conditions
        if challengingConditions.count >= 3 {
            return .mixed
        } else if challengingConditions.count == 1 {
            return challengingConditions[0]
        } else if challengingConditions.count == 2 {
            // Prioritize low light and blur
            if challengingConditions.contains(.lowLight) {
                return .lowLight
            } else if challengingConditions.contains(.blurryImage) {
                return .blurryImage
            }
            return .mixed
        }

        return .normal
    }

    /// Analyzes text characteristics from recognition results
    static func analyzeTextCharacteristics(from texts: [RecognizedText]) -> TextCharacteristics {
        guard !texts.isEmpty else {
            return TextCharacteristics(
                averageHeight: 0,
                averageConfidence: 0,
                textCount: 0,
                brightness: 128,
                sharpness: 150,
                contrast: 50,
                hasSmallText: false,
                hasLowConfidence: false
            )
        }

        let totalHeight = texts.reduce(0) { $0 + $1.boundingBox.height }
        let averageHeight = totalHeight / CGFloat(texts.count)

        let totalConfidence = texts.reduce(0) { $0 + $1.confidence }
        let averageConfidence = totalConfidence / Float(texts.count)

        let hasSmallText = texts.contains { $0.boundingBox.height < 0.015 }
        let hasLowConfidence = texts.contains { $0.confidence < 0.6 }

        return TextCharacteristics(
            averageHeight: averageHeight,
            averageConfidence: averageConfidence,
            textCount: texts.count,
            brightness: 128,    // Will be updated from actual quality assessment
            sharpness: 150,     // Will be updated from actual quality assessment
            contrast: 50,       // Will be updated from actual quality assessment
            hasSmallText: hasSmallText,
            hasLowConfidence: hasLowConfidence
        )
    }

    // MARK: - Parameter Optimization

    /// Gets optimized OCR parameters for detected scenario
    static func getOptimizedParameters(for scenario: OCRScenario) -> (
        minimumTextHeight: CGFloat,
        confidenceThreshold: Float,
        preprocessing: OCRPreprocessingOptions,
        shouldUseMultiFrame: Bool
    ) {
        switch scenario {
        case .normal:
            return (
                minimumTextHeight: 0.008,
                confidenceThreshold: 0.4,
                preprocessing: .default,
                shouldUseMultiFrame: false
            )

        case .lowLight:
            return (
                minimumTextHeight: 0.010,    // Slightly higher to avoid noise
                confidenceThreshold: 0.5,    // Higher threshold for low quality
                preprocessing: .lowLight,
                shouldUseMultiFrame: true
            )

        case .distantText:
            return (
                minimumTextHeight: 0.005,    // Lower to capture distant text
                confidenceThreshold: 0.45,
                preprocessing: .challenging,
                shouldUseMultiFrame: true
            )

        case .smallText:
            return (
                minimumTextHeight: 0.003,    // Much lower for very small text
                confidenceThreshold: 0.35,   // Lower threshold as small text is harder
                preprocessing: .challenging,
                shouldUseMultiFrame: true
            )

        case .angledText:
            return (
                minimumTextHeight: 0.008,
                confidenceThreshold: 0.45,
                preprocessing: .challenging,
                shouldUseMultiFrame: true    // Multi-frame helps with angle variations
            )

        case .blurryImage:
            return (
                minimumTextHeight: 0.010,
                confidenceThreshold: 0.5,
                preprocessing: .blurry,
                shouldUseMultiFrame: true
            )

        case .lowContrast:
            return (
                minimumTextHeight: 0.010,
                confidenceThreshold: 0.5,
                preprocessing: .default,     // Contrast enhancement handles this
                shouldUseMultiFrame: true
            )

        case .mixed:
            return (
                minimumTextHeight: 0.008,
                confidenceThreshold: 0.45,
                preprocessing: .challenging,
                shouldUseMultiFrame: true
            )
        }
    }

    /// Gets region suggestion for zooming (for small/distant text)
    static func getZoomRegion(for texts: [RecognizedText], imageSize: CGSize) -> CGRect? {
        guard !texts.isEmpty else { return nil }

        // Find text regions that are small (likely need zoom)
        let smallTexts = texts.filter { $0.boundingBox.height < 0.02 || $0.boundingBox.width < 0.05 }

        guard !smallTexts.isEmpty else { return nil }

        // Cluster nearby small texts
        let clusters = clusterTexts(smallTexts)

        // Return largest cluster's bounding box
        guard let largestCluster = clusters.max(by: { $0.count < $1.count }) else { return nil }

        // Calculate bounding box for cluster
        let minX = largestCluster.map { $0.boundingBox.minX }.min() ?? 0
        let maxX = largestCluster.map { $0.boundingBox.maxX }.max() ?? 1
        let minY = largestCluster.map { $0.boundingBox.minY }.min() ?? 0
        let maxY = largestCluster.map { $0.boundingBox.maxY }.max() ?? 1

        // Add padding
        let padding: CGFloat = 0.02
        let paddedRect = CGRect(
            x: max(0, minX - padding),
            y: max(0, minY - padding),
            width: min(1, maxX - minX + padding * 2),
            height: min(1, maxY - minY + padding * 2)
        )

        // Don't zoom if region is too large (whole image essentially)
        guard paddedRect.width < 0.5 && paddedRect.height < 0.5 else { return nil }

        return paddedRect
    }

    /// Clusters nearby texts together
    private static func clusterTexts(_ texts: [RecognizedText]) -> [[RecognizedText]] {
        var clusters: [[RecognizedText]] = []
        var processed: Set<Int> = []

        for (index, text) in texts.enumerated() {
            if processed.contains(index) { continue }

            var cluster = [text]
            processed.insert(index)

            // Find nearby texts
            for (otherIndex, otherText) in texts.enumerated() {
                if index == otherIndex { continue }
                if processed.contains(otherIndex) { continue }

                let distance = sqrt(
                    pow(text.boundingBox.midX - otherText.boundingBox.midX, 2) +
                    pow(text.boundingBox.midY - otherText.boundingBox.midY, 2)
                )

                // Cluster if within 0.1 normalized distance
                if distance < 0.1 {
                    cluster.append(otherText)
                    processed.insert(otherIndex)
                }
            }

            clusters.append(cluster)
        }

        return clusters
    }
}

// MARK: - Dynamic Recognition Level

extension OCRScenarioOptimizer {

    /// Suggests recognition level based on scenario
    static func getRecognitionLevel(for scenario: OCRScenario) -> VNRequestTextRecognitionLevel {
        switch scenario {
        case .normal:
            return .fast  // Fast is sufficient for normal conditions

        case .lowLight, .distantText, .smallText, .angledText, .blurryImage, .lowContrast, .mixed:
            return .accurate  // Use accurate for challenging conditions
        }
    }

    /// Gets recommended processing interval based on scenario
    static func getProcessingInterval(for scenario: OCRScenario) -> TimeInterval {
        switch scenario {
        case .normal:
            return 0.3  // Standard cadence

        case .lowLight, .blurryImage, .mixed:
            return 0.4  // Slower cadence for challenging conditions (more processing time needed)

        case .distantText, .smallText:
            return 0.35 // Slightly slower

        case .angledText, .lowContrast:
            return 0.3  // Standard cadence
        }
    }
}
