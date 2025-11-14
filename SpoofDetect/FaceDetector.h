//
//  FaceDetector.h
//  SpoofDetect
//
//  Created by Hari's Mac on 14.11.2025.
//

#ifndef FaceDetector_h
#define FaceDetector_h

#import <Foundation/Foundation.h>

@interface FaceDetector : NSObject

- (BOOL)loadModel;
- (NSArray*)detectNV21:(unsigned char*)nv21
                 width:(int)w
                height:(int)h
              rotation:(int)rot;

@end

#endif /* FaceDetector_h */
