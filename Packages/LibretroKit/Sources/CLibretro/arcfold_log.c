#include "arcfold_log.h"

#include <stdarg.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>

static _Atomic(arcfold_log_sink_t) arcfold_sink = NULL;
static _Atomic(int) arcfold_minimum_level = RETRO_LOG_WARN;
static _Atomic(uint64_t) arcfold_suppressed = 0;

void arcfold_log_set_sink(arcfold_log_sink_t sink) {
    atomic_store_explicit(&arcfold_sink, sink, memory_order_release);
}

void arcfold_log_set_minimum_level(enum retro_log_level level) {
    atomic_store_explicit(&arcfold_minimum_level, (int)level, memory_order_relaxed);
}

enum retro_log_level arcfold_log_minimum_level(void) {
    return (enum retro_log_level)atomic_load_explicit(&arcfold_minimum_level, memory_order_relaxed);
}

uint64_t arcfold_log_suppressed_lines(void) {
    return atomic_load_explicit(&arcfold_suppressed, memory_order_relaxed);
}

// The retro_log_printf_t handed to cores. Below the minimum level it only
// counts, so a core that logs every frame costs one atomic add per line.
static void arcfold_log_printf(enum retro_log_level level, const char *format, ...)
    __attribute__((format(printf, 2, 3)));

static void arcfold_log_printf(enum retro_log_level level, const char *format, ...) {
    if ((int)level < atomic_load_explicit(&arcfold_minimum_level, memory_order_relaxed)) {
        atomic_fetch_add_explicit(&arcfold_suppressed, 1, memory_order_relaxed);
        return;
    }
    arcfold_log_sink_t sink = atomic_load_explicit(&arcfold_sink, memory_order_acquire);
    if (sink == NULL || format == NULL) {
        return;
    }
    char line[1024];
    va_list arguments;
    va_start(arguments, format);
    int written = vsnprintf(line, sizeof(line), format, arguments);
    va_end(arguments);
    if (written < 0) {
        return;
    }
    // Cores end most lines with a newline; the sink gets the bare text.
    size_t length = strnlen(line, sizeof(line));
    while (length > 0 && (line[length - 1] == '\n' || line[length - 1] == '\r')) {
        line[--length] = '\0';
    }
    sink(level, line);
}

bool arcfold_log_fill_interface(struct retro_log_callback *callback) {
    if (callback == NULL) {
        return false;
    }
    callback->log = arcfold_log_printf;
    return true;
}
