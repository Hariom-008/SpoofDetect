// CameraPreview.swift
import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var viewModel: SpoofViewModel
    
    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.delegate = context.coordinator
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    class Coordinator: NSObject, CameraPreviewDelegate {
        let viewModel: SpoofViewModel
        
        init(viewModel: SpoofViewModel) {
            self.viewModel = viewModel
        }
        
        func didCapture(sampleBuffer: CMSampleBuffer) {
            viewModel.processFrame(buffer: sampleBuffer)
        }
    }
}

protocol CameraPreviewDelegate: AnyObject {
    func didCapture(sampleBuffer: CMSampleBuffer)
}

class CameraPreviewView: UIView {
    weak var delegate: CameraPreviewDelegate?
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCamera()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCamera()
    }
    
    private func setupCamera() {
        print("Setting up camera...")
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("Failed to get front camera")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
                print("Camera input added")
            }
        } catch {
            print("Error creating camera input: \(error)")
            return
        }
        
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            print("Video output added")
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
        
        self.captureSession = session
        self.previewLayer = previewLayer
        
        sessionQueue.async {
            session.startRunning()
            print("Camera session started")
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

extension CameraPreviewView: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        delegate?.didCapture(sampleBuffer: sampleBuffer)
    }
}
