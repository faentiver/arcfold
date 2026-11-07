// The audio ring between the emulation thread and the real-time render block
// of AVAudioSourceNode (ADR 0005, section 6). C because Swift is not supported
// on audio real-time threads: the render block and everything it calls are
// CA_REALTIME_API, and the implementation turns -Wfunction-effects into an
// error, so an allocation, a lock or an Objective-C message there breaks the
// build.
//
// One producer (the emulation thread writes), one consumer (the render block
// reads). Control functions may be called from any thread.

#ifndef CRENDERERAUDIO_H
#define CRENDERERAUDIO_H

#import <AVFAudio/AVFAudio.h>
#include <stdbool.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

/// Interleaved stereo Int16 frames, one frame stored as a uint32_t so that a
/// left and right sample always travel together.
typedef struct ARCAudioRing ARCAudioRing;

/// What the render function does with the ring.
typedef NS_ENUM(uint32_t, ARCAudioRingState) {
    /// Silence until the target level is buffered; nothing is consumed.
    ARCAudioRingStatePriming = 0,
    /// Frames are played. Running dry counts an underrun and primes again.
    ARCAudioRingStatePlaying = 1,
    /// Silence without consuming or counting, while the emulation is paused.
    ARCAudioRingStateSuspended = 2,
};

/// The ring after a write, for the frame clock of the emulation thread.
typedef struct ARCAudioWriteStatus {
    uint32_t bufferedFrames;
    uint32_t targetFrames;
    /// Playing, and the render block ran within the last 100 ms.
    bool isConsuming;
} ARCAudioWriteStatus;

/// All counters, each read atomically.
typedef struct ARCAudioCounters {
    uint64_t underruns;
    uint64_t underrunFrames;
    uint64_t droppedFrames;
    uint64_t primes;
    uint64_t renderCalls;
    uint32_t largestRequest;
    uint32_t bufferedFrames;
    uint32_t targetFrames;
    ARCAudioRingState state;
} ARCAudioCounters;

/// Frames the render function fades over: in when it starts playing after
/// priming, out when the ring runs dry or the output is suspended while
/// playing. The signal never jumps between silence and its value.
#define ARC_AUDIO_RAMP_FRAMES 64u

/// `capacityFrames` must be a power of two of at least 64. Returns NULL otherwise
/// or if the memory cannot be allocated. The ring starts priming.
ARCAudioRing *_Nullable ARCAudioRingCreate(uint32_t capacityFrames);

/// Frees the ring. Only after the source node that reads it stopped rendering.
void ARCAudioRingDestroy(ARCAudioRing *ring);

/// Producer. Appends up to `frames` interleaved stereo frames; what does not fit
/// is dropped and counted. `hostTime` is the current `mach_absolute_time()`.
/// Returns the frames stored. Allocation- and lock-free, checked by the compiler.
uint32_t ARCAudioRingWrite(ARCAudioRing *ring, const int16_t *interleaved, uint32_t frames,
                           uint64_t hostTime, ARCAudioWriteStatus *status) CA_REALTIME_API;

/// Consumer. Fills `frames` frames of `output` (interleaved stereo Int16, one
/// uint32_t per frame) from the ring or with silence. `isSilence` is set when
/// the whole output is zero.
void ARCAudioRingRender(ARCAudioRing *ring, uint32_t *output, uint32_t frames,
                        bool *isSilence) CA_REALTIME_API;

/// The level priming waits for and the frame clock steers to. Clamped to half
/// the capacity.
void ARCAudioRingSetTargetFrames(ARCAudioRing *ring, uint32_t frames);

/// While suspended, the render function plays silence without consuming or
/// counting. Leaving the suspension primes again.
void ARCAudioRingSetSuspended(ARCAudioRing *ring, bool suspended);

/// Asks the render function to drop everything buffered and prime again at its
/// next call, for example after a pause or an engine restart.
void ARCAudioRingRequestFlush(ARCAudioRing *ring);

void ARCAudioRingReadCounters(const ARCAudioRing *ring, ARCAudioCounters *counters);

/// The same as ARCAudioRingRender, without the real-time attribute, so that
/// Swift tests can drive the consumer side.
void ARCAudioRingRenderForTesting(ARCAudioRing *ring, uint32_t *output, uint32_t frames, bool *isSilence);

/// A source node whose real-time-safe render block reads `ring`. `format` must
/// be interleaved stereo Int16 (the core's format); the node converts to the
/// format it is connected with. Returns nil for any other format. The ring must
/// outlive the node's rendering.
AVAudioSourceNode *_Nullable ARCAudioMakeSourceNode(AVAudioFormat *format, ARCAudioRing *ring);

NS_ASSUME_NONNULL_END

#endif
