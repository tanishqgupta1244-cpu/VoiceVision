import Foundation
import CoreImage
import Accelerate
import CoreVideo

/// Quality assessment result for image preprocessing
enum ImageQuality: Equatable {
    case excellent
    case good
    case fair
    case poor
}

/// Preprocessing options for OCR enhancement
struct OCRPreprocessingOptions: Equatable {
    var applyContrastEnhancement: Bool = true
    var applySharpening: Bool = true
    var applyAdaptiveThreshold: Bool = false
    var sharpeningIntensity: Float = 0.4
    var contrastEnhancementFactor: Float = 1.2
}

/// Image processing utilities for OCR enhancement
/// Handles low light, blur, and angle compensation
final class ImageProcessingUtilities {

    // MARK: - Quality Assessment

    /// Assesses image quality based on brightness, sharpness, and contrast
    /// - Parameter pixelBuffer: Input image buffer
    /// - Returns: Quality rating and diagnostic values
    static func assessImageQuality(_ pixelBuffer: CVPixelBuffer) -> (quality: ImageQuality, brightness: Float, sharpness: Float, contrast: Float) {
        let brightness = calculateBrightness(pixelBuffer)
        let sharpness = calculateSharpness(pixelBuffer)
        let contrast = calculateContrast(pixelBuffer)

        let quality: ImageQuality

        // Quality assessment thresholds
        let brightnessThreshold: Float = 40.0 // Below this is too dark
        let sharpnessThreshold: Float = 100.0 // Below this is too blurry
        let contrastThreshold: Float = 30.0   // Below this is too low contrast

        let brightnessGood = brightness >= brightnessThreshold ? 1 : 0
        let sharpnessGood = sharpness >= sharpnessThreshold ? 1 : 0
        let contrastGood = contrast >= contrastThreshold ? 1 : 0
        let goodMetrics = brightnessGood + sharpnessGood + contrastGood

        switch goodMetrics {
        case 3:
            quality = .excellent
        case 2:
            quality = .good
        case 1:
            quality = .fair
        default:
            quality = .poor
        }

        return (quality, brightness, sharpness, contrast)
    }

