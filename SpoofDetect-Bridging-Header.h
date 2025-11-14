//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import "NativeNCNN.h"

#ifndef SpoofDetect_Bridging_Header_h
#define SpoofDetect_Bridging_Header_h

#import <Foundation/Foundation.h>

typedef struct {
    int32_t left;
    int32_t top;
    int32_t right;
    int32_t bottom;
    float confidence;
} FaceBox;

// Face Detector C API
void* face_detector_create(void);
void face_detector_destroy(void* handle);
int32_t face_detector_load_model(void* handle, const char* model_path);
int32_t face_detector_detect_yuv(void* handle, const uint8_t* yuv_data, int32_t width, int32_t height, int32_t orientation, FaceBox** out_faces, int32_t* out_count);
void face_detector_free_faces(FaceBox* faces);

// Live Detector C API
void* live_detector_create(void);
void live_detector_destroy(void* handle);
int32_t live_detector_load_model(void* handle, const char* model_path);
float live_detector_detect_yuv(void* handle, const uint8_t* yuv_data, int32_t width, int32_t height, int32_t orientation, int32_t left, int32_t top, int32_t right, int32_t bottom);

#endif /* SpoofDetect_Bridging_Header_h */
