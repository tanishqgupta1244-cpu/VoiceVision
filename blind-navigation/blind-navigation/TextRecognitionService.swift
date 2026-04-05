import Vision
import AVFoundation
import Combine
import CoreImage

struct RecognizedText: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let confidence: Float
    let boundingBox: CGRect
    
    static func == (lhs: RecognizedText, rhs: RecognizedText) -> Bool {
        return lhs.text == rhs.text && 
               abs(lhs.boundingBox.midX - rhs.boundingBox.midX) < 0.1 &&
               abs(lhs.boundingBox.midY - rhs.boundingBox.midY) < 0.1
    }
}

final class TextRecognitionService: ObservableObject {
    @Published var recognizedTexts: [RecognizedText] = []
    @Published var fullTextContent: String = ""
    @Published var isPaused: Bool = false
    @Published var currentScenario: OCRScenario = .normal

    private let textRequest: VNRecognizeTextRequest
    private let queue = DispatchQueue(label: "TextRecognitionQueue")
    private var lastProcessedTime: Date = .distantPast
    private let processingInterval: TimeInterval = 0.3 // Faster cadence for responsive OCR

    // Minimum confidence for text recognition (dynamic based on scenario)
    private var minConfidence: Float = 0.4
    private let minBoundingBoxArea: CGFloat = 0.0008

    // Stability filtering
    private var recentTextSnapshots: [String] = []
    private let stabilityWindow: Int = 1
    private let requiredStableMatches: Int = 1

    // Debounce to prevent re-announcing same text
    private var lastAnnouncedText: String = ""
    private var lastAnnouncementTime: Date = .distantPast
    private let announcementCooldown: TimeInterval = 5.0 // Don't re-announce same text within 5 seconds

    // ENHANCED: Multi-frame fusion system
    private let multiFrameFusion = MultiFrameFusion()

    // ENHANCED: Scenario tracking
    private var currentScenarioWeights: [OCRScenario: Int] = [:]

    // ENHANCED: Quality assessment cache
    private var lastQualityAssessment: (quality: ImageQuality, brightness: Float, sharpness: Float, contrast: Float)?
    private var lastQualityUpdateTime: Date = .distantPast
    private let qualityUpdateInterval: TimeInterval = 0.5 // Update quality every 500ms
    
    init() {
        textRequest = VNRecognizeTextRequest()

        // ENHANCED: Use accurate recognition for better text quality
        textRequest.recognitionLevel = .accurate

        // ENHANCED: Enable language correction for better partial text handling
        textRequest.usesLanguageCorrection = true

        // ENHANCED: Support multiple English variants for better regional recognition
        textRequest.recognitionLanguages = ["en-US", "en-IN", "en-GB"]

        // ENHANCED: Auto-detect language for mixed text scenarios
        textRequest.automaticallyDetectsLanguage = true

        // Lower minimum text height for better small/distant text detection
        textRequest.minimumTextHeight = 0.008
    }
    
