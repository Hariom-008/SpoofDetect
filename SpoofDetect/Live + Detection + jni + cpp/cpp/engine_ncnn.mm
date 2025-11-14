// engine_ncnn.mm
// iOS NCNN backend without OpenCV

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>

#include "SpoofDetect-Bridging-Header.h"

// NCNN
#include <ncnn/net.h>
#include <ncnn/mat.h>
#include <ncnn/layer.h>

#include <vector>
#include <string>
#include <mutex>
#include <algorithm>

namespace {

//----------------------------------------------------------
// STRUCTS
//----------------------------------------------------------

struct NcnnFaceDetector {
    ncnn::Net net;
    int inputWidth  = 320;
    int inputHeight = 240;
    float scoreThresh = 0.6f;
    float nmsThresh   = 0.4f;
};

struct LiveModelConfig {
    float scale;
    float shift_x;
    float shift_y;
    int   width;
    int   height;
    std::string name;
    bool  org_resize;
};

struct NcnnLiveEngine {
    std::vector<ncnn::Net*> nets;
    std::vector<LiveModelConfig> configs;

    ~NcnnLiveEngine() {
        for (auto* n : nets) {
            delete n;
        }
        nets.clear();
    }
};

//----------------------------------------------------------
// HELPERS
//----------------------------------------------------------

static NSString* bundlePath(NSString *name, NSString *ext, NSString *subdir = nil) {
    NSBundle *bundle = [NSBundle mainBundle];
    if (subdir) {
        return [bundle pathForResource:name ofType:ext inDirectory:subdir];
    } else {
        return [bundle pathForResource:name ofType:ext];
    }
}

static ncnn::Mat cgimage_to_ncnn_rgb(CGImageRef image,
                                     int targetW,
                                     int targetH)
{
    size_t width  = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);

    std::vector<uint8_t> rgba(width * height * 4);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        rgba.data(),
        width,
        height,
        8,
        width * 4,
        colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);

    ncnn::Mat in = ncnn::Mat::from_pixels_resize(
        rgba.data(),
        ncnn::Mat::PIXEL_RGBA2RGB,
        (int)width,
        (int)height,
        targetW,
        targetH
    );

    return in;
}

// TEMP: Treat YUV input as RGBA → convert using PIXEL_RGBA2RGB
static ncnn::Mat yuv420sp_to_ncnn_rgb(const void* rgbaData,
                                      int width,
                                      int height,
                                      int targetW,
                                      int targetH)
{
    const unsigned char* p = (const unsigned char*)rgbaData;

    ncnn::Mat in = ncnn::Mat::from_pixels_resize(
        p,
        ncnn::Mat::PIXEL_RGBA2RGB,
        width,
        height,
        targetW,
        targetH
    );

    return in;
}

static std::vector<int> nms(const std::vector<CFaceBox>& boxes, float nmsThresh) {
    std::vector<int> keep;
    std::vector<bool> removed(boxes.size(), false);

    for (size_t i = 0; i < boxes.size(); ++i) {
        if (removed[i]) continue;
        keep.push_back((int)i);

        float x1 = boxes[i].left;
        float y1 = boxes[i].top;
        float x2 = boxes[i].right;
        float y2 = boxes[i].bottom;
        float area_i = (x2 - x1 + 1) * (y2 - y1 + 1);

        for (size_t j = i + 1; j < boxes.size(); ++j) {
            if (removed[j]) continue;

            float xx1 = std::max(x1, (float)boxes[j].left);
            float yy1 = std::max(y1, (float)boxes[j].top);
            float xx2 = std::min(x2, (float)boxes[j].right);
            float yy2 = std::min(y2, (float)boxes[j].bottom);

            float w = std::max(0.0f, xx2 - xx1 + 1);
            float h = std::max(0.0f, yy2 - yy1 + 1);
            float inter = w * h;
            float area_j = (boxes[j].right - boxes[j].left + 1) *
                           (boxes[j].bottom - boxes[j].top + 1);
            float ovr = inter / (area_i + area_j - inter);

            if (ovr > nmsThresh) {
                removed[j] = true;
            }
        }
    }
    return keep;
}

} // namespace

