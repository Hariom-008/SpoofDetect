//
//  live_Detector_wrapper.cpp
//  SpoofDetect
//
//  Created by Hari's Mac on 14.11.2025.
//

#include "live_Detector_wrapper.hpp"
// live_detector_wrapper.cpp
#include "NativeNCNN.h"  // Your existing NCNN wrapper
#include <cstring>

extern "C" {

void* live_detector_create(void) {
    printf("live_detector_create called\n");
    // TODO: Create your actual LiveDetector instance
    // Example: return new YourLiveDetectorClass();
    return nullptr;  // Replace with actual implementation
}

void live_detector_destroy(void* handle) {
    printf("live_detector_destroy called\n");
    if (handle) {
        // TODO: Delete your LiveDetector instance
        // Example: delete static_cast<YourLiveDetectorClass*>(handle);
    }
}

int32_t live_detector_load_model(void* handle, const char* model_path) {
    printf("live_detector_load_model called with path: %s\n", model_path);
    if (!handle) {
        printf("live_detector_load_model: Invalid handle\n");
        return -1;
    }
    
    // TODO: Load your liveness detection model
    // Example:
    // auto* detector = static_cast<YourLiveDetectorClass*>(handle);
    // return detector->loadModel(model_path);
    
    return 0;  // Replace with actual implementation
}

float live_detector_detect_yuv(
    void* handle,
    const uint8_t* yuv_data,
    int32_t width,
    int32_t height,
    int32_t orientation,
    int32_t left,
    int32_t top,
    int32_t right,
    int32_t bottom
) {
    printf("live_detector_detect_yuv called: %dx%d, face: (%d,%d)-(%d,%d)\n",
           width, height, left, top, right, bottom);
    
    if (!handle || !yuv_data) {
        printf("live_detector_detect_yuv: Invalid parameters\n");
        return 0.0f;
    }
    
    // TODO: Run liveness detection
    // Example:
    // auto* detector = static_cast<YourLiveDetectorClass*>(handle);
    // float score = detector->detect(yuv_data, width, height, orientation, left, top, right, bottom);
    
    float score = 0.0f;  // Replace with actual implementation
    
    printf("live_detector_detect_yuv: Score = %.3f\n", score);
    return score;
}

} // extern "C"
