// File: FaceDetectionView.swift
// SpoofDetect

import Foundation
import SwiftUI
import AVFoundation
import UIKit
import Combine

struct FaceDetectionView: View {
    @StateObject private var viewModel = FaceDetectionViewModel()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Camera preview
                ZStack {
                    CameraPreviewView(viewModel: viewModel)
                        .overlay(
                            FaceBoxOverlay(faces: viewModel.detectedFaces)
                        )
                }
                .frame(maxHeight: 500)
                .background(Color.black)
                .cornerRadius(12)
                
                // Detection info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Detected Faces: \(viewModel.detectedFaces.count)")
                        .font(.headline)
                    
                    if let livenessScore = viewModel.livenessScore {
                        HStack {
                            Text("Liveness Score:")
                                .font(.subheadline)
                            Text(String(format: "%.2f", livenessScore))
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(livenessScore > 0.5 ? .green : .red)
                        }
                    }
                    
                    ForEach(Array(viewModel.detectedFaces.enumerated()), id: \.offset) { index, face in
                        HStack {
                            Text("Face \(index + 1):")
                            Text("Confidence: \(String(format: "%.2f", face.confidence))")
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                
                if viewModel.isProcessingModels {
                    ProgressView("Loading models...")
                }
                
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .navigationTitle("Face Detection")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            viewModel.loadModels()
        }
    }
}

// MARK: - Face Box Overlay

struct FaceBoxOverlay: View {
    let faces: [FaceBox]
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(faces.enumerated()), id: \.offset) { _, face in
                Rectangle()
                    .stroke(Color.green, lineWidth: 2)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight:.infinity
                    )
                    .position(
                        x: CGFloat(face.center.x),
                        y: CGFloat(face.center.y)
                    )
                    .overlay(
                        Text(String(format: "%.0f%%", face.confidence * 100))
                            .font(.caption2)
                            .padding(4)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                            .position(
                                x: CGFloat(face.left),
                                y: CGFloat(face.top - 10)
                            )
                    )
            }
        }
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var viewModel: FaceDetectionViewModel
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.delegate = viewModel
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Nothing to update for now
    }
}

class CameraPreviewUIView: UIView {
    weak var delegate: CameraPreviewDelegate?
    
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "CameraVideoOutputQueue")
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCamera()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCamera()
    }
    
    private func setupCamera() {
        backgroundColor = .black
        
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        
        // Front camera
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .front) else {
            print("⚠️ No front camera found")
            session.commitConfiguration()
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            // 32BGRA from camera
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
            
            if let connection = videoOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
                // Do NOT mirror for now, so boxes line up
                connection.isVideoMirrored = false
            }
            
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(previewLayer)
            self.previewLayer = previewLayer
            
            session.commitConfiguration()
            session.startRunning()
        } catch {
            print("⚠️ Camera setup error: \(error)")
            session.commitConfiguration()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

extension CameraPreviewUIView: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        delegate?.didCapture(imageBuffer: buffer)
    }
}

// MARK: - Camera Preview Delegate

protocol CameraPreviewDelegate: AnyObject {
    func didCapture(imageBuffer: CVImageBuffer)
}

// MARK: - View Model

class FaceDetectionViewModel: ObservableObject, CameraPreviewDelegate {
    @Published var detectedFaces: [FaceBox] = []
    @Published var livenessScore: Float?
    @Published var isProcessingModels = false
    @Published var errorMessage: String?
    
    private var faceDetector: FaceDetector?
    private var liveness: Live?
    
    private let processingQueue = DispatchQueue(label: "FaceDetectionProcessingQueue")
    private var isProcessingFrame = false
    private var modelsLoaded = false
    
    init() {
        faceDetector = FaceDetector()
        liveness = Live()
    }
    
    func loadModels() {
        isProcessingModels = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let faceResult = self.faceDetector?.loadModel() ?? -1
            if faceResult != 0 {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load face detection model"
                    self.isProcessingModels = false
                }
                return
            }
            
            let liveResult = self.liveness?.loadModel() ?? -1
            if liveResult != 0 {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load liveness model"
                    self.isProcessingModels = false
                }
                return
            }
            
            DispatchQueue.main.async {
                self.modelsLoaded = true
                self.isProcessingModels = false
            }
        }
    }
    
    // Camera frame callback
    func didCapture(imageBuffer: CVImageBuffer) {
        // Don’t fry the device
        if isProcessingFrame || !modelsLoaded {
            return
        }
        isProcessingFrame = true
        
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        
        guard let rgbaData = Self.makeRGBAData(from: imageBuffer) else {
            isProcessingFrame = false
            return
        }
        
        let orientation = 0 // engine ignores this currently
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let faces = try self.faceDetector?.detect(
                    yuv: rgbaData,
                    width: width,
                    height: height,
                    orientation: orientation
                ) ?? []
                
                var liveScore: Float? = nil
                if let firstFace = faces.first {
                    liveScore = try? self.liveness?.detect(
                        yuv: rgbaData,
                        width: width,
                        height: height,
                        orientation: orientation,
                        faceBox: firstFace
                    )
                }
                
                DispatchQueue.main.async {
                    self.detectedFaces = faces
                    if let score = liveScore {
                        self.livenessScore = score
                        print("🔍 Liveness score: \(score)")
                    }
                    self.isProcessingFrame = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isProcessingFrame = false
                }
            }
        }
    }
    
    // Convert 32BGRA from camera → contiguous RGBA buffer (what engine_ncnn.mm expects)
    private static func makeRGBAData(from imageBuffer: CVImageBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer) else {
            return nil
        }
        
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        
        let srcPtr = baseAddress.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        
        var rgba = Data(count: width * height * 4)
        rgba.withUnsafeMutableBytes { destRaw in
            guard let dstBase = destRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            
            for y in 0..<height {
                let srcRow = srcPtr.advanced(by: y * bytesPerRow)
                let dstRow = dstBase.advanced(by: y * width * 4)
                
                for x in 0..<width {
                    let srcPixel = srcRow.advanced(by: x * 4) // BGRA
                    let dstPixel = dstRow.advanced(by: x * 4) // RGBA
                    
                    let b = srcPixel[0]
                    let g = srcPixel[1]
                    let r = srcPixel[2]
                    let a = srcPixel[3]
                    
                    dstPixel[0] = r
                    dstPixel[1] = g
                    dstPixel[2] = b
                    dstPixel[3] = a
                }
            }
        }
        
        return rgba
    }
}

// MARK: - Preview

struct FaceDetectionView_Previews: PreviewProvider {
    static var previews: some View {
        FaceDetectionView()
    }
}
