import SwiftUI

struct AntiSpoofView: View {
    @StateObject private var camera = CameraManager()

    var status: String {
        let s = camera.score
        if s == 0 { return "No Face" }
        if s > 0.8 { return "REAL FACE 🟢" }
        if s > 0.5 { return "Probably Real 🟡" }
        return "SPOOF DETECTED 🔴"
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Score: \(camera.score, specifier: "%.3f")")
                .font(.headline)

            Text(status)
                .font(.title2)
                .bold()
                .foregroundColor(.blue)

            Spacer()
        }
        .padding()
    }
}

// SpoofScreen.swift
import SwiftUI
import AVFoundation

struct SpoofScreen: View {
    @StateObject private var viewModel = SpoofViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Camera preview
            ZStack {
                if viewModel.hasCameraPermission {
                    CameraPreview(viewModel: viewModel)
                } else {
                    Text("Camera permission not granted")
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Results card
            VStack(spacing: 12) {
                Text("Liveness score: \(String(format: "%.3f", viewModel.livenessScore))")
                    .font(.headline)
                
                Text(viewModel.statusText)
                    .font(.body)
                
                if !viewModel.modelsLoaded {
                    Text("Loading models...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text("Models: \(viewModel.modelsLoadedText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 4)
            .padding()
        }
        .onAppear {
            viewModel.checkCameraPermission()
            viewModel.loadModels()
        }
    }
}
