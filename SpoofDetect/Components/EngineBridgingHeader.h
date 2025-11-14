//
//  Engine-Bridging-Header.h
//
//  Bridging header for exposing C/C++ functions to Swift
//

#ifndef Engine_Bridging_Header_h
#define Engine_Bridging_Header_h

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - FaceBox Structure

typedef struct {
    int left;
    int top;
    int right;
    int bottom;
    float confidence;
} CFaceBox;

// MARK: - ModelConfig Structure

typedef struct {
    float scale;
    float shift_x;
    float shift_y;
    int width;
    int height;
    const char* name;
    bool org_resize;
} CModelConfig;

// MARK: - Face Detector Functions

void* engine_face_detector_allocate(void);
void engine_face_detector_deallocate(void* handler);
int engine_face_detector_load_model(void* handler);

CFaceBox* engine_face_detector_detect_image(
    void* handler,
    CGImageRef image,
    int* faceCount
);

CFaceBox* engine_face_detector_detect_yuv(
    void* handler,
    const void* yuv,
    int width,
    int height,
    int orientation,
    int* faceCount
);

void engine_face_detector_free_faces(CFaceBox* faces);

// MARK: - Liveness Detection Functions

void* engine_live_allocate(void);
void engine_live_deallocate(void* handler);

int engine_live_load_model(
    void* handler,
    const CModelConfig* configs,
    int configCount
);

float engine_live_detect_yuv(
    void* handler,
    const void* yuv,
    int width,
    int height,
    int orientation,
    int left,
    int top,
    int right,
    int bottom
);

#ifdef __cplusplus
}
#endif

#endif /* Engine_Bridging_Header_h */