//--------------------------------------------------------------
// C API
//--------------------------------------------------------------

extern "C" {

//----------------------------------------------------------
// FACE DETECTOR
//----------------------------------------------------------

void* engine_face_detector_allocate(void) {
    auto *det = new NcnnFaceDetector();
    return det;
}

void engine_face_detector_deallocate(void* handler) {
    if (!handler) return;
    auto *det = static_cast<NcnnFaceDetector*>(handler);
    delete det;
}

int engine_face_detector_load_model(void* handler) {
    if (!handler) return -1;
    auto *det = static_cast<NcnnFaceDetector*>(handler);

    det->net.opt.num_threads = 2;
    det->net.opt.use_vulkan_compute = false;

    NSString *paramPath = bundlePath(@"detection", @"param", @"detection");
    NSString *binPath   = bundlePath(@"detection", @"bin",   @"detection");

    if (!paramPath || !binPath) return -1;

    int ret = det->net.load_param(paramPath.UTF8String);
    if (ret != 0) return ret;

    ret = det->net.load_model(binPath.UTF8String);
    return ret;
}

static std::vector<CFaceBox> run_detector(NcnnFaceDetector* det,
                                          const ncnn::Mat& in,
                                          int origW,
                                          int origH)
{
    std::vector<CFaceBox> results;

    ncnn::Extractor ex = det->net.create_extractor();
    ex.set_light_mode(true);
    // no ex.set_num_threads()

    int ret = ex.input("input", in);
    if (ret != 0) return results;

    ncnn::Mat out;
    ret = ex.extract("output", out);
    if (ret != 0) return results;

    for (int i = 0; i < out.h; i++) {
        const float* row = out.row(i);
        float score = row[4];
        if (score < det->scoreThresh) continue;

        CFaceBox fb;
        fb.left   = row[0] * origW;
        fb.top    = row[1] * origH;
        fb.right  = row[2] * origW;
        fb.bottom = row[3] * origH;
        fb.confidence = score;
        results.push_back(fb);
    }

    auto keep = nms(results, det->nmsThresh);
    std::vector<CFaceBox> finalBoxes;
    for (int idx : keep) finalBoxes.push_back(results[idx]);

    return finalBoxes;
}

CFaceBox* engine_face_detector_detect_image(
    void* handler,
    CGImageRef image,
    int* faceCount
) {
    if (!handler || !image) return nullptr;

    auto *det = static_cast<NcnnFaceDetector*>(handler);

    int origW = (int)CGImageGetWidth(image);
    int origH = (int)CGImageGetHeight(image);

    ncnn::Mat in = cgimage_to_ncnn_rgb(image, det->inputWidth, det->inputHeight);
    auto boxes = run_detector(det, in, origW, origH);

    *faceCount = (int)boxes.size();
    if (boxes.empty()) return nullptr;

    CFaceBox* out = (CFaceBox*)malloc(sizeof(CFaceBox) * boxes.size());
    for (size_t i = 0; i < boxes.size(); ++i) out[i] = boxes[i];
    return out;
}

CFaceBox* engine_face_detector_detect_yuv(
    void* handler,
    const void* rgba,
    int width,
    int height,
    int orientation,
    int* faceCount
) {
    if (!handler || !rgba) return nullptr;
    auto *det = static_cast<NcnnFaceDetector*>(handler);

    ncnn::Mat in = yuv420sp_to_ncnn_rgb(rgba, width, height,
                                        det->inputWidth, det->inputHeight);

    auto boxes = run_detector(det, in, width, height);
    *faceCount = (int)boxes.size();
    if (boxes.empty()) return nullptr;

    CFaceBox* out = (CFaceBox*)malloc(sizeof(CFaceBox) * boxes.size());
    for (size_t i = 0; i < boxes.size(); ++i) out[i] = boxes[i];
    return out;
}

void engine_face_detector_free_faces(CFaceBox* faces) {
    if (faces) free(faces);
}

//----------------------------------------------------------
// LIVE ENGINE
//----------------------------------------------------------

void* engine_live_allocate(void) {
    return new NcnnLiveEngine();
}

void engine_live_deallocate(void* handler) {
    if (!handler) return;
    delete static_cast<NcnnLiveEngine*>(handler);
}

int engine_live_load_model(
    void* handler,
    const CModelConfig* configs,
    int configCount
) {
    if (!handler || !configs || configCount <= 0) return -1;
    auto *live = static_cast<NcnnLiveEngine*>(handler);

    live->nets.clear();
    live->configs.clear();
    live->nets.reserve(configCount);
    live->configs.reserve(configCount);

    for (int i = 0; i < configCount; i++) {
        LiveModelConfig cfg;
        cfg.scale      = configs[i].scale;
        cfg.shift_x    = configs[i].shift_x;
        cfg.shift_y    = configs[i].shift_y;
        cfg.width      = configs[i].width;
        cfg.height     = configs[i].height;
        cfg.org_resize = configs[i].org_resize;
        if (configs[i].name) cfg.name = configs[i].name;

        live->configs.push_back(cfg);

        auto* net = new ncnn::Net();
        net->opt.num_threads = 2;
        net->opt.use_vulkan_compute = false;

        NSString* base = [NSString stringWithUTF8String:cfg.name.c_str()];
        NSString* paramPath = bundlePath(base, @"param", @"live");
        NSString* binPath   = bundlePath(base, @"bin",   @"live");

        if (!paramPath || !binPath) {
            delete net;
            return -1;
        }

        int ret = net->load_param(paramPath.UTF8String);
        if (ret != 0) { delete net; return ret; }

        ret = net->load_model(binPath.UTF8String);
        if (ret != 0) { delete net; return ret; }

        live->nets.push_back(net);
    }

    return 0;
}

//------------------------------------------------------------------------------
static float run_live_single(
    ncnn::Net* net,
    const LiveModelConfig& cfg,
    const ncnn::Mat& faceRgb
) {
    ncnn::Mat in = ncnn::Mat::from_pixels_resize(
        (unsigned char*)faceRgb.data,
        ncnn::Mat::PIXEL_RGB,
        faceRgb.w,
        faceRgb.h,
        cfg.width,
        cfg.height
    );

    const float mean_vals[3] = {127.5f, 127.5f, 127.5f};
    const float norm_vals[3] = {1 / 128.f, 1 / 128.f, 1 / 128.f};
    in.substract_mean_normalize(mean_vals, norm_vals);

    ncnn::Extractor ex = net->create_extractor();
    ex.set_light_mode(true);

    ex.input("data", in);

    ncnn::Mat out;
    ex.extract("prob", out);

    if (out.w >= 1) return out[0];
    return 0.0f;
}
//------------------------------------------------------------------------------

float engine_live_detect_yuv(
    void* handler,
    const void* rgba,
    int width,
    int height,
    int orientation,
    int left,
    int top,
    int right,
    int bottom
) {
    if (!handler || !rgba) return 0.0f;
    auto *live = static_cast<NcnnLiveEngine*>(handler);

    ncnn::Mat frame = yuv420sp_to_ncnn_rgb(rgba, width, height, width, height);

    int w = std::max(0, right - left);
    int h = std::max(0, bottom - top);
    if (w <= 0 || h <= 0) return 0.0f;

    left   = std::max(0, left);
    top    = std::max(0, top);
    right  = std::min(width,  right);
    bottom = std::min(height, bottom);

    ncnn::Mat faceRgb(w, h, 3);
    for (int y = 0; y < h; y++) {
        const unsigned char* src =
            (const unsigned char*)frame.channel(0) + (top + y) * width * 3 + left * 3;
        unsigned char* dst =
            (unsigned char*)faceRgb.channel(0) + y * w * 3;

        memcpy(dst, src, w * 3);
    }

    float sum = 0.f;
    for (int i = 0; i < live->nets.size(); i++) {
        sum += run_live_single(live->nets[i], live->configs[i], faceRgb);
    }

    return sum / std::max(1, (int)live->nets.size());
}

} // extern "C"
