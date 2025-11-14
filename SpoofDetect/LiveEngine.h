//
//  LiveEngine.h
//  SpoofDetect
//
//  Created by Hari's Mac on 14.11.2025.
//

#ifndef LiveEngine_h
#define LiveEngine_h
#import <Foundation/Foundation.h>

@interface LiveEngine : NSObject

- (BOOL)loadModels;
- (float)detectNV21:(unsigned char*)nv21
              width:(int)w
             height:(int)h
           rotation:(int)rot
               face:(NSDictionary*)box;

@end


#endif /* LiveEngine_h */
