//
//  FaceBoc.swift
//  SpoofDetect
//
//  Created by Hari's Mac on 14.11.2025.
//

import Foundation
import Foundation

@objc
class FaceBox: NSObject {
    let left: Int
    let top: Int
    let right: Int
    let bottom: Int
    var confidence: Float
    
    init(left: Int, top: Int, right: Int, bottom: Int, confidence: Float) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
        self.confidence = confidence
        super.init()
    }
    
    // Computed properties for convenience
    var width: Int {
        return right - left
    }
    
    var height: Int {
        return bottom - top
    }
    
    var center: (x: Int, y: Int) {
        return (x: (left + right) / 2, y: (top + bottom) / 2)
    }
}
