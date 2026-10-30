#import "PLAudio.h"
#import "PLAudioCore.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

@interface PLAudio () {
@public
    AudioUnit _unit;
    PLRing _capture, _playback;
    _Atomic bool _micMuted;
    bool _primed;
    int16_t _input[4096];
    dispatch_queue_t _sendQueue;
    dispatch_source_t _sendTimer;
    uint32_t _sendSequence, _receiveSequence;
    BOOL _receivedSequence;
}
@end

static OSStatus PLCapture(void *context, AudioUnitRenderActionFlags *flags,
                         const AudioTimeStamp *time, UInt32 bus, UInt32 frames, AudioBufferList *unused) {
    (void)bus; (void)unused;
    PLAudio *audio = (__bridge PLAudio *)context;
    if (frames > 4096) return kAudioUnitErr_TooManyFramesToProcess;
    AudioBufferList input = { .mNumberBuffers = 1, .mBuffers = {{1, frames * 2, audio->_input}} };
    OSStatus status = AudioUnitRender(audio->_unit, flags, time, 1, frames, &input);
    if (status != noErr) return status;
    if (atomic_load_explicit(&audio->_micMuted, memory_order_relaxed)) memset(audio->_input, 0, frames * 2);
    PLRingWrite(&audio->_capture, audio->_input, frames);
    return noErr;
}

static OSStatus PLRender(void *context, AudioUnitRenderActionFlags *flags,
                        const AudioTimeStamp *time, UInt32 bus, UInt32 frames, AudioBufferList *output) {
    (void)flags; (void)time; (void)bus;
    PLAudio *audio = (__bridge PLAudio *)context;
    for (UInt32 i = 0; i < output->mNumberBuffers; ++i)
        if (output->mBuffers[i].mData) memset(output->mBuffers[i].mData, 0, output->mBuffers[i].mDataByteSize);
    if (!output->mNumberBuffers || !output->mBuffers[0].mData || output->mBuffers[0].mDataByteSize < frames * 2) return noErr;
    uint32_t count = PLRingCount(&audio->_playback);
    if (count > 3200) PLRingKeepNewest(&audio->_playback, 960);
    if (!audio->_primed && PLRingCount(&audio->_playback) >= MAX(960u, frames)) audio->_primed = true;
    if (audio->_primed) {
        uint32_t read = PLRingRead(&audio->_playback, output->mBuffers[0].mData, frames);
        if (read < frames) audio->_primed = false;
    }
    return noErr;
}

@implementation PLAudio
- (instancetype)init {
    if ((self = [super init])) {
        PLRingInit(&_capture); PLRingInit(&_playback); atomic_init(&_micMuted, false);
        _sendQueue = dispatch_queue_create("com.phoni.phonilink.voice", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}
- (BOOL)muted { return atomic_load(&_micMuted); }
- (void)setMuted:(BOOL)value { atomic_store(&_micMuted, value); }

- (BOOL)start:(NSError **)error {
    if (_unit) return YES;
    AudioComponentDescription desc = { .componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_VoiceProcessingIO, .componentManufacturer = kAudioUnitManufacturer_Apple };
    AudioComponent component = AudioComponentFindNext(NULL, &desc);
    OSStatus status = component ? AudioComponentInstanceNew(component, &_unit) : kAudio_ParamError;
    UInt32 enabled = 1, maxFrames = 4096;
    AudioStreamBasicDescription format = { .mSampleRate = PLSampleRate, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        .mBytesPerPacket = 2, .mFramesPerPacket = 1, .mBytesPerFrame = 2, .mChannelsPerFrame = 1, .mBitsPerChannel = 16 };
    if (!status) status = AudioUnitSetProperty(_unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enabled, sizeof(enabled));
    if (!status) status = AudioUnitSetProperty(_unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, sizeof(maxFrames));
    if (!status) status = AudioUnitSetProperty(_unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, sizeof(format));
    if (!status) status = AudioUnitSetProperty(_unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof(format));
    AURenderCallbackStruct capture = {PLCapture, (__bridge void *)self}, render = {PLRender, (__bridge void *)self};
    if (!status) status = AudioUnitSetProperty(_unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &capture, sizeof(capture));
    if (!status) status = AudioUnitSetProperty(_unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &render, sizeof(render));
    if (!status) status = AudioUnitInitialize(_unit);
    if (!status) status = AudioOutputUnitStart(_unit);
    if (status) {
        if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Couldn’t start call audio (%d).", (int)status]}];
        [self stop]; return NO;
    }
    // Network work stays off the real-time audio thread; packets are 20 ms of mono PCM.
    _sendTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _sendQueue);
    dispatch_source_set_timer(_sendTimer, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), 20 * NSEC_PER_MSEC, 2 * NSEC_PER_MSEC);
    __weak PLAudio *weak = self;
    dispatch_source_set_event_handler(_sendTimer, ^{
        PLAudio *audio = weak; if (!audio) return;
        if (PLRingCount(&audio->_capture) > 1600) PLRingKeepNewest(&audio->_capture, 640);
        for (unsigned i = 0; i < 3 && PLRingCount(&audio->_capture) >= PLPacketFrames; ++i) {
            int16_t samples[PLPacketFrames]; uint8_t packet[PLVoicePacketBytes];
            PLRingRead(&audio->_capture, samples, PLPacketFrames);
            if (atomic_load(&audio->_micMuted)) memset(samples, 0, sizeof(samples));
            PLEncodeVoice(packet, audio->_sendSequence++, samples);
            if (audio.sendPacket) audio.sendPacket([NSData dataWithBytes:packet length:sizeof(packet)]);
        }
    });
    dispatch_resume(_sendTimer);
    return YES;
}
- (void)receivePacket:(NSData *)packet {
    if (!_unit) return;
    uint32_t sequence; int16_t pcm[PLPacketFrames];
    if (!PLDecodeVoice(packet.bytes, packet.length, &sequence, pcm)) return;
    if (_receivedSequence) {
        if (!PLSequenceIsNewer(sequence, _receiveSequence)) return;
        uint32_t missing = sequence - _receiveSequence - 1;
        // Conceal short losses without building a long queue after a network stall.
        if (missing && missing <= 3) {
            int16_t silence[PLPacketFrames] = {0};
            for (uint32_t i = 0; i < missing; ++i) PLRingWrite(&_playback, silence, PLPacketFrames);
        }
    }
    _receiveSequence = sequence; _receivedSequence = YES;
    PLRingWrite(&_playback, pcm, PLPacketFrames);
}
- (void)stop {
    if (_sendTimer) { dispatch_source_cancel(_sendTimer); _sendTimer = nil; }
    // Drain the timer queue before releasing transport references or the audio buffers.
    dispatch_sync(_sendQueue, ^{});
    self.sendPacket = nil;
    if (_unit) { AudioOutputUnitStop(_unit); AudioUnitUninitialize(_unit); AudioComponentInstanceDispose(_unit); _unit = NULL; }
}
- (void)dealloc { [self stop]; }
@end
