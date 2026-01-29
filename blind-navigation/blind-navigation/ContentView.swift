import SwiftUI
import Combine
import ARKit
import AVFoundation
import LocalAuthentication

struct ContentView: View {
    @StateObject private var arCamera = ARCameraService()
    @StateObject private var detector: DetectionService
    @StateObject private var textRecognition = TextRecognitionService()
    @StateObject private var currencyRecognition = CurrencyRecognitionService()
    @StateObject private var qrScanService = QRScanService()
    @StateObject private var speechService = SpeechService()

    // Debug/diagnostics
    @State private var lastARSessionError: String? = nil
    @State private var cameraAuthStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    
    init() {
        // Initialize detector safely
        print("DEBUG: Initializing DetectionService...")
        if let detectionService = DetectionService() {
            _detector = StateObject(wrappedValue: detectionService)
            print("DEBUG: DetectionService initialized successfully")
        } else {
            print("ERROR: Failed to initialize DetectionService - ML model could not be loaded")
            // This will crash, but with a clear error message
            // In production, the model should always be available
            fatalError("Failed to initialize DetectionService - ML model could not be loaded. Please ensure yolo11n.mlpackage is included in the app bundle.")
        }
    }
    
    // Track objects that have been announced (only reset when they leave frame)
    @State private var announcedObjects: Set<String> = []
    // Track objects in the last few frames to detect when they truly leave
    @State private var recentlyDetectedObjects: [Set<String>] = []
    private let frameHistorySize = 5 // Number of frames to check before considering object "gone"
    // Global cooldown per label to prevent spam from micro-movements
    @State private var lastAnnouncementTimeByLabel: [String: Date] = [:]
    private let objectAnnouncementCooldown: TimeInterval = 4.0
    
    // Text reading confirmation
    @State private var detectedText: String? = nil
    @State private var showTextConfirmation: Bool = false
    @State private var lastTextAnnouncementTime: Date = .distantPast
    @State private var lastPromptedText: String? = nil
    @State private var lastPromptTime: Date = .distantPast
    @State private var lastPromptAnnouncementTime: Date = .distantPast // Track when we last said "Text detected"
    @State private var isReadingText: Bool = false // Track if text is currently being read
    @State private var lastTextDetectedTime: Date = .distantPast
    private let textPromptCooldown: TimeInterval = 5.0 // Don't prompt again for 5 seconds
    private let textSimilarityThreshold: Double = 0.8 // 80% similarity = same text
    private let textPromptGracePeriod: TimeInterval = 1.5
    
    // Currency recognition state
    @State private var detectedCurrency: DetectedCurrency? = nil
    @State private var pendingCurrency: DetectedCurrency? = nil
    @State private var isCurrencyModeActive: Bool = false // Currency detection mode
    @State private var lastCurrencyPromptTime: Date = .distantPast
    private let currencyPromptCooldown: TimeInterval = 3.0

    // QR payment mode
    @State private var isQRPayModeActive: Bool = false
    @State private var pendingQRPayload: QRTransferPayload? = nil
    @State private var isSendingMoney: Bool = false
    @State private var lastQRPromptTime: Date = .distantPast
    private let qrPromptCooldown: TimeInterval = 2.5
    @State private var showQRAmountPrompt: Bool = false
    @State private var qrAmountInput: String = ""
    @State private var qrAmountError: String? = nil
    @State private var isAuthorizingPayment: Bool = false

    // TODO: Replace with the actual merchant/owner phone.
    // QR amount is entered by the user; recipient is fixed to this number.
    private let defaultQRRecipientPhone: String = "8290883601"

    // Option A: Only allow specific QR(s) to trigger payment.
    // TODO: Replace this with the exact decoded QR payload string.
    // You can add multiple allowed QRs here if needed.
    private let allowedQRRawValues: Set<String> = [
        // QR code shown on Wikipedia's QR code article ("QR code for mobile English Wikipedia").
        // Decodes to the mobile English Wikipedia homepage.
        // If you replace the QR later, update this string to the new QR's decoded text.
        "https://en.m.wikipedia.org"
    ]
    
    // Whitelist of object labels that should be spoken aloud
    // Only large, important objects that blind users need to know about
    // Note: YOLO11n trained on COCO doesn't include "door" or "window" classes
    private let speakableLabels: Set<String> = [
        "person", // Added for navigation safety
        "chair",
        "couch",
        "bed",
        "dining table",
        "refrigerator", // Used as proxy for cupboards/cabinets
        "wall", // Detected via ARKit vertical planes
        "doorway", // Detected via ARKit gaps between planes (ANNOUNCE)
        "car",
        "motorcycle",
        "bus",
        "train",
        "truck",
        "boat"
    ]
    
