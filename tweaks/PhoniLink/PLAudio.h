#import <Foundation/Foundation.h>

@interface PLAudio : NSObject
@property(nonatomic, copy) void (^sendPacket)(NSData *packet);
@property(nonatomic) BOOL muted;
- (BOOL)start:(NSError **)error;
- (void)stop;
// Call on the main queue. The audio callback is the only playback consumer.
- (void)receivePacket:(NSData *)packet;
@end
