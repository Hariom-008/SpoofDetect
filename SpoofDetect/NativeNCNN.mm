#import "NativeNCNN.h"
#import <ncnn/net.h>

float runModel(const unsigned char* pixels, int w, int h) {

    // Load model from bundle
    NSString* paramPath = [[NSBundle mainBundle] pathForResource:@"live" ofType:@"param"];
    NSString* binPath   = [[NSBundle mainBundle] pathForResource:@"live" ofType:@"bin"];

    ncnn::Net net;
    net.load_param(paramPath.UTF8String);
    net.load_model(binPath.UTF8String);

    ncnn::Mat input = ncnn::Mat::from_pixels(
        pixels,
        ncnn::Mat::PIXEL_RGBA2RGB,
        w, h
    );

    ncnn::Extractor ex = net.create_extractor();
    ex.set_light_mode(true);

    ex.input("input", input);

    ncnn::Mat out;
    ex.extract("output", out);

    return out[0];
}

@implementation NativeNCNN
+ (float)runNCNN:(unsigned char*)data width:(int)w height:(int)h {
    return runModel(data, w, h);
}
@end
