// File: Live.swift

import Foundation
import UIKit
import os.log

class Live: Component {
    private var nativeHandler: UnsafeMutableRawPointer?
    private static let log = OSLog(subsystem: "com.mv.engine", category: "Live")
    
    override init() {
        super.init()
        nativeHandler = createInstance()
    }
    
    override func createInstance() -> UnsafeMutableRawPointer? {
        return allocate()
    }
    
    override func destroy() {
        if let handler = nativeHandler {
            deallocate(handler)
            nativeHandler = nil
        }
    }
    
    func loadModel() -> Int32 {
        guard let configs = parseConfig() else {
            os_log("Parse model config failed", log: Live.log, type: .error)
            return -1
        }
        
        guard !configs.isEmpty else {
            os_log("Model config is empty", log: Live.log, type: .error)
            return -1
        }
        
        guard let handler = nativeHandler else {
            os_log("Native handler not initialized", log: Live.log, type: .error)
            return -1
        }
        
        return nativeLoadModel(handler, configs)
    }
    
    func detect(
        yuv: Data,
        width: Int,
        height: Int,
        orientation: Int,
        faceBox: FaceBox
    ) throws -> Float {
        // RGBA again
        let expectedSize = width * height * 4
        guard yuv.count == expectedSize else {
            throw LiveError.invalidYUVData
        }
        
        guard let handler = nativeHandler else {
            throw LiveError.nativeHandlerNotInitialized
        }
        
        return yuv.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return 0.0 }
            return nativeDetectYUV(
                handler,
                baseAddress,
                Int32(width),
                Int32(height),
                Int32(orientation),
                Int32(faceBox.left),
                Int32(faceBox.top),
                Int32(faceBox.right),
                Int32(faceBox.bottom)
            )
        }
    }
    
    // MARK: - Config Parsing
    
    private func parseConfig() -> [ModelConfig]? {
        guard let url = Bundle.main.url(
            forResource: "config",
            withExtension: "json"   // no subdirectory now
        ) else {
            os_log("Config file not found", log: Live.log, type: .error)
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let configs = try JSONDecoder().decode([ModelConfig].self, from: data)
            return configs
        } catch {
            os_log("Failed to parse config: %@", log: Live.log, type: .error, error.localizedDescription)
            return nil
        }
    }

    
    // MARK: - Native Methods
    
    private func allocate() -> UnsafeMutableRawPointer? {
        return engine_live_allocate()
    }
    
    private func deallocate(_ handler: UnsafeMutableRawPointer) {
        engine_live_deallocate(handler)
    }
    
    private func nativeLoadModel(_ handler: UnsafeMutableRawPointer, _ configs: [ModelConfig]) -> Int32 {
        // Convert Swift ModelConfig array to C array
        var cConfigs = configs.map { config -> CModelConfig in
            CModelConfig(
                scale: config.scale,
                shift_x: config.shiftX,
                shift_y: config.shiftY,
                height: Int32(config.height),
                width: Int32(config.width),
                name: strdup(config.name),
                org_resize: config.orgResize
            )
        }
        
        let result = cConfigs.withUnsafeMutableBufferPointer { buffer in
            engine_live_load_model(handler, buffer.baseAddress, Int32(configs.count))
        }
        
        // Free duplicated strings
        for i in 0..<cConfigs.count {
            if let name = cConfigs[i].name {
                free(UnsafeMutablePointer(mutating: name))
            }
        }
        
        return result
    }
    
    private func nativeDetectYUV(
        _ handler: UnsafeMutableRawPointer,
        _ yuv: UnsafeRawPointer,
        _ width: Int32,
        _ height: Int32,
        _ orientation: Int32,
        _ left: Int32,
        _ top: Int32,
        _ right: Int32,
        _ bottom: Int32
    ) -> Float {
        engine_live_detect_yuv(
            handler,
            yuv,
            width,
            height,
            orientation,
            left,
            top,
            right,
            bottom
        )
    }
}

// MARK: - Error Types

enum LiveError: Error {
    case invalidYUVData
    case nativeHandlerNotInitialized
    case configParseError
    
    var localizedDescription: String {
        switch self {
        case .invalidYUVData:
            return "Invalid frame buffer size (expected RGBA)"
        case .nativeHandlerNotInitialized:
            return "Native handler not initialized"
        case .configParseError:
            return "Failed to parse model configuration"
        }
    }
}

// MARK: - Native C Function Declarations

@_silgen_name("engine_live_allocate")
func engine_live_allocate() -> UnsafeMutableRawPointer?

@_silgen_name("engine_live_deallocate")
func engine_live_deallocate(_ handler: UnsafeMutableRawPointer)

@_silgen_name("engine_live_load_model")
func engine_live_load_model(
    _ handler: UnsafeMutableRawPointer,
    _ configs: UnsafePointer<CModelConfig>?,
    _ configCount: Int32
) -> Int32

@_silgen_name("engine_live_detect_yuv")
func engine_live_detect_yuv(
    _ handler: UnsafeRawPointer,
    _ yuv: UnsafeRawPointer,
    _ width: Int32,
    _ height: Int32,
    _ orientation: Int32,
    _ left: Int32,
    _ top: Int32,
    _ right: Int32,
    _ bottom: Int32
) -> Float
