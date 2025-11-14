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
    
    static NSString* bundleFile(NSString *relativePath) {
        NSString *base = [[NSBundle mainBundle] resourcePath];
        NSString *full = [base stringByAppendingPathComponent:relativePath];

        if (![[NSFileManager defaultManager] fileExistsAtPath:full]) {
            NSLog(@"[NCNN] bundleFile: missing %@", full);
            return nil;
        }
        return full;
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

        // Files are at bundle root:
        // SpoofDetect.app/detection.param
        // SpoofDetect.app/detection.bin
        NSString *paramPath = bundleFile(@"detection.param");
        NSString *binPath   = bundleFile(@"detection.bin");

        NSLog(@"[NCNN] detection paramPath = %@", paramPath);
        NSLog(@"[NCNN] detection binPath   = %@", binPath);

        if (!paramPath || !binPath) return -1;

        int ret = det->net.load_param(paramPath.UTF8String);
        NSLog(@"[NCNN] load_param ret = %d", ret);
        if (ret != 0) return ret;

        ret = det->net.load_model(binPath.UTF8String);
        NSLog(@"[NCNN] load_model ret = %d", ret);
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

        int ret = 0;

        // Debug: Print available layer names
        NSLog(@"[NCNN] 🔍 Detector model layers:");
        const std::vector<ncnn::Blob>& blobs = det->net.blobs();
        for (size_t i = 0; i < blobs.size(); i++) {
            NSLog(@"[NCNN]   Layer %zu: %s", i, blobs[i].name.c_str());
        }

        // Try common input blob names
        ret = ex.input("data", in);
        if (ret != 0) {
            NSLog(@"[NCNN] 'data' input failed, trying 'input'");
            ret = ex.input("input", in);
        }
        if (ret != 0) {
            NSLog(@"[NCNN] 'input' failed, trying 'in0'");
            ret = ex.input("in0", in);
        }
        if (ret != 0) {
            NSLog(@"[NCNN] ❌ detector: failed to set input blob (ret=%d)", ret);
            return results;
        }
        NSLog(@"[NCNN] ✅ Input blob set successfully");

        // Try common output blob names
        ncnn::Mat out;
        const char* outputNames[] = {
            "output", "prob", "detection_out", "scores", "out0",
            "conv6_2_mbox_conf", "detection_output", "fc7", "conf",
            "loc", "mbox_conf", "mbox_loc"
        };
        
        bool extracted = false;
        const char* successName = nullptr;
        
        for (const char* name : outputNames) {
            ret = ex.extract(name, out);
            if (ret == 0) {
                NSLog(@"[NCNN] ✅ Successfully extracted output blob: %s (dims: w=%d h=%d c=%d)",
                      name, out.w, out.h, out.c);
                extracted = true;
                successName = name;
                break;
            }
        }
        
        if (!extracted) {
            NSLog(@"[NCNN] ❌ detector: failed to extract output blob with any known name");
            NSLog(@"[NCNN] 💡 Check the detection.param file to see the actual layer names");
            return results;
        }

        // Parse detection results
        // Expected format: each row contains [x1, y1, x2, y2, score, ...]
        NSLog(@"[NCNN] 📊 Output blob dimensions: w=%d h=%d c=%d", out.w, out.h, out.c);
        
        // Log first few rows to understand the format
        if (out.h > 0 && out.w >= 6) {
            NSLog(@"[NCNN] 📊 First detection raw values: [%.4f, %.4f, %.4f, %.4f, %.4f, %.4f]",
                  out.row(0)[0], out.row(0)[1], out.row(0)[2],
                  out.row(0)[3], out.row(0)[4], out.row(0)[5]);
        }
        
        for (int i = 0; i < out.h; i++) {
            const float* row = out.row(i);
            
            // DetectionOutput layer format is typically: [class_id, confidence, x1, y1, x2, y2]
            // But your previous code expected: [x1, y1, x2, y2, confidence]
            // Let's check both formats
            
            float score, x1, y1, x2, y2;
            
            if (out.w >= 6) {
                // Format: [class_id, confidence, x1, y1, x2, y2] (SSD format)
                float class_id = row[0];
                score = row[1];
                x1 = row[2];
                y1 = row[3];
                x2 = row[4];
                y2 = row[5];
                
                NSLog(@"[NCNN] Detection %d: class=%.0f score=%.3f box=[%.3f,%.3f,%.3f,%.3f]",
                      i, class_id, score, x1, y1, x2, y2);
            } else {
                // Format: [x1, y1, x2, y2, confidence] (original format)
                x1 = row[0];
                y1 = row[1];
                x2 = row[2];
                y2 = row[3];
                score = row[4];
            }
            
            if (score < det->scoreThresh) continue;

            CFaceBox fb;
            fb.left   = x1 * origW;
            fb.top    = y1 * origH;
            fb.right  = x2 * origW;
            fb.bottom = y2 * origH;
            fb.confidence = score;
            results.push_back(fb);
            
            NSLog(@"[NCNN] 👤 Face detected: score=%.2f box=[%.0f,%.0f,%.0f,%.0f]",
                  score, fb.left, fb.top, fb.right, fb.bottom);
        }

        NSLog(@"[NCNN] 🎯 Total faces before NMS: %zu", results.size());
        auto keep = nms(results, det->nmsThresh);
        std::vector<CFaceBox> finalBoxes;
        for (int idx : keep) finalBoxes.push_back(results[idx]);
        NSLog(@"[NCNN] 🎯 Total faces after NMS: %zu", finalBoxes.size());

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

        NSString* baseName = [NSString stringWithUTF8String:cfg.name.c_str()];

        // Files are at bundle root:
        // SpoofDetect.app/model_1.param, model_1.bin, etc.
        NSString* paramPath = bundleFile([NSString stringWithFormat:@"%@.param", baseName]);
        NSString* binPath   = bundleFile([NSString stringWithFormat:@"%@.bin",   baseName]);

        NSLog(@"[NCNN] live paramPath = %@", paramPath);
        NSLog(@"[NCNN] live binPath   = %@", binPath);

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
    //------------------------------------------------------------------------------
    // Force liveness model input to 80x80, extract from 'softmax' (Silent-Face style)
    //------------------------------------------------------------------------------

    static float run_live_single(
        ncnn::Net* net,
        const LiveModelConfig& cfg,
        const ncnn::Mat& faceRgb
    ) {
        if (!net || faceRgb.empty()) {
            NSLog(@"[NCNN] ❌ Liveness: net or faceRgb is null/empty");
            return 0.0f;
        }

        int srcW = faceRgb.w;
        int srcH = faceRgb.h;

        if (srcW <= 0 || srcH <= 0) {
            NSLog(@"[NCNN] ❌ Liveness: invalid source face size %dx%d", srcW, srcH);
            return 0.0f;
        }

        // MiniFASNet / Silent-Face expect 80x80 input
        const int MODEL_W = 80;
        const int MODEL_H = 80;

        NSLog(@"[NCNN] ▶️ Liveness input crop size: %dx%d, resizing to %dx%d",
              srcW, srcH, MODEL_W, MODEL_H);

        // Resize face crop to 80x80
        ncnn::Mat in = ncnn::Mat::from_pixels_resize(
            (const unsigned char*)faceRgb.data,
            ncnn::Mat::PIXEL_RGB,
            srcW,
            srcH,
            MODEL_W,
            MODEL_H
        );

        // Normalization: (x - 127.5) / 128.0
        const float mean_vals[3] = {127.5f, 127.5f, 127.5f};
        const float norm_vals[3] = {1 / 128.f, 1 / 128.f, 1 / 128.f};
        in.substract_mean_normalize(mean_vals, norm_vals);

        ncnn::Extractor ex = net->create_extractor();
        ex.set_light_mode(true);

        // Input blob is usually "data"
        int ret = ex.input("data", in);
        if (ret != 0) {
            NSLog(@"[NCNN] ❌ Liveness: failed to set input 'data' (ret=%d)", ret);
            return 0.0f;
        }

        ncnn::Mat out;
        const char* usedName = nullptr;

        // Try known output names, including "softmax" (your log literally suggested this)
        const char* outputNames[] = {"prob", "softmax", "output", "fc7"};
        for (const char* name : outputNames) {
            ret = ex.extract(name, out);
            if (ret == 0) {
                usedName = name;
                break;
            }
        }

        if (ret != 0 || out.empty()) {
            NSLog(@"[NCNN] ❌ Liveness: failed to extract output blob (ret=%d)", ret);
            return 0.0f;
        }

        NSLog(@"[NCNN] ✅ Liveness output blob '%s' dims: w=%d h=%d c=%d",
              usedName, out.w, out.h, out.c);

        int len = out.w * out.h * out.c;
        if (len <= 0) {
            NSLog(@"[NCNN] ⚠️ Liveness: output length is 0");
            return 0.0f;
        }

        // Flattened access (ncnn::Mat::operator[])
        float real_score = 0.0f;

        if (len >= 3) {
            float s0 = out[0];
            float s1 = out[1]; // Silent-Face: index 1 is "real"
            float s2 = out[2];

            NSLog(@"[NCNN] 🔴 %s output (softmax style): [c0=%.3f, c1=%.3f, c2=%.3f]",
                  cfg.name.c_str(), s0, s1, s2);

            real_score = s1;
        } else if (len == 2) {
            float s0 = out[0];
            float s1 = out[1];
            // Common pattern: [fake, real]
            NSLog(@"[NCNN] 🔴 %s output (2-class): [fake=%.3f, real=%.3f]",
                  cfg.name.c_str(), s0, s1);
            real_score = s1;
        } else { // len == 1
            float spoof_prob = out[0];
            real_score = 1.0f - spoof_prob;
            NSLog(@"[NCNN] 🔴 %s output (1 value): spoof=%.3f -> real=%.3f",
                  cfg.name.c_str(), spoof_prob, real_score);
        }

        return real_score;
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
        if (!handler || !rgba) {
            NSLog(@"[NCNN] ❌ Liveness: null handler or rgba");
            return 0.0f;
        }
        auto *live = static_cast<NcnnLiveEngine*>(handler);

        // Full frame in RGB (interleaved)
        ncnn::Mat frame = yuv420sp_to_ncnn_rgb(rgba, width, height, width, height);
        if (frame.empty()) {
            NSLog(@"[NCNN] ❌ Liveness: failed to convert frame to RGB");
            return 0.0f;
        }

        int face_w = right - left;
        int face_h = bottom - top;
        
        if (face_w <= 0 || face_h <= 0) {
            NSLog(@"[NCNN] ❌ Liveness: invalid face box w=%d h=%d", face_w, face_h);
            return 0.0f;
        }

        NSLog(@"[NCNN] 🔍 Original face box: [%d,%d,%d,%d] size=%dx%d (frame %dx%d)",
              left, top, right, bottom, face_w, face_h, width, height);

        if (live->nets.empty()) {
            NSLog(@"[NCNN] ❌ No liveness models loaded");
            return 0.0f;
        }

        NSLog(@"[NCNN] Running %zu liveness models...", live->nets.size());
        float sum = 0.f;
        int valid_models = 0;
        
        for (int i = 0; i < (int)live->nets.size(); i++) {
            const LiveModelConfig& cfg = live->configs[i];

            int face_center_x = left + face_w / 2;
            int face_center_y = top + face_h / 2;
            
            int expanded_w = (int)(face_w * cfg.scale);
            int expanded_h = (int)(face_h * cfg.scale);
            
            int shift_x_pixels = (int)(face_w * cfg.shift_x);
            int shift_y_pixels = (int)(face_h * cfg.shift_y);
            
            int crop_left   = face_center_x - expanded_w / 2 + shift_x_pixels;
            int crop_top    = face_center_y - expanded_h / 2 + shift_y_pixels;
            int crop_right  = crop_left + expanded_w;
            int crop_bottom = crop_top + expanded_h;
            
            crop_left   = std::max(0, crop_left);
            crop_top    = std::max(0, crop_top);
            crop_right  = std::min(width,  crop_right);
            crop_bottom = std::min(height, crop_bottom);
            
            int crop_w = crop_right - crop_left;
            int crop_h = crop_bottom - crop_top;
            
            if (crop_w <= 0 || crop_h <= 0) {
                NSLog(@"[NCNN] ⚠️ Model %s: invalid crop after scaling",
                      cfg.name.c_str());
                continue;
            }
            
            NSLog(@"[NCNN] 📐 Model %s (scale=%.2f, shift=(%.2f,%.2f)): crop [%d,%d,%d,%d] size=%dx%d",
                  cfg.name.c_str(), cfg.scale, cfg.shift_x, cfg.shift_y,
                  crop_left, crop_top, crop_right, crop_bottom, crop_w, crop_h);

            // Extract face crop from the full frame (interleaved RGB)
            ncnn::Mat faceRgb(crop_w, crop_h, 3);
            for (int y = 0; y < crop_h; y++) {
                const unsigned char* src =
                    (const unsigned char*)frame.channel(0) + (crop_top + y) * width * 3 + crop_left * 3;
                unsigned char* dst =
                    (unsigned char*)faceRgb.channel(0) + y * crop_w * 3;
                memcpy(dst, src, crop_w * 3);
            }

            // Run single-model liveness with forced 80x80 resize
            float score = run_live_single(live->nets[i], cfg, faceRgb);
            NSLog(@"[NCNN] ✅ Model %s liveness score: %.3f",
                  cfg.name.c_str(), score);

            sum += score;
            valid_models++;
        }

        if (valid_models == 0) {
            NSLog(@"[NCNN] ❌ No valid liveness models processed");
            return 0.0f;
        }

        float avgScore = sum / valid_models;
        NSLog(@"[NCNN] 🎯 Final liveness score: %.3f (avg of %d models)",
              avgScore, valid_models);
        NSLog(@"[NCNN] 💡 Interpretation: %.3f = %s",
              avgScore,
              avgScore > 0.5f ? "REAL FACE ✅" : "FAKE/SPOOF ❌");

        return avgScore;
    }


} // extern "C"
