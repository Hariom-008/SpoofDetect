//
//  FaceDetectionView.swift
//  SpoofDetect
//
//  Created by Hari's Mac on 14.11.2025.
//

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
                // Camera preview or selected image
                ZStack {
                    if let image = viewModel.selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .overlay(
                                FaceBoxOverlay(faces: viewModel.detectedFaces)
                            )
                    } else {
                        CameraPreviewView(viewModel: viewModel)
                            .overlay(
                                FaceBoxOverlay(faces: viewModel.detectedFaces)
                            )
                    }
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
                
                // Action buttons
                HStack(spacing: 16) {
                    Button(action: viewModel.selectImage) {
                        Label("Choose Photo", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: viewModel.capturePhoto) {
                        Label("Capture", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                if viewModel.isProcessing {
                    ProgressView("Processing...")
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
            ForEach(Array(faces.enumerated()), id: \.offset) { index, face in
                Rectangle()
                    .stroke(Color.green, lineWidth: 2)
                    .frame(
                        width: CGFloat(face.width),
                        height: CGFloat(face.height)
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
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

class CameraPreviewUIView: UIView {
    weak var delegate: CameraPreviewDelegate?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCamera()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupCamera() {
        // Camera setup would go here
        backgroundColor = .black
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

protocol CameraPreviewDelegate: AnyObject {
    func didCapture(imageBuffer: CVImageBuffer)
}

// MARK: - View Model

class FaceDetectionViewModel: ObservableObject, CameraPreviewDelegate {
    @Published var selectedImage: UIImage?
    @Published var detectedFaces: [FaceBox] = []
    @Published var livenessScore: Float?
    @Published var isProcessing = false
    @Published var errorMessage: String?
    
    private var faceDetector: FaceDetector?
    private var liveness: Live?
    
    init() {
        faceDetector = FaceDetector()
        liveness = Live()
    }
    
    func loadModels() {
        isProcessing = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Load face detector model
            let faceResult = self.faceDetector?.loadModel() ?? -1
            if faceResult != 0 {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load face detection model"
                    self.isProcessing = false
                }
                return
            }
            
            // Load liveness model
            let liveResult = self.liveness?.loadModel() ?? -1
            if liveResult != 0 {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load liveness model"
                    self.isProcessing = false
                }
                return
            }
            
            DispatchQueue.main.async {
                self.isProcessing = false
            }
        }
    }
    
    func selectImage() {
        // Image picker implementation
    }
    
    func capturePhoto() {
        // Capture implementation
    }
    
    func detectFaces(in image: UIImage) {
        isProcessing = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let faces = try self.faceDetector?.detect(image: image) ?? []
                
                DispatchQueue.main.async {
                    self.detectedFaces = faces
                    self.isProcessing = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }
    
    func didCapture(imageBuffer: CVImageBuffer) {
        // Handle camera frame capture
    }
}

// MARK: - Preview

struct FaceDetectionView_Previews: PreviewProvider {
    static var previews: some View {
        FaceDetectionView()
    }
}
