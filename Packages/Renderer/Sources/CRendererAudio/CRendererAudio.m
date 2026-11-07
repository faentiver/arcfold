// Every function marked CA_REALTIME_API ([[clang::nonblocking]]) and every block
// passed as realtimeSafeRenderBlock is checked by the compiler: a call to
// malloc, free, a lock, NSLog or an Objective-C message inside breaks the build
// (ADR 0005, section 6). Without this pragma clang only warns with
// -Wfunction-effects, which neither the default flags nor -Wall turn on.
#pragma clang diagnostic error "-Wfunction-effects"

#if !__has_feature(objc_arc)
#error "CRendererAudio expects ARC"
#endif

#import "CRendererAudio.h"

#include <mach/mach_time.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

// Fields written by different threads sit on different cache lines.
#define ARC_CACHE_LINE 128

struct ARCAudioRing {
    // Written by the producer.
    _Alignas(ARC_CACHE_LINE) _Atomic(uint64_t) writeIndex;
    _Atomic(uint64_t) droppedFrames;
    // Producer only: when the producer last saw the render call counter move.
    uint64_t producerSeenRenderCalls;
    uint64_t producerLastRenderTime;

    // Written by the consumer (the render function).
    _Alignas(ARC_CACHE_LINE) _Atomic(uint64_t) readIndex;
    _Atomic(uint32_t) state;
    _Atomic(uint64_t) underruns;
    _Atomic(uint64_t) underrunFrames;
    _Atomic(uint64_t) primes;
    _Atomic(uint64_t) renderCalls;
    _Atomic(uint32_t) largestRequest;
    // Consumer only: the last frame played and the fades in progress.
    uint32_t lastFrame;
    uint32_t rampFrame;
    uint32_t rampPosition;
    uint32_t fadeInPosition;

    // Written by the owner (AudioOutput on the main thread).
    _Alignas(ARC_CACHE_LINE) _Atomic(uint32_t) targetFrames;
    _Atomic(bool) suspendRequested;
    _Atomic(bool) flushRequested;

    // Immutable after creation.
    _Alignas(ARC_CACHE_LINE) uint32_t capacity;
    uint32_t mask;
    uint64_t consumingWindow;   // host time units in 100 ms
    uint32_t *frames;
};

ARCAudioRing *ARCAudioRingCreate(uint32_t capacityFrames) {
    if (capacityFrames < 64 || (capacityFrames & (capacityFrames - 1)) != 0) {
        return NULL;
    }
    void *memory = NULL;
    if (posix_memalign(&memory, ARC_CACHE_LINE, sizeof(ARCAudioRing)) != 0) {
        return NULL;
    }
    ARCAudioRing *ring = memory;
    memset(ring, 0, sizeof *ring);
    ring->frames = calloc(capacityFrames, sizeof(uint32_t));
    if (ring->frames == NULL) {
        free(ring);
        return NULL;
    }
    ring->capacity = capacityFrames;
    ring->mask = capacityFrames - 1;
    ring->rampPosition = ARC_AUDIO_RAMP_FRAMES;
    ring->fadeInPosition = ARC_AUDIO_RAMP_FRAMES;

    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    ring->consumingWindow = (uint64_t)100000000 * timebase.denom / timebase.numer;

    atomic_init(&ring->writeIndex, 0);
    atomic_init(&ring->droppedFrames, 0);
    atomic_init(&ring->readIndex, 0);
    atomic_init(&ring->state, ARCAudioRingStatePriming);
    atomic_init(&ring->underruns, 0);
    atomic_init(&ring->underrunFrames, 0);
    // The ring starts out filling up to its target.
    atomic_init(&ring->primes, 1);
    atomic_init(&ring->renderCalls, 0);
    atomic_init(&ring->largestRequest, 0);
    atomic_init(&ring->targetFrames, 0);
    atomic_init(&ring->suspendRequested, false);
    atomic_init(&ring->flushRequested, false);
    return ring;
}

void ARCAudioRingDestroy(ARCAudioRing *ring) {
    free(ring->frames);
    free(ring);
}

uint32_t ARCAudioRingWrite(ARCAudioRing *ring, const int16_t *interleaved, uint32_t frames,
                           uint64_t hostTime, ARCAudioWriteStatus *status) CA_REALTIME_API {
    uint64_t write = atomic_load_explicit(&ring->writeIndex, memory_order_relaxed);
    uint64_t read = atomic_load_explicit(&ring->readIndex, memory_order_acquire);
    uint32_t space = ring->capacity - (uint32_t)(write - read);
    uint32_t count = frames < space ? frames : space;
    if (count < frames) {
        atomic_fetch_add_explicit(&ring->droppedFrames, frames - count, memory_order_relaxed);
    }

    // At most two copies: up to the end of the storage, then from its start.
    uint32_t start = (uint32_t)(write & ring->mask);
    uint32_t first = ring->capacity - start;
    if (first > count) {
        first = count;
    }
    memcpy(ring->frames + start, interleaved, (size_t)first * sizeof(uint32_t));
    memcpy(ring->frames, interleaved + 2 * (size_t)first, (size_t)(count - first) * sizeof(uint32_t));
    atomic_store_explicit(&ring->writeIndex, write + count, memory_order_release);

    uint64_t calls = atomic_load_explicit(&ring->renderCalls, memory_order_relaxed);
    if (calls != ring->producerSeenRenderCalls) {
        ring->producerSeenRenderCalls = calls;
        ring->producerLastRenderTime = hostTime;
    }
    uint32_t state = atomic_load_explicit(&ring->state, memory_order_relaxed);
    read = atomic_load_explicit(&ring->readIndex, memory_order_acquire);
    status->bufferedFrames = (uint32_t)(write + count - read);
    status->targetFrames = atomic_load_explicit(&ring->targetFrames, memory_order_relaxed);
    status->isConsuming = state == ARCAudioRingStatePlaying && calls != 0 &&
                          hostTime - ring->producerLastRenderTime <= ring->consumingWindow;
    return count;
}

