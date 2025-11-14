//
//  LiveEngine.m
//  SpoofDetect
//
//  Created by Hari's Mac on 14.11.2025.
//

#import <Foundation/Foundation.h>
#import "LiveEngine.h"
#import <ncnn/net.h>

ncnn::Net live1;
ncnn::Net live2;

@implementation LiveEngine

- (BOOL)loadModels {

    NSString* p1 = [[NSBundle mainBundle] pathForResource:@"model_1" ofType:@"param"];
    NSString* b1 = [[NSBundle mainBundle] pathForResource:@"model_1" ofType:@"bin"];
    NSString* p2 = [[NSBundle mainBundle] pathForResource:@"model_2" ofType:@"param"];
    NSString* b2 = [[NSBundle mainBundle] pathForResource:@"model_2" ofType:@"bin"];

    live1.load_param(p1.UTF8String);
    live1.load_model(b1.UTF8String);

    live2.load_param(p2.UTF8String);
    live2.load_model(b2.UTF8String);

    return YES;
}

float runStage(ncnn::Net &net, ncnn::Mat &crop) {
    ncnn::Extractor ex = net.create_extractor();
    ex.set_light_mode(true);

    ex.input("input", crop);
    ncnn::Mat out;
    ex.extract("output", out);

    return out[0];
}

- (float)detectNV21:(unsigned char*)nv21 width:(int)w height:(int)h rotation:(int)rot face:(NSDictionary*)box {

    int left   = [box[@"left"] intValue];
    int top    = [box[@"top"] intValue];
    int right  = [box[@"right"] intValue];
    int bottom = [box[@"bottom"] intValue];

    int fw = right - left;
    int fh = bottom - top;

    ncnn::Mat in = ncnn::Mat::from_pixels_nv21(nv21, w, h);

    ncnn::Mat faceCrop;
    ncnn::copy_cut_border(in, faceCrop, top, in.h-bottom, left, in.w-right);

    ncnn::Mat resized;
    ncnn::resize_bilinear(faceCrop, resized, 112, 112);

    float s1 = runStage(live1, resized);
    float s2 = runStage(live2, resized);

    float final = (s1 + s2) / 2.0f;

    return final;
}

@end