    // Labels to detect but NOT announce (visual only)
    private let silentLabels: Set<String> = [
        "window" // Detected via ARKit but not announced
    ]
    // Vehicle labels that require stricter filtering to avoid false positives
    private let vehicleLabels: Set<String> = [
        "car",
        "motorcycle",
        "bus",
        "train",
        "truck",
        "boat"
    ]
    
    // Person detections need stricter filtering
    private let personLabels: Set<String> = [
        "person"
    ]
    
    // Error state
    @State private var initializationError: String? = nil
    @State private var arSessionStarted: Bool = false

    var body: some View {
        ZStack {
            // Background color to prevent black screen
            Color.black
                .ignoresSafeArea()
            
            // Show error message if initialization failed
            if let error = initializationError {
                VStack(spacing: 20) {
                    Text("Initialization Error")
                        .font(.title)
                        .foregroundColor(.white)
                    Text(error)
                        .font(.body)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Text("Please check Xcode console for details")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color.black)
            } else {
                // Show camera preview once AR session is ready
                if arSessionStarted {
                    CameraPreview(arCameraService: arCamera)
                        .ignoresSafeArea()
                } else {
                    // Show loading state
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("Initializing AR Camera...")
                            .foregroundColor(.white)
                            .font(.headline)
                        Text("If this screen persists, check Xcode console")
                            .foregroundColor(.gray)
                            .font(.caption)
                            .padding(.top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }
            }

            // Lightweight always-on debug overlay (helps diagnose black screen on device)
            VStack(alignment: .leading, spacing: 6) {
                Text("Debug")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("Camera auth: \(debugCameraAuthString(cameraAuthStatus))")
                    .font(.caption2)
                Text("AR started: \(arSessionStarted ? "yes" : "no")")
                    .font(.caption2)
                Text("Has frames: \(arCamera.latestBuffer == nil ? "no" : "yes")")
                    .font(.caption2)
                if let last = lastARSessionError {
                    Text("AR error: \(last)")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(3)
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.55))
            .foregroundColor(.white)
            .cornerRadius(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding([.top, .leading], 12)
            .zIndex(2000)
            if !isQRPayModeActive {
                ForEach(detector.detections) { detection in
                    DetectionBox(detection: detection)
                }
                ForEach(arCamera.wallDetections) { detection in
                    DetectionBox(detection: detection)
                }
                ForEach(arCamera.doorwayDetections) { detection in
                    DetectionBox(detection: detection, color: .blue) // Blue for doorways
                }
                ForEach(arCamera.windowDetections) { detection in
                    DetectionBox(detection: detection, color: .cyan) // Cyan for windows
                }
                ForEach(textRecognition.recognizedTexts) { recognizedText in
                    TextBox(recognizedText: recognizedText)
                }
            }
            
            // Text reading confirmation - tap anywhere on screen to read
            if showTextConfirmation, let text = detectedText {
                Button(action: {
                    readDetectedText(text)
                }) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .zIndex(1000) // Ensure it's on top
            }
            
            // Tap-to-stop overlay when text is being read
            if isReadingText {
                Button(action: {
                    stopTextReading()
                }) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .zIndex(1001) // Above text confirmation
            }
            
            // Currency mode indicator
            if isCurrencyModeActive {
                VStack {
                    HStack {
                        Spacer()
                        VStack {
                            Text("Currency Mode")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Double tap to exit")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(10)
                        .padding()
                    }
                    Spacer()
                }
                .zIndex(1200)
            }

            // QR Pay mode indicator
            if isQRPayModeActive {
                VStack {
                    HStack {
                        Spacer()
                        VStack {
                            Text("QR Pay Mode")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Long press to exit")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color.green.opacity(0.8))
                        .cornerRadius(10)
                        .padding()
                    }
                    Spacer()
                }
                .zIndex(1200)
            }

            // QR amount entry overlay
            if showQRAmountPrompt {
                VStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Text("Enter Amount")
                            .font(.headline)
                            .foregroundColor(.white)

                        TextField("Amount in rupees", text: $qrAmountInput)
                            .keyboardType(.numberPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(maxWidth: 220)

                        if let error = qrAmountError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        HStack(spacing: 16) {
                            Button("Cancel") {
                                cancelQRAmountPrompt()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.6))
                            .cornerRadius(8)

                            Button("Confirm") {
                                confirmQRAmountAndSend()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.8))
                            .cornerRadius(8)
                        }
                    }
                    .padding(16)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(12)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.35))
                .zIndex(1500)
            }
        }
        .onTapGesture {
            if !showQRAmountPrompt {
                handlePrimaryConfirmationTap()
            }
        }
        .highPriorityGesture(
            TapGesture(count: 2)
                .onEnded {
                    handleCurrencyModeToggleGesture()
                }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 1.0)
                .onEnded { _ in
                    handleQRModeToggleGesture()
                }
        )
        .onReceive(arCamera.$latestBuffer.compactMap { $0 }) { buffer in
            // Only process detection/text when NOT in currency or QR pay mode
            if !isCurrencyModeActive && !isQRPayModeActive {
                detector.process(pixelBuffer: buffer)
                textRecognition.process(pixelBuffer: buffer)
            }
            // Always process currency recognition (it checks isActive internally)
            currencyRecognition.process(pixelBuffer: buffer)
            // Always process QR scan (it checks isActive internally)
            qrScanService.process(pixelBuffer: buffer)
        }
        .onReceive(detector.$detections) { detections in
            // Only handle detections when NOT in currency mode and NOT reading text
            if !isCurrencyModeActive && !isReadingText {
                handleDetections(detections, announce: true)
            }
        }
        .onReceive(arCamera.$wallDetections) { walls in
            if !isQRPayModeActive && !isReadingText {
                handleDetections(walls, announce: true)
            }
        }
        .onReceive(arCamera.$doorwayDetections) { doorways in
            if !isQRPayModeActive && !isReadingText {
                handleDetections(doorways, announce: true)
            }
        }
        .onReceive(arCamera.$windowDetections) { windows in
            if !isQRPayModeActive && !isReadingText {
                handleDetections(windows, announce: false) // Detect but don't announce
            }
        }
        .onReceive(textRecognition.$fullTextContent) { textContent in
            // Only handle text detection when NOT in currency mode
            if !isCurrencyModeActive && !isQRPayModeActive {
                handleTextDetection(textContent)
            }
        }
        .onReceive(currencyRecognition.$detectedCurrency) { currency in
            handleCurrencyDetection(currency)
        }
        .onReceive(qrScanService.$lastPayload) { payload in
            handleQRPayload(payload)
        }
        .onReceive(speechService.$isSpeaking) { isSpeaking in
            // Pause text and currency recognition when speech is active to avoid conflicts
            textRecognition.isPaused = isSpeaking
            currencyRecognition.isPaused = isSpeaking
            qrScanService.isPaused = isSpeaking
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TextReadingStarted"))) { _ in
            DispatchQueue.main.async {
                self.isReadingText = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TextReadingFinished"))) { _ in
            DispatchQueue.main.async {
                self.isReadingText = false
            }
        }
        .onAppear {
            print("DEBUG: ========== ContentView appeared - starting services... ==========")
            
            // Check for basic requirements first
            guard ARWorldTrackingConfiguration.isSupported else {
                let errorMsg = "ARKit is not supported on this device"
                print("ERROR: \(errorMsg)")
                initializationError = errorMsg
                return
            }
            
            // Start unified AR camera service (handles both camera feed and wall detection)
            // IMPORTANT: On first install, starting AR before camera permission is granted can lead to a black screen.
            requestCameraAccessAndStartAR()
            
            print("DEBUG: Initializing speech service...")
            speechService.initialize()
            
            // Test speech output to verify it works
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                print("DEBUG: Testing speech output...")
                speechService.speak(label: "Test", phrase: "VoiceVision app is ready")
            }
            
            print("DEBUG: ContentView initialization complete")
        }
        .onDisappear {
            TorchService.shared.setTorch(enabled: false)
            arCamera.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // If the app came back from background right after a permission prompt, ensure AR is running.
            cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
            if initializationError == nil && !arSessionStarted {
                requestCameraAccessAndStartAR()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ARSessionError"))) { note in
            let message: String
            if let err = note.object as? Error {
                message = err.localizedDescription
            } else {
                message = "Unknown ARSession error"
            }
            DispatchQueue.main.async {
                self.lastARSessionError = message
                self.initializationError = "ARSession error: \(message)"
            }
        }
    }

