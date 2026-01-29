import SwiftUI
import ARKit
import SceneKit

struct CameraPreview: UIViewRepresentable {
    let arCameraService: ARCameraService
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView()
        
        // Set background color to prevent black screen during initialization
        arView.backgroundColor = .black
        
        // Configure the AR view for camera preview
        arView.automaticallyUpdatesLighting = false
        arView.isUserInteractionEnabled = false
        
        // Hide debug options (we don't want to show plane meshes)
        arView.debugOptions = []
        
        // Use a simple scene with no content (just camera feed)
        arView.scene = SCNScene()
        
        // Set rendering delegate if needed for custom rendering
        arView.delegate = context.coordinator
        
        // Set session after view is created to ensure proper initialization
        arView.session = arCameraService.getSession()
        
        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // ARSCNView automatically handles orientation
        // No manual updates needed
    }
    
    class Coordinator: NSObject, ARSCNViewDelegate {
        // Optional: Implement delegate methods if needed for custom rendering
        // For now, we just need the camera feed to display
    }
}
