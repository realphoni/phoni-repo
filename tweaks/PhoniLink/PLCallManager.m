#import "PLCallManager.h"
#import "PLAudio.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

static NSString *const PLService = @"phonilink";
static void PLMain(void (^block)(void)) { dispatch_async(dispatch_get_main_queue(), block); }

@interface PLCallManager () <MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate>
@property(nonatomic) MCPeerID *identity;
@property(nonatomic) MCSession *session;
@property(nonatomic) MCNearbyServiceAdvertiser *advertiser;
@property(nonatomic) MCNearbyServiceBrowser *browser;
@property(nonatomic) NSMutableArray<MCPeerID *> *found;
@property(nonatomic) MCPeerID *remote;
@property(nonatomic) NSUUID *callID;
@property(nonatomic) PLAudio *audio;
@property(nonatomic) NSTimer *timeout;
@property(nonatomic) NSTimer *ringTimer;
@property(nonatomic) NSTimer *livenessTimer;
@property(nonatomic) NSTimer *durationTimer;
@property(nonatomic) NSDate *startedAt;
@property(nonatomic) NSTimeInterval lastReceived;
@property(nonatomic) BOOL incoming;
@property(nonatomic) BOOL waitingForPermission;
@property(nonatomic) BOOL audioSessionActive;
@property(nonatomic, readwrite) NSString *localName;
@property(nonatomic, readwrite) NSString *status;
@property(nonatomic, readwrite) BOOL nearbyEnabled;
@property(nonatomic, readwrite) PLCallState state;
@property(nonatomic, readwrite) BOOL muted;
@property(nonatomic, readwrite) BOOL speaker;
@end