    private func requestCameraAccessAndStartAR() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraAuthStatus = status
        switch status {
        case .authorized:
            startARNow()
        case .notDetermined:
            print("DEBUG: Requesting camera permission...")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    if granted {
                        print("DEBUG: Camera permission granted")
                        self.startARNow()
                    } else {
                        let errorMsg = "Camera permission is required to show the camera feed. Enable it in Settings > Privacy & Security > Camera."
                        print("ERROR: \(errorMsg)")
                        self.initializationError = errorMsg
                    }
                }
            }
        case .denied, .restricted:
            let errorMsg = "Camera permission is not available. Enable it in Settings > Privacy & Security > Camera."
            print("ERROR: \(errorMsg)")
            initializationError = errorMsg
        @unknown default:
            let errorMsg = "Unknown camera permission state."
            print("ERROR: \(errorMsg)")
            initializationError = errorMsg
        }
    }

    private func startARNow() {
        print("DEBUG: Starting AR camera...")
        arCamera.start()
        // Mark AR session as started after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.arSessionStarted = true
            print("DEBUG: AR session marked as started")
        }
    }

    private func debugCameraAuthString(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .restricted: return "restricted"
        @unknown default: return "unknown"
        }
    }
    

    private func handleDetections(_ detections: [Detection], announce: Bool = true) {
        // Filter to valid detections (speakable or silent labels)
        let validDetections = detections.filter { detection in
            let label = detection.label.lowercased()
            
            // Check if in speakable whitelist or silent list
            let isInWhitelist = speakableLabels.contains(label) || silentLabels.contains(label)
            guard isInWhitelist else {
                return false
            }
            
            // ARKit detections (doorway, wall, window) have high confidence and should pass through
            if label == "doorway" || label == "wall" || label == "window" {
                return true // ARKit detections are already validated
            }
            
            // Very strict filtering for person detections to reduce clustering
            // Person need high confidence (0.60) and reasonable size (0.2 height)
            if personLabels.contains(label) {
                return detection.confidence > 0.60 && detection.boundingBox.height > 0.2
            }
            
            // Stricter filtering for vehicles to reduce false positives
            // Vehicles need higher confidence (0.65) and larger size (0.3 height)
            if vehicleLabels.contains(label) {
                return detection.confidence > 0.65 && detection.boundingBox.height > 0.3
            }
            
            // Base filters for other objects: confidence and size
            guard detection.confidence > 0.45 && detection.boundingBox.height > 0.25 else {
                return false
            }
            
            return true
        }
        
        // Create unique keys for currently detected objects (label + position)
        let currentObjectKeys = Set(validDetections.map { createObjectKey(for: $0) })
        
        // Add current frame to history
        recentlyDetectedObjects.append(currentObjectKeys)
        if recentlyDetectedObjects.count > frameHistorySize {
            recentlyDetectedObjects.removeFirst()
        }
        
        // Find objects that have truly left the frame (not in last N frames)
        let objectsStillPresent = recentlyDetectedObjects.reduce(Set<String>()) { $0.union($1) }
        
        // Remove objects from announced set if they've been gone for several frames
        announcedObjects = announcedObjects.intersection(objectsStillPresent)
        
        // Only announce if requested (for speakable objects)
        guard announce else { return }
        
        // Announce only objects that haven't been announced yet
        for detection in validDetections {
            let objectKey = createObjectKey(for: detection)
            let label = detection.label.lowercased()
            
            // Skip if already announced
            guard !announcedObjects.contains(objectKey) else { continue }
            
            // Skip silent labels (windows)
            guard !silentLabels.contains(label) else { continue }
            
            // Only announce if in speakable list
            guard speakableLabels.contains(label) else { continue }
            
            // Global cooldown per label to avoid spam from micro-movements
            let now = Date()
            if let lastTime = lastAnnouncementTimeByLabel[label],
               now.timeIntervalSince(lastTime) < objectAnnouncementCooldown {
                continue
            }
            lastAnnouncementTimeByLabel[label] = now
            
            let position = describePosition(for: detection)
            let distance = estimateDistance(for: detection.boundingBox)
            let labelCapitalized = detection.label.capitalized
            
            // Include distance for all large objects
            // Make announcements more concise and clear
            let phrase: String
            if distance.contains("half") || distance.contains("1 meter") {
                // Close objects - emphasize proximity
                phrase = "\(labelCapitalized) \(position), \(distance). Be careful."
            } else {
                phrase = "\(labelCapitalized) \(position), \(distance)"
            }

            DispatchQueue.main.async {
                self.speechService.speak(label: labelCapitalized, phrase: phrase)
            }
            
            // Mark as announced
            announcedObjects.insert(objectKey)
        }
        
        announceMeshObstacleIfNeeded()
    }
    
    /// Creates a unique key for an object based on label and position
    /// This allows tracking the same object type in different positions separately
    private func createObjectKey(for detection: Detection) -> String {
        let label = detection.label.lowercased()
        let position = describePosition(for: detection)
        return "\(label)_\(position)"
    }

    private func describePosition(for detection: Detection) -> String {
        let centerX = detection.boundingBox.midX
        if centerX < 0.33 { return "on your left" }
        if centerX > 0.66 { return "on your right" }
        return "in front of you"
    }

    private func describeProximity(for height: CGFloat) -> String? {
        if height > 0.6 { return "Very close" }
        if height > 0.4 { return "Close" }
        return nil
    }
    
    /// Estimates approximate distance to object based on bounding box size
    /// Uses normalized height (0.0 to 1.0) as proxy for distance
    /// Returns distance in meters as a string
    private func estimateDistance(for boundingBox: CGRect) -> String {
        // Use both height and area for better distance estimation
        let height = boundingBox.height
        let area = boundingBox.width * boundingBox.height
        
        // Calibration: larger objects appear larger in frame when closer
        // These thresholds are calibrated for typical indoor distances
        if height > 0.7 || area > 0.5 {
            return "half a meter away"
        } else if height > 0.5 || area > 0.3 {
            return "1 meter away"
        } else if height > 0.35 || area > 0.15 {
            return "2 meters away"
        } else if height > 0.25 || area > 0.08 {
            return "2 and a half meters away"
        } else {
            return "3 meters away"
        }
    }
    
    
    private func announceMeshObstacleIfNeeded() {
        guard let nearestObstacle = arCamera.obstacles3D.first(where: { $0.type == .unknown }) else {
            return
        }
        
        let label = "obstacle"
        let now = Date()
        if let lastTime = lastAnnouncementTimeByLabel[label],
           now.timeIntervalSince(lastTime) < objectAnnouncementCooldown {
            return
        }
        lastAnnouncementTimeByLabel[label] = now
        
        let distance = estimateDistanceFor3DObstacle(nearestObstacle)
        let phrase = "Obstacle ahead, \(distance)."
        DispatchQueue.main.async {
            self.speechService.speak(label: "Obstacle", phrase: phrase)
        }
    }

    private func estimateDistanceFor3DObstacle(_ obstacle: Obstacle3D) -> String {
        guard let userPosition = arCamera.userPosition else {
            return "nearby"
        }
            let distance = simd_length(obstacle.position - userPosition)
        if distance < 0.8 { return "very close" }
        if distance < 1.5 { return "1 meter away" }
        if distance < 2.5 { return "2 meters away" }
        return "more than 2 meters away"
    }

    // MARK: - Currency Handling
    
    /// Double-tap handler: enter/exit currency mode.
    /// Note: Does NOT activate currency mode if QR pay mode is active - user must exit QR mode first.
    private func handleCurrencyModeToggleGesture() {
        DispatchQueue.main.async {
            if self.isCurrencyModeActive {
                self.deactivateCurrencyMode(announce: true)
            } else if !self.isQRPayModeActive {
                // Only activate currency mode if QR pay mode is NOT active
                self.activateCurrencyMode()
            }
            // If QR pay mode is active, ignore the double-tap (user must long-press to exit first)
        }
    }

    /// Long-press handler: enter/exit QR pay mode.
    /// Note: Does NOT activate QR mode if currency mode is active - user must exit currency mode first.
    private func handleQRModeToggleGesture() {
        DispatchQueue.main.async {
            if self.isQRPayModeActive {
                self.deactivateQRPayMode(announce: true)
            } else if !self.isCurrencyModeActive {
                // Only activate QR mode if currency mode is NOT active
                self.activateQRPayMode()
            }
            // If currency mode is active, ignore the long press (user must double-tap to exit first)
        }
    }

    private func activateCurrencyMode() {
        isCurrencyModeActive = true
        isQRPayModeActive = false

        TorchService.shared.setTorch(enabled: true, level: 1.0)
        currencyRecognition.activate()
        qrScanService.deactivate()

        detector.isPaused = true
        textRecognition.isPaused = true

        detectedCurrency = nil
        pendingCurrency = nil
        lastCurrencyPromptTime = .distantPast

        speechService.speak(label: "Mode", phrase: "Currency mode activated. Point camera at currency note.")
    }

    private func deactivateCurrencyMode(announce: Bool) {
        isCurrencyModeActive = false
        TorchService.shared.setTorch(enabled: false)
        currencyRecognition.deactivate()
        detector.isPaused = false
        textRecognition.isPaused = false
        detectedCurrency = nil
        pendingCurrency = nil
        lastCurrencyPromptTime = .distantPast
        if announce {
            speechService.speak(label: "Mode", phrase: "Currency mode deactivated")
        }
    }

    private func activateQRPayMode() {
        isQRPayModeActive = true
        isCurrencyModeActive = false

        // Configure QR scan behavior (QR contents are not used for amount)
        qrScanService.allowedRawValues = allowedQRRawValues
        qrScanService.activate()

        // Ensure currency is off
        currencyRecognition.deactivate()

        // Pause other Vision pipelines for speed + fewer conflicts
        detector.isPaused = true
        textRecognition.isPaused = true

    // Fully stop/clear text recognition state while QR mode is active
    textRecognition.recognizedTexts = []
    textRecognition.fullTextContent = ""
    detectedText = nil
    showTextConfirmation = false
    isReadingText = false
    lastPromptedText = nil
    lastPromptTime = .distantPast
    lastPromptAnnouncementTime = .distantPast
    lastTextDetectedTime = .distantPast

    pendingQRPayload = nil
    isSendingMoney = false
    lastQRPromptTime = .distantPast
    showQRAmountPrompt = false
    qrAmountInput = ""
    qrAmountError = nil

        TorchService.shared.setTorch(enabled: true, level: 1.0)
        speechService.speak(label: "Mode", phrase: "QR pay mode activated. Point camera at the QR code.")
    }

    private func deactivateQRPayMode(announce: Bool) {
        isQRPayModeActive = false
        qrScanService.deactivate()
        pendingQRPayload = nil
        isSendingMoney = false
        lastQRPromptTime = .distantPast
        showQRAmountPrompt = false
        qrAmountInput = ""
        qrAmountError = nil

        TorchService.shared.setTorch(enabled: false)
        detector.isPaused = false
        textRecognition.isPaused = false

        if announce {
            speechService.speak(label: "Mode", phrase: "QR pay mode deactivated")
        }
    }
    
    private func handleCurrencyDetection(_ currency: DetectedCurrency?) {
        // Only handle currency detection when in currency mode
        guard isCurrencyModeActive else { return }
        
        // If the model stops seeing currency, clear the pending state so a new note can be detected.
        // This prevents the "detects only once" behavior.
        if currency == nil {
            if pendingCurrency != nil {
                DispatchQueue.main.async {
                    self.pendingCurrency = nil
                    self.detectedCurrency = nil
                }
            }
            return
        }

        guard let currency = currency else { return }

        // If a different denomination appears, allow prompting again.
        if let pending = pendingCurrency, pending != currency {
            DispatchQueue.main.async {
                self.pendingCurrency = nil
                self.detectedCurrency = nil
                self.lastCurrencyPromptTime = .distantPast
            }
        }

        // If we already have a pending currency (same denomination) don't spam prompts.
        guard pendingCurrency == nil else { return }
        
        let now = Date()
        
        // Cooldown to avoid repeating announcement too frequently
        guard now.timeIntervalSince(lastCurrencyPromptTime) >= currencyPromptCooldown else {
            return
        }
        
        DispatchQueue.main.async {
            self.detectedCurrency = currency
            self.pendingCurrency = currency
            self.lastCurrencyPromptTime = now
            
            // Speak currency value (no deposit / wallet mutation)
            self.speechService.speak(label: "CurrencyPrompt", phrase: "Detected \(currency.name).")
        }
    }

    private func handleCurrencyConfirmationTap() {
        // Deposits are intentionally disabled. Single-tap confirmation does nothing in currency mode.
        // (Double-tap still exits currency mode.)
        return
    }

    // MARK: - QR Pay Handling

    private func handleQRPayload(_ payload: QRTransferPayload?) {
        guard isQRPayModeActive else { return }
        guard !isSendingMoney else { return }

        // If QR disappears, clear pending so a new QR can be detected.
        guard let payload else {
            if pendingQRPayload != nil && !showQRAmountPrompt {
                DispatchQueue.main.async {
                    self.pendingQRPayload = nil
                }
            }
            return
        }

        guard pendingQRPayload == nil else { return }

        let now = Date()
        guard now.timeIntervalSince(lastQRPromptTime) >= qrPromptCooldown else { return }

        DispatchQueue.main.async {
            self.pendingQRPayload = payload
            self.lastQRPromptTime = now
            self.showQRAmountPrompt = true
            self.qrAmountInput = ""
            self.qrAmountError = nil
            self.speechService.speak(label: "QRPrompt", phrase: "QR detected. Please enter the amount and tap confirm.")
        }
    }

    private func confirmQRAmountAndSend() {
        guard isQRPayModeActive else { return }
        guard let _ = pendingQRPayload else { return }
        guard !isSendingMoney else { return }
        guard !isAuthorizingPayment else { return }

        let trimmed = qrAmountInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = Int(trimmed), amount > 0 else {
            qrAmountError = "Enter a valid amount"
            speechService.speak(label: "WalletError", phrase: "Invalid amount. Please enter a valid amount.")
            return
        }

        qrAmountError = nil

        let announce = "You are paying \(amount) rupees. Please authorize with Face ID."
        speechService.speak(label: "Wallet", phrase: announce)

        let delay = estimateSpeechDelay(for: announce)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.authorizePayment { authorized in
                guard authorized else {
                    self.speechService.speak(label: "WalletError", phrase: "Authorization failed. Payment cancelled.")
                    return
                }

                self.isSendingMoney = true
                self.speechService.speak(label: "Wallet", phrase: "Sending \(amount) rupees.")

                WalletAPIService.shared.sendMoney(amount: amount, recipientPhone: defaultQRRecipientPhone, description: "QR payment") { result in
                    self.isSendingMoney = false
                    switch result {
                    case .success(let response):
                        let formattedBalance = self.formatCurrencyAmount(response.balance)
                        self.pendingQRPayload = nil
                        self.showQRAmountPrompt = false
                        self.qrAmountInput = ""
                        self.speechService.speak(label: "Wallet", phrase: "Payment sent. New balance \(formattedBalance) rupees.")
                    case .failure:
                        self.speechService.speak(label: "WalletError", phrase: "Unable to send money. Please try again.")
                    }
                }
            }
        }
    }

    private func cancelQRAmountPrompt() {
        pendingQRPayload = nil
        showQRAmountPrompt = false
        qrAmountInput = ""
        qrAmountError = nil
        speechService.speak(label: "QRPrompt", phrase: "Payment cancelled.")
    }

    private func authorizePayment(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }

        isAuthorizingPayment = true
        let reason = "Authorize payment with Face ID"
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                self.isAuthorizingPayment = false
                completion(success)
            }
        }
    }

    private func estimateSpeechDelay(for phrase: String) -> TimeInterval {
        // Rough estimate: base 1.0s + 0.18s per word
        let words = phrase.split(separator: " ").count
        return 1.0 + (Double(words) * 0.18)
    }

    // MARK: - Gesture routing

    private func handlePrimaryConfirmationTap() {
        if isCurrencyModeActive {
            handleCurrencyConfirmationTap()
            return
        }
        if isQRPayModeActive {
            // QR mode uses the on-screen amount prompt confirm button.
            return
        }
        // Normal mode: no-op for now
    }

    private func formatCurrencyAmount(_ amount: Double) -> String {
        if amount.rounded(.towardZero) == amount {
            return String(format: "%.0f", amount)
        }
        return String(format: "%.2f", amount)
    }
    
    // Handle text detection - prompt user instead of auto-reading
    private func handleTextDetection(_ textContent: String) {
        // Normalize text: remove extra whitespace, lowercase for comparison
        let normalizedText = textContent
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
        
        let now = Date()
        
        // Only prompt for meaningful text (5+ characters)
        guard normalizedText.count >= 5 else {
            // Keep prompt visible briefly so taps still work
            if showTextConfirmation,
               now.timeIntervalSince(lastTextDetectedTime) > textPromptGracePeriod {
                dismissTextPrompt()
            }
            return
        }
        
        // Update last seen time
        lastTextDetectedTime = now
        
        // CRITICAL: 5-second timeout - cannot say "Text detected" again until 5 seconds have passed
        guard now.timeIntervalSince(lastPromptAnnouncementTime) >= textPromptCooldown else {
            // Even if we can't announce, update the current text (no queue - always latest)
            DispatchQueue.main.async {
                let displayText = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
                self.detectedText = displayText
                self.showTextConfirmation = true // Keep prompt active if it was active
            }
            return // Don't announce "Text detected" if we just said it
        }
        
        // Check if we've already prompted for similar text recently
        let isSimilarText = isTextSimilar(normalizedText, to: lastPromptedText)
        let isInCooldown = now.timeIntervalSince(lastPromptTime) < textPromptCooldown
        
        // Don't prompt if it's similar text and we're in cooldown
        if isSimilarText && isInCooldown {
            // Still update current text (no queue - always latest)
            DispatchQueue.main.async {
                let displayText = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
                self.detectedText = displayText
                self.showTextConfirmation = true
            }
            return
        }
        
        // Don't prompt if we just read text (cooldown after reading)
        guard now.timeIntervalSince(lastTextAnnouncementTime) >= textPromptCooldown else {
            // Still update current text (no queue - always latest)
            DispatchQueue.main.async {
                let displayText = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
                self.detectedText = displayText
                self.showTextConfirmation = true // Keep prompt active
            }
            return
        }
        
        // Check if current detected text is similar to what we're showing
        let isSimilarToCurrent = isTextSimilar(normalizedText, to: detectedText?.lowercased())
        
        // Always update to latest text (no queue - replace old text)
        DispatchQueue.main.async {
            // Use original text (not normalized) for display/reading
            let displayText = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            self.detectedText = displayText // Always update to latest text
            self.showTextConfirmation = true
            
            // Only announce if text is meaningfully different
            if !isSimilarToCurrent {
                self.lastPromptedText = normalizedText
                self.lastPromptTime = now
                self.lastPromptAnnouncementTime = now // Track when we said "Text detected"
                // Announce prompt for blind users
                self.speechService.speak(label: "Text", phrase: "Text detected. Tap screen to read.")
            }
        }
    }
    
    // Check if two text strings are similar (handles minor variations from camera movement)
    private func isTextSimilar(_ text1: String, to text2: String?) -> Bool {
        guard let text2 = text2 else { return false }
        
        // Exact match
        if text1 == text2 {
            return true
        }
        
        // Calculate similarity using Levenshtein distance or simple word overlap
        let similarity = calculateTextSimilarity(text1, text2)
        return similarity >= textSimilarityThreshold
    }
    
    // Calculate text similarity (0.0 to 1.0)
    private func calculateTextSimilarity(_ text1: String, _ text2: String) -> Double {
        // Simple word-based similarity
        let words1 = Set(text1.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
        let words2 = Set(text2.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
        
        guard !words1.isEmpty && !words2.isEmpty else { return 0.0 }
        
        let intersection = words1.intersection(words2)
        let union = words1.union(words2)
        
        // Jaccard similarity: intersection / union
        return Double(intersection.count) / Double(union.count)
    }
    
    // Read the detected text aloud
    private func readDetectedText(_ text: String) {
        let currentText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentText.isEmpty else { return }
        
        // Dismiss prompt first
        dismissTextPrompt()
        
        let phrase = "Text: \(currentText)"
        DispatchQueue.main.async {
            // Mark that we're reading text immediately (notification will also set this, but we set it early for UI)
            self.isReadingText = true
            self.speechService.speak(label: "TextReading", phrase: phrase)
            self.lastTextAnnouncementTime = Date()
            // Clear the prompted text so it can be prompted again later if needed
            self.lastPromptedText = nil
            // Clear detected text after reading
            self.detectedText = nil
        }
    }
    
    // Stop text reading when user taps screen
    private func stopTextReading() {
        // Stop speech and clear state immediately
        self.speechService.stopAndClear()
        DispatchQueue.main.async {
            self.isReadingText = false
            print("DEBUG: Text reading stopped by user tap")
        }
    }
    
    // Dismiss the text prompt
    private func dismissTextPrompt() {
        DispatchQueue.main.async {
            self.showTextConfirmation = false
            // Clear detectedText after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if !self.showTextConfirmation {
                    self.detectedText = nil
                }
            }
        }
    }
}

