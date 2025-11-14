// NativeBridge.swift
import Foundation

// MARK: - FaceBox Structure
struct FaceBox {
    let left: Int32
    let top: Int32
    let right: Int32
    let bottom: Int32
    let confidence: Float
}

// MARK: - Face Detector
class FaceDetector {
    private var handle: UnsafeMutableRawPointer?
    
    init() {
        print("FaceDetector: Creating instance")
        handle = face_detector_create()
        if handle == nil {
            print("FaceDetector: Failed to create handle")
        }
    }
    
    deinit {
        print("FaceDetector: Destroying instance")
        if let handle = handle {
            face_detector_destroy(handle)
        }
    }
    
    func loadModel() -> Int32 {
        guard let handle = handle else {
            print("FaceDetector: Invalid handle")
            return -1
        }
        
        guard let modelPath = Bundle.main.resourcePath else {
            print("FaceDetector: Failed to get resource path")
            return -1
        }
        
        let result = modelPath.withCString { pathPtr in
            return face_detector_load_model(handle, pathPtr)
        }
        
        print("FaceDetector: loadModel result = \(result)")
        return result
    }
    
    func detect(yuv: Data, width: Int32, height: Int32, orientation: Int32) -> [FaceBox] {
        guard let handle = handle else {
            print("FaceDetector: Invalid handle")
            return []
        }
        
        var facesPtr: UnsafeMutablePointer<FaceBox>?
        var count: Int32 = 0
        
        let result = yuv.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int32 in
            guard let baseAddress = buffer.baseAddress else {
                print("FaceDetector: Failed to get buffer base address")
                return -1
            }
            let uint8Ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
            return face_detector_detect_yuv(handle, uint8Ptr, width, height, orientation, &facesPtr, &count)
        }
        
        print("FaceDetector: detect result = \(result), count = \(count)")
        
        guard result == 0, let faces = facesPtr, count > 0 else {
            print("FaceDetector: No faces detected or error occurred")
            return []
        }
        
        // Copy face data to Swift array
        let faceArray = Array(UnsafeBufferPointer(start: faces, count: Int(count)))
        
        // Free C-allocated memory
        face_detector_free_faces(faces)
        
        print("FaceDetector: Returning \(faceArray.count) faces")
        return faceArray
    }
}

// MARK: - Live Detector
class LiveDetector {
    private var handle: UnsafeMutableRawPointer?
    
    init() {
        print("LiveDetector: Creating instance")
        handle = live_detector_create()
        if handle == nil {
            print("LiveDetector: Failed to create handle")
        }
    }
    
    deinit {
        print("LiveDetector: Destroying instance")
        if let handle = handle {
            live_detector_destroy(handle)
        }
    }
    
    func loadModel() -> Int32 {
        guard let handle = handle else {
            print("LiveDetector: Invalid handle")
            return -1
        }
        
        guard let modelPath = Bundle.main.resourcePath else {
            print("LiveDetector: Failed to get resource path")
            return -1
        }
        
        let result = modelPath.withCString { pathPtr in
            return live_detector_load_model(handle, pathPtr)
        }
        
        print("LiveDetector: loadModel result = \(result)")
        return result
    }
    
    func detect(yuv: Data, width: Int32, height: Int32, orientation: Int32, faceBox: FaceBox) -> Float {
        guard let handle = handle else {
            print("LiveDetector: Invalid handle")
            return 0.0
        }
        
        let score = yuv.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Float in
            guard let baseAddress = buffer.baseAddress else {
                print("LiveDetector: Failed to get buffer base address")
                return 0.0
            }
            let uint8Ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
            return live_detector_detect_yuv(
                handle,
                uint8Ptr,
                width,
                height,
                orientation,
                faceBox.left,
                faceBox.top,
                faceBox.right,
                faceBox.bottom
            )
        }
        
        print("LiveDetector: score = \(score)")
        return score
    }
}