// One sample of a packed frame scaled by factor / ARC_AUDIO_RAMP_FRAMES.
static inline uint32_t ARCScaledSample(uint32_t frame, unsigned shift, int32_t factor) CA_REALTIME_API {
    int32_t sample = (int16_t)(uint16_t)(frame >> shift);
    int32_t scaled = sample * factor / (int32_t)ARC_AUDIO_RAMP_FRAMES;
    return (uint32_t)(uint16_t)(int16_t)scaled << shift;
}

// Starts fading out from the last frame played.
static inline void ARCStartRamp(ARCAudioRing *ring) CA_REALTIME_API {
    ring->rampFrame = ring->lastFrame;
    ring->rampPosition = 0;
    ring->lastFrame = 0;
}

// Fills output[from..<frames] with the rest of a running fade-out, then zeros.
// Returns true if any written frame is not zero.
static inline bool ARCFillSilence(ARCAudioRing *ring, uint32_t *output, uint32_t from,
                                  uint32_t frames) CA_REALTIME_API {
    bool audible = false;
    uint32_t index = from;
    while (index < frames && ring->rampPosition < ARC_AUDIO_RAMP_FRAMES) {
        int32_t factor = (int32_t)(ARC_AUDIO_RAMP_FRAMES - 1 - ring->rampPosition);
        uint32_t frame = ARCScaledSample(ring->rampFrame, 0, factor) | ARCScaledSample(ring->rampFrame, 16, factor);
        audible = audible || frame != 0;
        output[index] = frame;
        index += 1;
        ring->rampPosition += 1;
    }
    if (index < frames) {
        memset(output + index, 0, (size_t)(frames - index) * sizeof(uint32_t));
    }
    return audible;
}

// Fades in the first frames played after priming, so that the signal does not
// jump from silence to its value: frame n of the fade keeps (n + 1) / 64.
static inline void ARCFadeIn(ARCAudioRing *ring, uint32_t *output, uint32_t frames) CA_REALTIME_API {
    uint32_t index = 0;
    while (index < frames && ring->fadeInPosition < ARC_AUDIO_RAMP_FRAMES) {
        int32_t factor = (int32_t)(ring->fadeInPosition + 1);
        output[index] = ARCScaledSample(output[index], 0, factor) | ARCScaledSample(output[index], 16, factor);
        index += 1;
        ring->fadeInPosition += 1;
    }
}

static inline void ARCEnterPriming(ARCAudioRing *ring, uint32_t *state) CA_REALTIME_API {
    *state = ARCAudioRingStatePriming;
    atomic_fetch_add_explicit(&ring->primes, 1, memory_order_relaxed);
}

