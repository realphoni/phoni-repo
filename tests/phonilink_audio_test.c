#include "../tweaks/PhoniLink/PLAudioCore.h"
#include <assert.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <sched.h>

static PLRing concurrent;
enum { StressFrames = 1000000 };
static void *produce(void *unused) {
    (void)unused;
    for (uint32_t i = 0; i < StressFrames;) {
        int16_t sample = (int16_t)(i % 32000);
        if (PLRingWrite(&concurrent, &sample, 1)) ++i; else sched_yield();
    }
    return NULL;
}
int main(void) {
    PLRing *ring = calloc(1, sizeof(*ring)); assert(ring); PLRingInit(ring);
    int16_t input[PLRingCapacity + 20], output[PLRingCapacity + 20];
    for (unsigned i = 0; i < PLRingCapacity + 20; ++i) input[i] = (int16_t)i;
    assert(PLRingRead(ring, output, 1) == 0);
    assert(PLRingWrite(ring, input, PLRingCapacity + 20) == PLRingCapacity);
    assert(PLRingWrite(ring, input, 1) == 0);
    assert(PLRingCount(ring) == PLRingCapacity);
    assert(PLRingRead(ring, output, 4000) == 4000);
    assert(memcmp(input, output, 8000) == 0);
    assert(PLRingWrite(ring, input, 3000) == 3000);
    PLRingKeepNewest(ring, 960);
    assert(PLRingCount(ring) == 960);
    assert(PLRingRead(ring, output, 2000) == 960);
    assert(memcmp(output, input + 2040, 1920) == 0);
    // Monotonic counters must survive uint32 rollover, not just buffer-index wrapping.
    atomic_store(&ring->readIndex, UINT32_MAX - 9); atomic_store(&ring->writeIndex, UINT32_MAX - 9);
    assert(PLRingWrite(ring, input, 40) == 40); assert(PLRingCount(ring) == 40);
    assert(PLRingRead(ring, output, 40) == 40); assert(memcmp(input, output, 80) == 0);
    free(ring);

    uint8_t packet[PLVoicePacketBytes]; uint32_t sequence = 0;
    int16_t pcm[PLPacketFrames], decoded[PLPacketFrames];
    for (unsigned i = 0; i < PLPacketFrames; ++i) pcm[i] = (int16_t)((int)i * 200 - 32000);
    pcm[0] = INT16_MIN; pcm[1] = INT16_MAX; pcm[2] = -1; pcm[3] = 0;
    PLEncodeVoice(packet, 0x12345678, pcm);
    assert(packet[0] == 1 && packet[1] == 0x12 && packet[4] == 0x78);
    assert(packet[5] == 0 && packet[6] == 0x80 && packet[7] == 0xff && packet[8] == 0x7f);
    assert(PLDecodeVoice(packet, sizeof(packet), &sequence, decoded));
    assert(sequence == 0x12345678 && memcmp(pcm, decoded, sizeof(pcm)) == 0);
    assert(!PLDecodeVoice(packet, 0, &sequence, decoded));
    assert(!PLDecodeVoice(packet, sizeof(packet) - 1, &sequence, decoded));
    assert(!PLDecodeVoice(packet, sizeof(packet) + 1, &sequence, decoded));
    packet[0] = 0; assert(!PLDecodeVoice(packet, sizeof(packet), &sequence, decoded));
    assert(PLSequenceIsNewer(1, 0)); assert(!PLSequenceIsNewer(1, 1));
    assert(!PLSequenceIsNewer(5, 6)); assert(PLSequenceIsNewer(0, UINT32_MAX));
    assert(!PLSequenceIsNewer(UINT32_MAX, 0)); assert(!PLSequenceIsNewer(0x80000000, 0));

    PLRingInit(&concurrent); pthread_t thread; assert(pthread_create(&thread, NULL, produce, NULL) == 0);
    for (uint32_t i = 0; i < StressFrames;) {
        int16_t sample;
        if (PLRingRead(&concurrent, &sample, 1)) { assert(sample == (int16_t)(i % 32000)); ++i; } else sched_yield();
    }
    assert(pthread_join(thread, NULL) == 0); assert(PLRingCount(&concurrent) == 0);
    puts("PhoniLink audio tests passed: wire format, malformed frames, loss ordering, ring limits/rollover, 1M concurrent samples");
}