struct DetectionBox: View {
    let detection: Detection
    var color: Color = .green
    
    var body: some View {
        GeometryReader { geo in
            let box = detection.boundingBox
            let rect = CGRect(
                x: box.minX * geo.size.width,
                y: (1 - box.maxY) * geo.size.height,
                width: box.width * geo.size.width,
                height: box.height * geo.size.height
            )
            
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .path(in: rect)
                    .stroke(color, lineWidth: 2)
                Text("\(detection.label) \(Int(detection.confidence * 100))%")
                    .font(.caption2)
                    .padding(4)
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .offset(x: rect.minX, y: rect.minY - 18)
            }
        }
        .allowsHitTesting(false)
    }
}

struct TextBox: View {
    let recognizedText: RecognizedText
    
    var body: some View {
        GeometryReader { geo in
            let box = recognizedText.boundingBox
            let rect = CGRect(
                x: box.minX * geo.size.width,
                y: (1 - box.maxY) * geo.size.height,
                width: box.width * geo.size.width,
                height: box.height * geo.size.height
            )
            
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .path(in: rect)
                    .stroke(Color.yellow, lineWidth: 2)
                Text(recognizedText.text)
                    .font(.caption2)
                    .padding(4)
                    .background(Color.yellow.opacity(0.8))
                    .foregroundColor(.black)
                    .offset(x: rect.minX, y: rect.minY - 18)
            }
        }
        .allowsHitTesting(false)
    }
}
