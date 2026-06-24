#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface GestureAugmentor : NSObject

+ (nullable CGEventRef)augmentEvent:(CGEventRef)event;

@end

NS_ASSUME_NONNULL_END