    func process(pixelBuffer: CVPixelBuffer) {
        // Skip processing if paused (e.g., when speech is active)
        guard !isPaused else { return }

        // Throttle processing to avoid overload
        let now = Date()
        guard now.timeIntervalSince(lastProcessedTime) >= processingInterval else { return }
        lastProcessedTime = now

        queue.async { [weak self] in
            guard let self = self else { return }

            // Double-check pause status in async context
            guard !self.isPaused else { return }

            // ENHANCED: Assess image quality (with caching)
            let qualityAssessment: (quality: ImageQuality, brightness: Float, sharpness: Float, contrast: Float)
            if now.timeIntervalSince(self.lastQualityUpdateTime) >= self.qualityUpdateInterval {
                qualityAssessment = ImageProcessingUtilities.assessImageQuality(pixelBuffer)
                self.lastQualityAssessment = qualityAssessment
                self.lastQualityUpdateTime = now
            } else {
                qualityAssessment = self.lastQualityAssessment ?? (.good, 128, 150, 50)
            }

            // ENHANCED: Perform initial OCR recognition
            var texts = self.performOCR(on: pixelBuffer)

            // ENHANCED: Detect scenario and optimize
            let textCharacteristics = OCRScenarioOptimizer.analyzeTextCharacteristics(from: texts)
            let scenario = OCRScenarioOptimizer.detectScenario(
                imageQuality: qualityAssessment,
                textCharacteristics: textCharacteristics
            )

            // Update scenario tracking
            self.currentScenarioWeights[scenario, default: 0] += 1
            DispatchQueue.main.async {
                self.currentScenario = scenario
            }

            // ENHANCED: Get optimized parameters for scenario
            let params = OCRScenarioOptimizer.getOptimizedParameters(for: scenario)
            self.minConfidence = params.confidenceThreshold

            // ENHANCED: Apply preprocessing if needed and re-run OCR
            if params.preprocessing != .default {
                if let enhanced = ImageProcessingUtilities.preprocessForOCR(pixelBuffer, options: params.preprocessing) {
                    // Re-run OCR on enhanced image
                    texts = self.performOCR(on: enhanced)
                }
            }

            // ENHANCED: Multi-frame fusion for challenging scenarios
            if params.shouldUseMultiFrame {
                if let fusedTexts = self.multiFrameFusion.addFrame(texts: texts, quality: qualityAssessment.quality) {
                    // Use fused results
                    let allText = fusedTexts.map { $0.text }.joined(separator: " ")
                    let stableText = self.applyStabilityFilter(allText)

                    DispatchQueue.main.async {
                        self.recognizedTexts = fusedTexts
                        self.fullTextContent = stableText
                    }
                    return
                }
            }

            // Standard processing (no fusion yet or fusion not needed)
            let allText = texts.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let stableText = self.applyStabilityFilter(allText)

            DispatchQueue.main.async {
                self.recognizedTexts = texts
                self.fullTextContent = stableText
            }
        }
    }

    // MARK: - ENHANCED: OCR Processing

    /// Performs OCR on pixel buffer and returns recognized texts
    private func performOCR(on pixelBuffer: CVPixelBuffer) -> [RecognizedText] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])

        do {
            try handler.perform([self.textRequest])

            guard let results = self.textRequest.results else { return [] }

            var texts: [RecognizedText] = []

            for observation in results {
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence >= self.minConfidence else { continue }

                let text = candidate.string
                let boundingBox = observation.boundingBox
                let area = boundingBox.width * boundingBox.height

                // Filter out very small or noise text
                guard text.count >= 2 else { continue }
                guard area >= self.minBoundingBoxArea else { continue }

                texts.append(RecognizedText(
                    text: text,
                    confidence: candidate.confidence,
                    boundingBox: boundingBox
                ))
            }

            return texts
        } catch {
            print("Text recognition error:", error)
            return []
        }
    }
    
    private func applyStabilityFilter(_ text: String) -> String {
        guard !text.isEmpty else {
            recentTextSnapshots.removeAll()
            return ""
        }
        
        recentTextSnapshots.append(text)
        if recentTextSnapshots.count > stabilityWindow {
            recentTextSnapshots.removeFirst()
        }
        
        let normalized = text.lowercased()
        let matches = recentTextSnapshots.filter { $0.lowercased() == normalized }.count
        if matches >= requiredStableMatches {
            return text
        }
        
        return ""
    }
    
    // Get announcement-worthy text (significant text blocks)
    func getAnnouncementText() -> String? {
        // Group nearby text into sentences/blocks
        let significantText = fullTextContent.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only announce if we have meaningful text (more than just a few characters)
        guard significantText.count >= 5 else { return nil }

        // Check if this text is different from what we last announced
        let now = Date()
        let isSameText = significantText.lowercased() == lastAnnouncedText.lowercased()
        let isInCooldown = now.timeIntervalSince(lastAnnouncementTime) < announcementCooldown

        if isSameText && isInCooldown {
            return nil // Don't re-announce
        }

        // Update tracking
        lastAnnouncedText = significantText
        lastAnnouncementTime = now

        return significantText
    }

    // MARK: - ENHANCED: Diagnostic and Control Methods

    /// Resets multi-frame fusion (call when scene changes significantly)
    func resetFusion() {
        multiFrameFusion.reset()
    }

    /// Gets current diagnostic information
    func getDiagnostics() -> (scenario: OCRScenario, quality: ImageQuality?, frameCount: Int) {
        let quality = lastQualityAssessment?.quality
        return (currentScenario, quality, multiFrameFusion.frameCount)
    }

    /// Manually set scenario (for testing or special cases)
    func setScenario(_ scenario: OCRScenario) {
        DispatchQueue.main.async {
            self.currentScenario = scenario
        }
    }
}