void ARCAudioRingRender(ARCAudioRing *ring, uint32_t *output, uint32_t frames, bool *isSilence) CA_REALTIME_API {
    atomic_fetch_add_explicit(&ring->renderCalls, 1, memory_order_relaxed);
    if (frames > atomic_load_explicit(&ring->largestRequest, memory_order_relaxed)) {
        atomic_store_explicit(&ring->largestRequest, frames, memory_order_relaxed);
    }

    uint32_t state = atomic_load_explicit(&ring->state, memory_order_relaxed);
    if (atomic_load_explicit(&ring->suspendRequested, memory_order_acquire)) {
        if (state == ARCAudioRingStatePlaying) {
            ARCStartRamp(ring);
        }
        state = ARCAudioRingStateSuspended;
    } else if (state == ARCAudioRingStateSuspended) {
        ARCEnterPriming(ring, &state);
    }

    if (atomic_exchange_explicit(&ring->flushRequested, false, memory_order_acq_rel)) {
        // Only the consumer moves the read index, so dropping is a store.
        uint64_t write = atomic_load_explicit(&ring->writeIndex, memory_order_acquire);
        atomic_store_explicit(&ring->readIndex, write, memory_order_release);
        // Priming and suspended stay as they are; playing fills up again.
        if (state == ARCAudioRingStatePlaying) {
            ARCStartRamp(ring);
            ARCEnterPriming(ring, &state);
        }
    }

    uint64_t read = atomic_load_explicit(&ring->readIndex, memory_order_relaxed);
    uint64_t write = atomic_load_explicit(&ring->writeIndex, memory_order_acquire);
    uint64_t available = write - read;

    if (state == ARCAudioRingStatePriming) {
        uint32_t target = atomic_load_explicit(&ring->targetFrames, memory_order_relaxed);
        if (target > 0 && available >= target) {
            state = ARCAudioRingStatePlaying;
            // A fade-out still running belongs to the silence before; the new
            // signal starts now and fades in.
            ring->rampPosition = ARC_AUDIO_RAMP_FRAMES;
            ring->fadeInPosition = 0;
        }
    }

    uint32_t played = 0;
    if (state == ARCAudioRingStatePlaying) {
        played = available < frames ? (uint32_t)available : frames;
        uint32_t start = (uint32_t)(read & ring->mask);
        uint32_t first = ring->capacity - start;
        if (first > played) {
            first = played;
        }
        memcpy(output, ring->frames + start, (size_t)first * sizeof(uint32_t));
        memcpy(output + first, ring->frames, (size_t)(played - first) * sizeof(uint32_t));
        atomic_store_explicit(&ring->readIndex, read + played, memory_order_release);
        // Before lastFrame is taken, so that a fade-out starts from what played.
        ARCFadeIn(ring, output, played);
        if (played > 0) {
            ring->lastFrame = output[played - 1];
        }
        if (played < frames) {
            // Ran dry while playing: an underrun. Fade out from the last value
            // and fill up again before playing on.
            atomic_fetch_add_explicit(&ring->underruns, 1, memory_order_relaxed);
            atomic_fetch_add_explicit(&ring->underrunFrames, frames - played, memory_order_relaxed);
            ARCStartRamp(ring);
            ARCEnterPriming(ring, &state);
        }
    }

    bool audible = ARCFillSilence(ring, output, played, frames);
    *isSilence = played == 0 && !audible;
    atomic_store_explicit(&ring->state, state, memory_order_relaxed);
}

void ARCAudioRingRenderForTesting(ARCAudioRing *ring, uint32_t *output, uint32_t frames, bool *isSilence) {
    ARCAudioRingRender(ring, output, frames, isSilence);
}

void ARCAudioRingSetTargetFrames(ARCAudioRing *ring, uint32_t frames) {
    uint32_t limit = ring->capacity / 2;
    atomic_store_explicit(&ring->targetFrames, frames < limit ? frames : limit, memory_order_relaxed);
}

void ARCAudioRingSetSuspended(ARCAudioRing *ring, bool suspended) {
    atomic_store_explicit(&ring->suspendRequested, suspended, memory_order_release);
}

void ARCAudioRingRequestFlush(ARCAudioRing *ring) {
    atomic_store_explicit(&ring->flushRequested, true, memory_order_release);
}

void ARCAudioRingReadCounters(const ARCAudioRing *ring, ARCAudioCounters *counters) {
    uint64_t read = atomic_load_explicit(&ring->readIndex, memory_order_acquire);
    uint64_t write = atomic_load_explicit(&ring->writeIndex, memory_order_acquire);
    counters->underruns = atomic_load_explicit(&ring->underruns, memory_order_relaxed);
    counters->underrunFrames = atomic_load_explicit(&ring->underrunFrames, memory_order_relaxed);
    counters->droppedFrames = atomic_load_explicit(&ring->droppedFrames, memory_order_relaxed);
    counters->primes = atomic_load_explicit(&ring->primes, memory_order_relaxed);
    counters->renderCalls = atomic_load_explicit(&ring->renderCalls, memory_order_relaxed);
    counters->largestRequest = atomic_load_explicit(&ring->largestRequest, memory_order_relaxed);
    // The two indices are read one after the other; the write index may have
    // moved on, so the difference is clamped to the capacity.
    uint64_t buffered = write >= read ? write - read : 0;
    counters->bufferedFrames = (uint32_t)(buffered < ring->capacity ? buffered : ring->capacity);
    counters->targetFrames = atomic_load_explicit(&ring->targetFrames, memory_order_relaxed);
    counters->state = atomic_load_explicit(&ring->state, memory_order_relaxed);
}

AVAudioSourceNode *ARCAudioMakeSourceNode(AVAudioFormat *format, ARCAudioRing *ring) {
    if (format.commonFormat != AVAudioPCMFormatInt16 || !format.isInterleaved || format.channelCount != 2) {
        return nil;
    }
    return [[AVAudioSourceNode alloc] initWithFormat:format
                             realtimeSafeRenderBlock:^OSStatus(BOOL *isSilence, const AudioTimeStamp *timestamp,
                                                               AVAudioFrameCount frameCount,
                                                               AudioBufferList *outputData) CA_REALTIME_API {
        (void)timestamp;
        // Interleaved format: one buffer, four bytes per frame.
        AudioBuffer *buffer = &outputData->mBuffers[0];
        uint32_t capacity = buffer->mDataByteSize / (uint32_t)sizeof(uint32_t);
        uint32_t frames = frameCount < capacity ? frameCount : capacity;
        bool silence = false;
        ARCAudioRingRender(ring, (uint32_t *)buffer->mData, frames, &silence);
        *isSilence = silence ? YES : NO;
        return noErr;
    }];
}
