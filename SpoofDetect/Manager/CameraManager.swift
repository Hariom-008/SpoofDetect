import AVFoundation
import SwiftUI
import Combine

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    @Published var score: Float = 0

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera.queue")

    override init() {
        super.init()
        setupCamera()
    }

    func setupCamera() {
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: queue)

        session.addOutput(output)
        session.startRunning()
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)

        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            return
        }

        // BGRA → pass as RGBA (NCNN will handle)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        let result = NativeNCNN.run(
            UnsafeMutablePointer(mutating: ptr),
            width: Int32(width),
            height: Int32(height)
        )

        DispatchQueue.main.async {
            self.score = result
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
    }
}