    /// Calculates average brightness of image (0-255 scale)
    private static func calculateBrightness(_ pixelBuffer: CVPixelBuffer) -> Float {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return 0 }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow

        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }

        var total: Float = 0
        let bytesPerPixel = cgImage.bitsPerPixel / 8

        // Sample pixels (every 10th pixel for performance)
        let sampleStep = 10
        var sampleCount = 0

        for y in stride(from: 0, through: height, by: sampleStep) {
            for x in stride(from: 0, through: width, by: sampleStep) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let dataLength = CFDataGetLength(data)
                if offset + 2 < dataLength {
                    let r = Float(bytes[offset])
                    let g = Float(bytes[offset + 1])
                    let b = Float(bytes[offset + 2])

                    // Perceived brightness using ITU-R BT.709 formula
                    let brightness = 0.2126 * r + 0.7152 * g + 0.0722 * b
                    total += brightness
                    sampleCount += 1
                }
            }
        }

        return sampleCount > 0 ? total / Float(sampleCount) : 0
    }

    /// Calculates image sharpness using Laplacian variance
    /// Higher values = sharper image
    private static func calculateSharpness(_ pixelBuffer: CVPixelBuffer) -> Float {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let context = CIContext(options: [.useSoftwareRenderer: false])

        // Apply Laplacian filter for edge detection
        guard let laplacianFilter = CIFilter(name: "CIConvolution3X3") else { return 0 }
        laplacianFilter.setValue(ciImage, forKey: kCIInputImageKey)

        // Laplacian kernel for edge detection
        let laplacianKernel: [CGFloat] = [
            0,  1,  0,
            1, -4,  1,
            0,  1,  0
        ]

        laplacianFilter.setValue(CIVector(values: laplacianKernel, count: 9), forKey: "inputWeights")

        guard let outputImage = laplacianFilter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return 0 }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow

        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }

        // Calculate variance (simplified version using sampling)
        var sum: Float = 0
        var sumSquared: Float = 0
        let sampleStep = 20
        var sampleCount = 0
        let bytesPerPixel = cgImage.bitsPerPixel / 8

        let dataLength = CFDataGetLength(data)
        for y in stride(from: 0, through: height, by: sampleStep) {
            for x in stride(from: 0, through: width, by: sampleStep) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                if offset < dataLength {
                    let value = Float(bytes[offset])
                    sum += value
                    sumSquared += value * value
                    sampleCount += 1
                }
            }
        }

        guard sampleCount > 0 else { return 0 }

        let mean = sum / Float(sampleCount)
        let variance = (sumSquared / Float(sampleCount)) - (mean * mean)

        return max(0.0, variance) // Return variance as sharpness metric
    }

    /// Calculates RMS contrast of the image
    private static func calculateContrast(_ pixelBuffer: CVPixelBuffer) -> Float {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return 0 }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow

        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }

        var sum: Float = 0
        var sumSquared: Float = 0
        let sampleStep = 15
        var sampleCount = 0
        let bytesPerPixel = cgImage.bitsPerPixel / 8

        // Calculate mean and variance for RMS contrast
        let dataLength = CFDataGetLength(data)
        for y in stride(from: 0, through: height, by: sampleStep) {
            for x in stride(from: 0, through: width, by: sampleStep) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                if offset + 2 < dataLength {
                    let r = Float(bytes[offset])
                    let g = Float(bytes[offset + 1])
                    let b = Float(bytes[offset + 2])

                    // Use luminance
                    let luminance = 0.299 * r + 0.587 * g + 0.114 * b

                    sum += luminance
                    sumSquared += luminance * luminance
                    sampleCount += 1
                }
            }
        }

        guard sampleCount > 0 else { return 0 }

        let mean = sum / Float(sampleCount)
        let rmsContrast = sqrt((sumSquared / Float(sampleCount)) - (mean * mean))

        return rmsContrast
    }

    // MARK: - Image Enhancement

    /// Preprocesses image for OCR with specified enhancements
    /// - Parameters:
    ///   - pixelBuffer: Input image buffer
    ///   - options: Preprocessing options
    /// - Returns: Preprocessed pixel buffer or nil if processing failed
    static func preprocessForOCR(_ pixelBuffer: CVPixelBuffer, options: OCRPreprocessingOptions = .default) -> CVPixelBuffer? {
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Apply enhancements in sequence
        if options.applyContrastEnhancement {
            ciImage = applyContrastEnhancement(to: ciImage, factor: options.contrastEnhancementFactor)
        }

        if options.applySharpening {
            ciImage = applySharpening(to: ciImage, intensity: options.sharpeningIntensity)
        }

        // Convert back to CVPixelBuffer
        let context = CIContext(options: [.useSoftwareRenderer: false])

        var outputPixelBuffer: CVPixelBuffer?

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            CVPixelBufferGetWidth(pixelBuffer),
            CVPixelBufferGetHeight(pixelBuffer),
            CVPixelBufferGetPixelFormatType(pixelBuffer),
            nil,
            &outputPixelBuffer
        )

        guard status == kCVReturnSuccess, let outputBuffer = outputPixelBuffer else {
            return nil
        }

        context.render(ciImage, to: outputBuffer)

        return outputBuffer
    }

    /// Applies contrast enhancement to improve text visibility
    /// - Parameters:
    ///   - image: Input CIImage
    ///   - factor: Enhancement factor (1.0 = no change, >1.0 = more contrast)
    /// - Returns: Enhanced image
    private static func applyContrastEnhancement(to image: CIImage, factor: Float) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else { return image }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(factor, forKey: kCIInputContrastKey)

        // Slightly increase brightness to compensate for contrast
        filter.setValue(1.05, forKey: kCIInputBrightnessKey)

        return filter.outputImage ?? image
    }

    /// Applies sharpening filter to compensate for blur
    /// - Parameters:
    ///   - image: Input CIImage
    ///   - intensity: Sharpening intensity (0.0-1.0)
    /// - Returns: Sharpened image
    private static func applySharpening(to image: CIImage, intensity: Float) -> CIImage {
        guard let filter = CIFilter(name: "CISharpenLuminance") else { return image }

        filter.setValue(image, forKey: kCIInputImageKey)
        // Sharpness value typically 0.0-2.0, we scale intensity accordingly
        filter.setValue(intensity * 2.0, forKey: kCIInputSharpnessKey)

        return filter.outputImage ?? image
    }

    /// Applies perspective correction for angled text
    /// Note: This requires detected text corners, should be used with VNDocumentObservation
    /// - Parameters:
    ///   - image: Input CIImage
    ///   - topLeft: Top-left corner of text region
    ///   - topRight: Top-right corner
    ///   - bottomLeft: Bottom-left corner
    ///   - bottomRight: Bottom-right corner
    /// - Returns: Perspective-corrected image
    static func applyPerspectiveCorrection(
        to image: CIImage,
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomLeft: CGPoint,
        bottomRight: CGPoint
    ) -> CIImage {
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return image }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")

        return filter.outputImage ?? image
    }

    /// Creates a zoomed crop of the image for better small text recognition
    /// - Parameters:
    ///   - pixelBuffer: Input image buffer
    ///   - region: Region to crop (normalized coordinates 0-1)
    /// - Returns: Cropped and scaled pixel buffer
    static func cropAndZoomRegion(_ pixelBuffer: CVPixelBuffer, region: CGRect) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let width = ciImage.extent.width
        let height = ciImage.extent.height

        // Convert normalized rect to pixel coordinates
        let pixelRect = CGRect(
            x: region.origin.x * width,
            y: region.origin.y * height,
            width: region.size.width * width,
            height: region.size.height * height
        )

        // Crop the region
        let croppedImage = ciImage.cropped(to: pixelRect)

        // Scale up 2x for better text recognition
        let scaledImage = croppedImage.transformed(by: CGAffineTransform(scaleX: 2.0, y: 2.0))

        // Convert back to CVPixelBuffer
        let context = CIContext(options: [.useSoftwareRenderer: false])

        var outputPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(scaledImage.extent.width),
            Int(scaledImage.extent.height),
            CVPixelBufferGetPixelFormatType(pixelBuffer),
            nil,
            &outputPixelBuffer
        )

        guard status == kCVReturnSuccess, let outputBuffer = outputPixelBuffer else {
            return nil
        }

        context.render(scaledImage, to: outputBuffer)

        return outputBuffer
    }
}

// MARK: - Default Options

extension OCRPreprocessingOptions {
    static let `default` = OCRPreprocessingOptions()

    /// Options for low-light conditions
    static let lowLight = OCRPreprocessingOptions(
        applyContrastEnhancement: true,
        applySharpening: true,
        contrastEnhancementFactor: 1.4
    )

    /// Options for blurry images
    static let blurry = OCRPreprocessingOptions(
        applyContrastEnhancement: true,
        applySharpening: true,
        sharpeningIntensity: 0.6,
        contrastEnhancementFactor: 1.3
    )

    /// Options for general challenging conditions
    static let challenging = OCRPreprocessingOptions(
        applyContrastEnhancement: true,
        applySharpening: true,
        sharpeningIntensity: 0.5,
        contrastEnhancementFactor: 1.35
    )
}
