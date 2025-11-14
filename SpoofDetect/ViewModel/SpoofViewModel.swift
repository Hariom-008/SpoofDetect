// SpoofViewModel.swift
import SwiftUI
import AVFoundation
import Combine

class SpoofViewModel: NSObject, ObservableObject {
    @Published var livenessScore: Float = 0.0
    @Published var statusText: String = "Waiting for face..."
    @Published var modelsLoaded: Bool = false
    @Published var modelsLoadedText: String = "Loading..."
    @Published var hasCameraPermission: Bool = false
    
    private var faceDetector: FaceDetector?
    private var liveDetector: LiveDetector?
    
    override init() {
        super.init()
        print("SpoofViewModel initialized")
    }
    
    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasCameraPermission = true
            print("Camera permission: authorized")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.hasCameraPermission = granted
                    print("Camera permission: \(granted ? "granted" : "denied")")
                }
            }
        default:
            hasCameraPermission = false
            print("Camera permission: denied")
        }
    }
    
    func loadModels() {
        print("Loading native models...")
        faceDetector = FaceDetector()
        liveDetector = LiveDetector()
        
        let detRes = faceDetector?.loadModel() ?? -1
        let liveRes = liveDetector?.loadModel() ?? -1
        
        print("FaceDetector loadModel=\(detRes), LiveDetector loadModel=\(liveRes)")
        modelsLoadedText = "det=\(detRes), live=\(liveRes)"
        modelsLoaded = (detRes == 0 && liveRes == 0)
    }
    
    func processFrame(buffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else {
            print("Failed to get image buffer")
            return
        }
        
        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        
        print("Processing frame: \(width)x\(height)")
        
        // Convert to NV21 format
        guard let nv21Data = convertToNV21(pixelBuffer: imageBuffer) else {
            print("Failed to convert to NV21")
            updateResult(score: 0.0)
            return
        }
        
        print("NV21 data size: \(nv21Data.count), expected: \(width * height * 3 / 2)")
        
        // Detect faces
        guard let faces = faceDetector?.detect(
            yuv: nv21Data,
            width: Int32(width),
            height: Int32(height),
            orientation: 0
        ), !faces.isEmpty else {
            print("No faces detected")
            updateResult(score: 0.0)
            return
        }
        
        let face = faces[0]
        print("First face detected: left=\(face.left), top=\(face.top), right=\(face.right), bottom=\(face.bottom)")
        
        // Liveness detection
        let score = liveDetector?.detect(
            yuv: nv21Data,
            width: Int32(width),
            height: Int32(height),
            orientation: 0,
            faceBox: face
        ) ?? 0.0
        
        print("Liveness score (raw): \(score)")
        updateResult(score: score)
    }
    
    private func updateResult(score: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.livenessScore = score
            self?.statusText = {
                switch score {
                case 0.0:
                    return "No face / low confidence"
                case 0.9...:
                    return "REAL FACE ✅"
                default:
                    return "Possible SPOOF ⚠️"
                }
            }()
        }
    }
    
    private func convertToNV21(pixelBuffer: CVPixelBuffer) -> Data? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        let uvPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
        
        let ySize = width * height
        let uvSize = width * height / 2
        
        var nv21 = Data(count: ySize + uvSize)
        
        // Copy Y plane
        if let yPlane = yPlane {
            let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            for row in 0..<height {
                let srcOffset = row * yStride
                let dstOffset = row * width
                nv21.replaceSubrange(dstOffset..<(dstOffset + width),
                                    with: yPlane.advanced(by: srcOffset).assumingMemoryBound(to: UInt8.self),
                                    count: width)
            }
            print("Y plane copied")
        }
        
        // Copy and interleave UV plane (NV12 to NV21 conversion: swap U and V)
        if let uvPlane = uvPlane {
            let uvStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            var outPos = ySize
            
            for row in 0..<(height / 2) {
                for col in 0..<(width / 2) {
                    let uvIndex = row * uvStride + col * 2
                    let u = uvPlane.advanced(by: uvIndex).assumingMemoryBound(to: UInt8.self).pointee
                    let v = uvPlane.advanced(by: uvIndex + 1).assumingMemoryBound(to: UInt8.self).pointee
                    
                    // NV21 expects V then U (opposite of NV12)
                    nv21[outPos] = v
                    nv21[outPos + 1] = u
                    outPos += 2
                }
            }
            print("UV plane copied and converted to NV21")
        }
        
        return nv21
    }
}
