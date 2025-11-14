//
//  NativeNCNN.h .h
//  SpoofDetect
//
//  Created by Hari's Mac on 13.11.2025.
//

#ifndef NativeNCNN_h__h
#define NativeNCNN_h__h


#endif /* NativeNCNN_h__h */
#import <Foundation/Foundation.h>

@interface NativeNCNN : NSObject
+ (float)runNCNN:(unsigned char*)data width:(int)w height:(int)h;
@end
