//
//  ModelConfig.swift
//  SpoofDetect
//
//  Created by Hari's Mac on 14.11.2025.
//

import Foundation
import Foundation

@objc
class ModelConfig: NSObject, Codable {
    var scale: Float
    var shiftX: Float
    var shiftY: Float
    var height: Int
    var width: Int
    var name: String
    var orgResize: Bool
    
    init(
        scale: Float = 0.0,
        shiftX: Float = 0.0,
        shiftY: Float = 0.0,
        height: Int = 0,
        width: Int = 0,
        name: String = "",
        orgResize: Bool = false
    ) {
        self.scale = scale
        self.shiftX = shiftX
        self.shiftY = shiftY
        self.height = height
        self.width = width
        self.name = name
        self.orgResize = orgResize
        super.init()
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case scale
        case shiftX = "shift_x"
        case shiftY = "shift_y"
        case height
        case width
        case name
        case orgResize = "org_resize"
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scale = try container.decode(Float.self, forKey: .scale)
        shiftX = try container.decode(Float.self, forKey: .shiftX)
        shiftY = try container.decode(Float.self, forKey: .shiftY)
        height = try container.decode(Int.self, forKey: .height)
        width = try container.decode(Int.self, forKey: .width)
        name = try container.decode(String.self, forKey: .name)
        orgResize = try container.decode(Bool.self, forKey: .orgResize)
        super.init()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scale, forKey: .scale)
        try container.encode(shiftX, forKey: .shiftX)
        try container.encode(shiftY, forKey: .shiftY)
        try container.encode(height, forKey: .height)
        try container.encode(width, forKey: .width)
        try container.encode(name, forKey: .name)
        try container.encode(orgResize, forKey: .orgResize)
    }
}

// C-compatible ModelConfig structure for passing to native code
struct CModelConfig {
    var scale: Float
    var shift_x: Float
    var shift_y: Float
    var height: Int32
    var width: Int32
    var name: UnsafePointer<CChar>?
    var org_resize: Bool
}

extension ModelConfig {
    func toCModelConfig() -> CModelConfig {
        return CModelConfig(
            scale: scale,
            shift_x: shiftX,
            shift_y: shiftY,
            height: Int32(height),
            width: Int32(width),
            name: name.withCString { $0 },
            org_resize: orgResize
        )
    }
}
