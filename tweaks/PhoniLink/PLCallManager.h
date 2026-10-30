#import <Foundation/Foundation.h>
#import <MultipeerConnectivity/MultipeerConnectivity.h>

typedef NS_ENUM(NSInteger, PLCallState) { PLCallIdle, PLCallConnecting, PLCallOutgoing, PLCallIncoming, PLCallActive };

@interface PLCallManager : NSObject
@property(nonatomic, copy) void (^changed)(void);
@property(nonatomic, readonly) NSArray<MCPeerID *> *peers;
@property(nonatomic, readonly) NSString *localName;
@property(nonatomic, readonly) NSString *status;
@property(nonatomic, readonly) NSString *remoteName;
@property(nonatomic, readonly) BOOL nearbyEnabled;
@property(nonatomic, readonly) PLCallState state;
@property(nonatomic, readonly) BOOL muted;
@property(nonatomic, readonly) BOOL speaker;
- (void)startNearbyWithName:(NSString *)name;
- (void)stopNearby;
- (void)callPeer:(MCPeerID *)peer;
- (void)answer;
- (void)hangUp;
- (void)toggleMute;
- (void)toggleSpeaker;
@end
