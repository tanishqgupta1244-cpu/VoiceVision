import Foundation
import simd

/// Represents a 3D obstacle in the environment
struct Obstacle3D: Identifiable {
    let id = UUID()
    let type: ObstacleType
    let position: simd_float3  // Center position in world coordinates
    let size: simd_float3      // Width, height, depth
    let boundingBox: CGRect?  // 2D screen projection (optional)
    let confidence: Float
    
    enum ObstacleType {
        case wall
        case furniture      // Chairs, tables, etc.
        case doorway
        case window
        case person
        case vehicle
        case unknown
    }
    
    /// Get the 2D footprint (X and Z dimensions, ignoring Y/height)
    var footprint: (width: Float, depth: Float) {
        return (size.x, size.z)
    }
    
    /// Check if obstacle is at ground level (within threshold)
    func isAtGroundLevel(threshold: Float = 0.3) -> Bool {
        return abs(position.y) < threshold
    }
    
    /// Get bounding box corners in 2D (X-Z plane)
    func get2DCorners() -> [simd_float2] {
        let halfWidth = size.x / 2.0
        let halfDepth = size.z / 2.0
        
        return [
            simd_float2(position.x - halfWidth, position.z - halfDepth), // Bottom-left
            simd_float2(position.x + halfWidth, position.z - halfDepth), // Bottom-right
            simd_float2(position.x + halfWidth, position.z + halfDepth), // Top-right
            simd_float2(position.x - halfWidth, position.z + halfDepth)  // Top-left
        ]
    }
}
