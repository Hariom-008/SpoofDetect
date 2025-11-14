// File: FaceDetector.swift

import Foundation
import UIKit

class FaceDetector: Component {
    private var nativeHandler: UnsafeMutableRawPointer?
    
    override init() {
        super.init()
        nativeHandler = createInstance()
    }
    
    override func createInstance() -> UnsafeMutableRawPointer? {
        return allocate()
    }
    
    func loadModel() -> Int32 {
        guard let handler = nativeHandler else { return -1 }
        return nativeLoadModel(handler)
    }
    
    func detect(image: UIImage) throws -> [FaceBox] {
        guard let cgImage = image.cgImage else {
            throw FaceDetectorError.invalidImage
        }
        
        guard let handler = nativeHandler else {
            throw FaceDetectorError.nativeHandlerNotInitialized
        }
        
        return nativeDetectImage(handler, cgImage)
    }
    
    func detect(yuv: Data, width: Int, height: Int, orientation: Int) throws -> [FaceBox] {
        // Actually RGBA: width * height * 4
        let expectedSize = width * height * 4
        guard yuv.count == expectedSize else {
            throw FaceDetectorError.invalidYUVData
        }
        
        guard let handler = nativeHandler else {
            throw FaceDetectorError.nativeHandlerNotInitialized
        }
        
        return yuv.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return [] }
            return nativeDetectYUV(
                handler,
                baseAddress,
                Int32(width),
                Int32(height),
                Int32(orientation)
            )
        }
    }
    
    override func destroy() {
        if let handler = nativeHandler {
            deallocate(handler)
            nativeHandler = nil
        }
    }
    
    // MARK: - Native Methods
    
    private func allocate() -> UnsafeMutableRawPointer? {
        return engine_face_detector_allocate()
    }
    
    private func deallocate(_ handler: UnsafeMutableRawPointer) {
        engine_face_detector_deallocate(handler)
    }
    
    private func nativeLoadModel(_ handler: UnsafeMutableRawPointer) -> Int32 {
        return engine_face_detector_load_model(handler)
    }
    
    private func nativeDetectImage(_ handler: UnsafeMutableRawPointer, _ image: CGImage) -> [FaceBox] {
        var faceCount: Int32 = 0
        let facesPtr = engine_face_detector_detect_image(handler, image, &faceCount)
        
        guard let faces = facesPtr else { return [] }
        
        var result: [FaceBox] = []
        for i in 0..<Int(faceCount) {
            let face = faces[i]
            let faceBox = FaceBox(
                left: Int(face.left),
                top: Int(face.top),
                right: Int(face.right),
                bottom: Int(face.bottom),
                confidence: face.confidence
            )
            result.append(faceBox)
        }
        
        engine_face_detector_free_faces(facesPtr)
        return result
    }
    
    private func nativeDetectYUV(
        _ handler: UnsafeMutableRawPointer,
        _ yuv: UnsafeRawPointer,
        _ width: Int32,
        _ height: Int32,
        _ orientation: Int32
    ) -> [FaceBox] {
        var faceCount: Int32 = 0
        let facesPtr = engine_face_detector_detect_yuv(handler, yuv, width, height, orientation, &faceCount)
        
        guard let faces = facesPtr else { return [] }
        
        var result: [FaceBox] = []
        for i in 0..<Int(faceCount) {
            let face = faces[i]
            let faceBox = FaceBox(
                left: Int(face.left),
                top: Int(face.top),
                right: Int(face.right),
                bottom: Int(face.bottom),
                confidence: face.confidence
            )
            result.append(faceBox)
        }
        
        engine_face_detector_free_faces(facesPtr)
        return result
    }
}

// MARK: - Error Types

enum FaceDetectorError: Error {
    case invalidImage
    case invalidYUVData
    case nativeHandlerNotInitialized
    
    var localizedDescription: String {
        switch self {
        case .invalidImage:
            return "Invalid image format"
        case .invalidYUVData:
            return "Invalid frame buffer size (expected RGBA)"
        case .nativeHandlerNotInitialized:
            return "Native handler not initialized"
        }
    }
}

// MARK: - Native C Function Declarations

@_silgen_name("engine_face_detector_allocate")
func engine_face_detector_allocate() -> UnsafeMutableRawPointer?

@_silgen_name("engine_face_detector_deallocate")
func engine_face_detector_deallocate(_ handler: UnsafeMutableRawPointer)

@_silgen_name("engine_face_detector_load_model")
func engine_face_detector_load_model(_ handler: UnsafeMutableRawPointer) -> Int32

@_silgen_name("engine_face_detector_detect_image")
func engine_face_detector_detect_image(
    _ handler: UnsafeMutableRawPointer,
    _ image: CGImage,
    _ faceCount: UnsafeMutablePointer<Int32>
) -> UnsafeMutablePointer<CFaceBox>?

@_silgen_name("engine_face_detector_detect_yuv")
func engine_face_detector_detect_yuv(
    _ handler: UnsafeMutableRawPointer,
    _ yuv: UnsafeRawPointer,
    _ width: Int32,
    _ height: Int32,
    _ orientation: Int32,
    _ faceCount: UnsafeMutablePointer<Int32>
) -> UnsafeMutablePointer<CFaceBox>?

@_silgen_name("engine_face_detector_free_faces")
func engine_face_detector_free_faces(_ faces: UnsafeMutablePointer<CFaceBox>?)

// C-compatible FaceBox structure
struct CFaceBox {
    var left: Int32
    var top: Int32
    var right: Int32
    var bottom: Int32
    var confidence: Float
}
