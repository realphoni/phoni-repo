#ifndef PL_AUDIO_CORE_H
#define PL_AUDIO_CORE_H
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

enum { PLSampleRate = 16000, PLPacketFrames = 320, PLRingCapacity = 8192,
       PLVoicePacketBytes = 5 + PLPacketFrames * 2 };

// Single producer / single consumer. Only the consumer may skip old samples.
typedef struct {
    _Atomic uint32_t readIndex;
    _Atomic uint32_t writeIndex;
    int16_t samples[PLRingCapacity];
} PLRing;

static inline void PLRingInit(PLRing *ring) {
    atomic_init(&ring->readIndex, 0);
    atomic_init(&ring->writeIndex, 0);
}

static inline uint32_t PLRingCount(const PLRing *ring) {
    uint32_t read = atomic_load_explicit(&ring->readIndex, memory_order_acquire);
    uint32_t write = atomic_load_explicit(&ring->writeIndex, memory_order_acquire);
    return write - read;
}

static inline uint32_t PLRingWrite(PLRing *ring, const int16_t *input, uint32_t count) {
    uint32_t write = atomic_load_explicit(&ring->writeIndex, memory_order_relaxed);
    uint32_t read = atomic_load_explicit(&ring->readIndex, memory_order_acquire);
    uint32_t room = PLRingCapacity - (write - read);
    if (count > room) count = room;
    for (uint32_t i = 0; i < count; ++i) ring->samples[(write + i) & (PLRingCapacity - 1)] = input[i];
    atomic_store_explicit(&ring->writeIndex, write + count, memory_order_release);
    return count;
}

static inline uint32_t PLRingRead(PLRing *ring, int16_t *output, uint32_t count) {
    uint32_t read = atomic_load_explicit(&ring->readIndex, memory_order_relaxed);
    uint32_t write = atomic_load_explicit(&ring->writeIndex, memory_order_acquire);
    if (count > write - read) count = write - read;
    for (uint32_t i = 0; i < count; ++i) output[i] = ring->samples[(read + i) & (PLRingCapacity - 1)];
    atomic_store_explicit(&ring->readIndex, read + count, memory_order_release);
    return count;
}

static inline void PLRingKeepNewest(PLRing *ring, uint32_t keep) {
    uint32_t write = atomic_load_explicit(&ring->writeIndex, memory_order_acquire);
    uint32_t read = atomic_load_explicit(&ring->readIndex, memory_order_relaxed);
    if (write - read > keep) atomic_store_explicit(&ring->readIndex, write - keep, memory_order_release);
}

// Explicit little-endian PCM, network-order sequence number; no native struct layout on wire.
static inline void PLEncodeVoice(uint8_t *packet, uint32_t sequence, const int16_t *pcm) {
    packet[0] = 1;
    for (unsigned i = 0; i < 4; ++i) packet[1 + i] = (uint8_t)(sequence >> (24 - i * 8));
    for (unsigned i = 0; i < PLPacketFrames; ++i) {
        uint16_t value = (uint16_t)pcm[i];
        packet[5 + 2 * i] = (uint8_t)value;
        packet[6 + 2 * i] = (uint8_t)(value >> 8);
    }
}

static inline bool PLDecodeVoice(const uint8_t *packet, size_t size, uint32_t *sequence, int16_t *pcm) {
    if (size != PLVoicePacketBytes || packet[0] != 1) return false;
    *sequence = ((uint32_t)packet[1] << 24) | ((uint32_t)packet[2] << 16) | ((uint32_t)packet[3] << 8) | packet[4];
    for (unsigned i = 0; i < PLPacketFrames; ++i) pcm[i] = (int16_t)((uint16_t)packet[5 + 2 * i] | ((uint16_t)packet[6 + 2 * i] << 8));
    return true;
}

static inline bool PLSequenceIsNewer(uint32_t next, uint32_t previous) {
    uint32_t distance = next - previous;
    return distance != 0 && distance < 0x80000000u;
}
#endif