@implementation PLCallManager
- (instancetype)init {
    if ((self = [super init])) {
        _found = [NSMutableArray array]; _status = @"Ready when you are.";
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(backgrounded:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioInterrupted:) name:AVAudioSessionInterruptionNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioReset:) name:AVAudioSessionMediaServicesWereResetNotification object:nil];
    }
    return self;
}
- (NSArray<MCPeerID *> *)peers { return [self.found copy]; }
- (NSString *)remoteName { return self.remote.displayName ?: @""; }
- (void)notify { if (self.changed) self.changed(); }
- (void)makeSession {
    self.session.delegate = nil; [self.session disconnect];
    self.session = [[MCSession alloc] initWithPeer:self.identity securityIdentity:nil encryptionPreference:MCEncryptionRequired];
    self.session.delegate = self;
}
- (void)startNearbyWithName:(NSString *)name {
    if (self.nearbyEnabled || self.waitingForPermission) return;
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    NSString *clean = [[name componentsSeparatedByCharactersInSet:[NSCharacterSet controlCharacterSet]] componentsJoinedByString:@""];
    clean = [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!clean.length) clean = @"my iPhone";
    while ([clean lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 40)
        clean = [clean substringToIndex:[clean rangeOfComposedCharacterSequenceAtIndex:clean.length - 1].location];
    [[NSUserDefaults standardUserDefaults] setObject:clean forKey:@"phoneName"];
    NSString *tag = [[NSUserDefaults standardUserDefaults] stringForKey:@"phoneTag"];
    if (!tag) { tag = [[[NSUUID UUID] UUIDString] substringToIndex:4]; [[NSUserDefaults standardUserDefaults] setObject:tag forKey:@"phoneTag"]; }
    self.localName = [NSString stringWithFormat:@"%@ · %@", clean, tag];
    self.waitingForPermission = YES; self.status = @"Allow microphone access to make and answer calls."; [self notify];
    __weak PLCallManager *weak = self;
    [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) { PLMain(^{
        PLCallManager *manager = weak; if (!manager || !manager.waitingForPermission) return;
        manager.waitingForPermission = NO;
        if (!granted) { manager.status = @"Microphone access is off. Enable it in Settings > Privacy > Microphone, then try again."; [manager notify]; return; }
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) return;
        manager.identity = [[MCPeerID alloc] initWithDisplayName:manager.localName];
        [manager makeSession];
        manager.advertiser = [[MCNearbyServiceAdvertiser alloc] initWithPeer:manager.identity discoveryInfo:@{@"v": @"1"} serviceType:PLService];
        manager.advertiser.delegate = manager;
        manager.browser = [[MCNearbyServiceBrowser alloc] initWithPeer:manager.identity serviceType:PLService]; manager.browser.delegate = manager;
        manager.nearbyEnabled = YES;
        [manager.advertiser startAdvertisingPeer]; [manager.browser startBrowsingForPeers];
        [UIApplication sharedApplication].idleTimerDisabled = YES;
        manager.status = @"Looking for phones… Open PhoniLink on the other phone too."; [manager notify];
    }); }];
}
- (void)stopNearby {
    self.waitingForPermission = NO;
    [self finish:@"Nearby calling is off." notifyPeer:YES];
    self.nearbyEnabled = NO;
    self.browser.delegate = nil; [self.browser stopBrowsingForPeers]; self.browser = nil;
    self.advertiser.delegate = nil; [self.advertiser stopAdvertisingPeer]; self.advertiser = nil;
    self.session.delegate = nil; [self.session disconnect]; self.session = nil;
    [self.found removeAllObjects]; [UIApplication sharedApplication].idleTimerDisabled = NO;
    [self notify];
}
- (void)deadline:(NSTimeInterval)seconds message:(NSString *)message {
    [self.timeout invalidate];
    __weak PLCallManager *weak = self; NSUUID *call = self.callID;
    self.timeout = [NSTimer scheduledTimerWithTimeInterval:seconds repeats:NO block:^(NSTimer *timer) {
        (void)timer; PLCallManager *manager = weak;
        if (manager && [manager.callID isEqual:call]) [manager finish:message notifyPeer:YES];
    }];
}
- (void)callPeer:(MCPeerID *)peer {
    if (!self.nearbyEnabled || self.state != PLCallIdle || ![self.found containsObject:peer]) return;
    [self makeSession]; self.remote = peer; self.callID = [NSUUID UUID]; self.incoming = NO;
    self.state = PLCallConnecting; self.status = [NSString stringWithFormat:@"Connecting to %@…", peer.displayName];
    NSData *context = [NSJSONSerialization dataWithJSONObject:@{@"v": @1, @"id": self.callID.UUIDString} options:0 error:nil];
    [self.browser invitePeer:peer toSession:self.session withContext:context timeout:12];
    [self deadline:15 message:@"Couldn’t connect. Check that both apps are open and nearby calling is on."]; [self notify];
}
- (BOOL)sendControl:(NSString *)kind {
    if (!self.callID || !self.remote || ![self.session.connectedPeers containsObject:self.remote]) return NO;
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"v": @1, @"id": self.callID.UUIDString, @"kind": kind} options:0 error:nil];
    NSError *error = nil;
    return [self.session sendData:json toPeers:@[self.remote] withMode:MCSessionSendDataReliable error:&error];
}
- (void)beginAudio {
    [self.timeout invalidate]; self.timeout = nil;
    [self.ringTimer invalidate]; self.ringTimer = nil;
    NSError *error = nil; AVAudioSession *session = [AVAudioSession sharedInstance];
    BOOL ok = [session setCategory:AVAudioSessionCategoryPlayAndRecord mode:AVAudioSessionModeVoiceChat
        options:AVAudioSessionCategoryOptionAllowBluetooth error:&error];
    if (ok) { [session setPreferredSampleRate:16000 error:nil]; [session setPreferredIOBufferDuration:0.02 error:nil]; ok = [session setActive:YES error:&error]; }
    self.audioSessionActive = ok;
    PLAudio *audio = [PLAudio new];
    // Capture immutable call references. No UI or mutable manager state on the send queue.
    MCSession *transport = self.session; MCPeerID *remote = self.remote;
    __weak PLCallManager *weak = self; NSUUID *call = self.callID;
    __block unsigned failures = 0;
    audio.sendPacket = ^(NSData *packet) {
        NSError *sendError = nil;
        if ([transport sendData:packet toPeers:@[remote] withMode:MCSessionSendDataUnreliable error:&sendError]) failures = 0;
        else if (++failures == 25) PLMain(^{
            PLCallManager *manager = weak;
            if ([manager.callID isEqual:call]) [manager finish:@"Audio connection lost. Try calling again." notifyPeer:YES];
        });
    };
    if (ok) ok = [audio start:&error];
    if (!ok) { [audio stop]; [self finish:error.localizedDescription ?: @"Couldn’t start audio." notifyPeer:YES]; return; }
    self.audio = audio; self.state = PLCallActive; self.muted = NO; self.speaker = NO;
    self.startedAt = [NSDate date]; self.lastReceived = [NSDate timeIntervalSinceReferenceDate];
    [UIDevice currentDevice].proximityMonitoringEnabled = YES;
    [self sendControl:@"ready"]; [self deadline:10 message:@"The other phone’s audio didn’t start. Try again."];
    self.status = @"Connecting audio…";
    self.livenessTimer = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) {
        (void)timer; PLCallManager *manager = weak;
        if ([NSDate timeIntervalSinceReferenceDate] - manager.lastReceived > 10)
            [manager finish:@"Connection lost. Keep both apps open and try again." notifyPeer:YES];
        else [manager sendControl:@"ping"];
    }];
    self.durationTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        (void)timer; PLCallManager *manager = weak;
        if (!manager || manager.state != PLCallActive || manager.timeout) return;
        NSInteger elapsed = (NSInteger)-manager.startedAt.timeIntervalSinceNow;
        manager.status = [NSString stringWithFormat:@"On call · %ld:%02ld", (long)(elapsed / 60), (long)(elapsed % 60)]; [manager notify];
    }];
    [self notify];
}
- (void)answer {
    if (self.state != PLCallIncoming) return;
    if (![self sendControl:@"answer"]) { [self finish:@"The caller disconnected." notifyPeer:NO]; return; }
    [self beginAudio];
}
- (void)hangUp { [self finish:self.state == PLCallIncoming ? @"Call declined." : @"Call ended." notifyPeer:YES]; }
- (void)finish:(NSString *)message notifyPeer:(BOOL)notifyPeer {
    if (notifyPeer) [self sendControl:@"end"];
    [self.timeout invalidate]; self.timeout = nil;
    [self.ringTimer invalidate]; self.ringTimer = nil;
    [self.livenessTimer invalidate]; self.livenessTimer = nil;
    [self.durationTimer invalidate]; self.durationTimer = nil;
    [self.audio stop]; self.audio = nil;
    if (self.audioSessionActive) [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    self.audioSessionActive = NO;
    [UIDevice currentDevice].proximityMonitoringEnabled = NO;
    self.state = PLCallIdle; self.callID = nil; self.remote = nil; self.muted = NO; self.speaker = NO;
    if (self.identity) [self makeSession];
    self.status = message; [self notify];
}
- (void)toggleMute {
    if (self.state != PLCallActive) return;
    self.muted = !self.muted; self.audio.muted = self.muted; [self notify];
}
- (void)toggleSpeaker {
    if (self.state != PLCallActive) return;
    NSError *error = nil;
    if ([[AVAudioSession sharedInstance] overrideOutputAudioPort:self.speaker ? AVAudioSessionPortOverrideNone : AVAudioSessionPortOverrideSpeaker error:&error]) {
        self.speaker = !self.speaker; [UIDevice currentDevice].proximityMonitoringEnabled = !self.speaker;
    } else self.status = error.localizedDescription;
    [self notify];
}
- (void)backgrounded:(NSNotification *)note {
    (void)note; BOOL wasOn = self.nearbyEnabled; [self stopNearby];
    if (wasOn) { self.status = @"Nearby calling paused when you left the app. Turn it on again to reconnect."; [self notify]; }
}
- (void)audioInterrupted:(NSNotification *)note {
    if ([note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan)
        PLMain(^{ if (self.state != PLCallIdle) [self finish:@"Call interrupted by another audio session." notifyPeer:YES]; });
}
- (void)audioReset:(NSNotification *)note {
    (void)note; PLMain(^{ if (self.state != PLCallIdle) [self finish:@"Audio restarted. Please call again." notifyPeer:YES]; });
}

- (void)browser:(MCNearbyServiceBrowser *)browser foundPeer:(MCPeerID *)peer withDiscoveryInfo:(NSDictionary<NSString *, NSString *> *)info {
    PLMain(^{
        if (browser != self.browser || !self.nearbyEnabled || ![info[@"v"] isEqualToString:@"1"]) return;
        if (![self.found containsObject:peer]) [self.found addObject:peer];
        [self.found sortUsingComparator:^NSComparisonResult(MCPeerID *a, MCPeerID *b) { return [a.displayName localizedCaseInsensitiveCompare:b.displayName]; }];
        if (self.state == PLCallIdle) self.status = @"Tap a phone below to call it."; [self notify];
    });
}
- (void)browser:(MCNearbyServiceBrowser *)browser lostPeer:(MCPeerID *)peer {
    PLMain(^{ if (browser != self.browser) return; [self.found removeObject:peer]; [self notify]; });
}
- (void)browser:(MCNearbyServiceBrowser *)browser didNotStartBrowsingForPeers:(NSError *)error {
    PLMain(^{ if (browser != self.browser) return; [self stopNearby]; self.status = [@"Couldn’t search: " stringByAppendingString:error.localizedDescription]; [self notify]; });
}
- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didNotStartAdvertisingPeer:(NSError *)error {
    PLMain(^{ if (advertiser != self.advertiser) return; [self stopNearby]; self.status = [@"Couldn’t advertise: " stringByAppendingString:error.localizedDescription]; [self notify]; });
}
- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didReceiveInvitationFromPeer:(MCPeerID *)peer withContext:(NSData *)context invitationHandler:(void (^)(BOOL, MCSession *))handler {
    PLMain(^{
        id json = context.length <= 256 ? [NSJSONSerialization JSONObjectWithData:context ?: [NSData data] options:0 error:nil] : nil;
        id identifier = [json isKindOfClass:[NSDictionary class]] ? json[@"id"] : nil;
        NSUUID *call = [identifier isKindOfClass:[NSString class]] ? [[NSUUID alloc] initWithUUIDString:identifier] : nil;
        if (advertiser != self.advertiser || !self.nearbyEnabled || self.state != PLCallIdle || !call ||
            ![json[@"v"] isEqual:@1] || [UIApplication sharedApplication].applicationState != UIApplicationStateActive) { handler(NO, nil); return; }
        [self makeSession]; self.remote = peer; self.callID = call; self.incoming = YES; self.state = PLCallConnecting;
        self.status = [NSString stringWithFormat:@"Connecting to %@…", peer.displayName];
        // Accept the encrypted transport only. No microphone until the user taps Answer.
        handler(YES, self.session); [self deadline:15 message:@"The caller couldn’t connect."]; [self notify];
    });
}
- (void)session:(MCSession *)session peer:(MCPeerID *)peer didChangeState:(MCSessionState)state {
    PLMain(^{
        if (session != self.session || ![peer isEqual:self.remote]) return;
        if (state == MCSessionStateNotConnected) { [self finish:@"The other phone disconnected." notifyPeer:NO]; return; }
        if (state != MCSessionStateConnected || self.state != PLCallConnecting) return;
        [self deadline:30 message:self.incoming ? @"Missed call." : @"No answer."];
        if (self.incoming) {
            self.state = PLCallIncoming; self.status = [NSString stringWithFormat:@"%@ is calling…", peer.displayName];
            AudioServicesPlayAlertSound(kSystemSoundID_Vibrate); AudioServicesPlaySystemSound(1005);
            __weak PLCallManager *weak = self;
            self.ringTimer = [NSTimer scheduledTimerWithTimeInterval:3 repeats:YES block:^(NSTimer *timer) {
                (void)timer; if (weak.state == PLCallIncoming) { AudioServicesPlayAlertSound(kSystemSoundID_Vibrate); AudioServicesPlaySystemSound(1005); }
            }];
            [self sendControl:@"ring"];
        } else { self.state = PLCallOutgoing; self.status = [NSString stringWithFormat:@"Calling %@…", peer.displayName]; }
        [self notify];
    });
}
- (void)session:(MCSession *)session didReceiveData:(NSData *)data fromPeer:(MCPeerID *)peer {
    // MCSession delivers on a private queue. State and playback production stay on main.
    PLMain(^{
        if (session != self.session || ![peer isEqual:self.remote] || !self.callID || !data.length) return;
        if (((const uint8_t *)data.bytes)[0] == 1) {
            if (self.state == PLCallActive && data.length == 645) {
                self.lastReceived = [NSDate timeIntervalSinceReferenceDate]; [self.audio receivePacket:data];
                if (self.timeout) { [self.timeout invalidate]; self.timeout = nil; self.status = @"On call · 0:00"; [self notify]; }
            }
            return;
        }
        if (data.length > 512) return;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]] || ![json[@"v"] isEqual:@1] || ![json[@"id"] isEqual:self.callID.UUIDString]) return;
        NSString *kind = json[@"kind"]; if (![kind isKindOfClass:[NSString class]]) return;
        if ([kind isEqualToString:@"end"]) [self finish:self.state == PLCallOutgoing ? @"Call declined or ended." : @"Call ended." notifyPeer:NO];
        else if ([kind isEqualToString:@"answer"] && !self.incoming && (self.state == PLCallOutgoing || self.state == PLCallConnecting)) [self beginAudio];
        else if ([kind isEqualToString:@"ring"] && !self.incoming && self.state == PLCallOutgoing) { self.status = @"Ringing…"; [self notify]; }
        else if (([kind isEqualToString:@"ready"] || [kind isEqualToString:@"ping"]) && self.state == PLCallActive) {
            self.lastReceived = [NSDate timeIntervalSinceReferenceDate];
        }
    });
}
- (void)session:(MCSession *)session didReceiveStream:(NSInputStream *)stream withName:(NSString *)name fromPeer:(MCPeerID *)peer {
    (void)session; (void)name; (void)peer; [stream close];
}
- (void)session:(MCSession *)session didStartReceivingResourceWithName:(NSString *)name fromPeer:(MCPeerID *)peer withProgress:(NSProgress *)progress {
    (void)session; (void)name; (void)peer; [progress cancel];
}
- (void)session:(MCSession *)session didFinishReceivingResourceWithName:(NSString *)name fromPeer:(MCPeerID *)peer atURL:(NSURL *)url withError:(NSError *)error {
    (void)session; (void)name; (void)peer; (void)url; (void)error;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end
