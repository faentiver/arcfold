// The log interface Arcfold gives to cores (RETRO_ENVIRONMENT_GET_LOG_INTERFACE).
//
// retro_log_printf_t is variadic, and Swift can neither implement nor call a
// variadic C function. This shim implements it in C: lines below a minimum
// level are only counted, all others are formatted into a stack buffer and
// handed to a non-variadic sink that Swift provides (ADR 0005).

#ifndef ARCFOLD_LOG_H
#define ARCFOLD_LOG_H

#include <stdbool.h>
#include <stdint.h>

#include "libretro.h"

/// Receives one formatted log line without its trailing newline. Called on the
/// thread that logs, only for lines at or above the minimum level.
typedef void (*arcfold_log_sink_t)(enum retro_log_level level, const char *message);

/// Sets where formatted lines go; NULL drops them. Thread-safe.
void arcfold_log_set_sink(arcfold_log_sink_t sink);

/// Lines below `level` are counted but never formatted. The default is
/// RETRO_LOG_WARN, because mGBA logs a line per frame at RETRO_LOG_INFO for
/// many games. Thread-safe.
void arcfold_log_set_minimum_level(enum retro_log_level level);

/// The current minimum level.
enum retro_log_level arcfold_log_minimum_level(void);

/// Lines dropped for being below the minimum level, since the process started.
uint64_t arcfold_log_suppressed_lines(void);

/// Answers RETRO_ENVIRONMENT_GET_LOG_INTERFACE: stores the shim's printf
/// function in `callback`. Returns false if `callback` is NULL.
bool arcfold_log_fill_interface(struct retro_log_callback *callback);

#endif
