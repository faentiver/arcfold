// Signposts of the emulation thread for Instruments (ADR 0005, section 3).
//
// Emitted from C because Swift's OSSignposter allocates an interval state and
// a message buffer for every interval; once per frame that is a heap
// allocation the emulation thread must not make. The os_signpost macros check
// whether signposts are enabled and write into a stack buffer.

#ifndef ARCFOLD_SIGNPOST_H
#define ARCFOLD_SIGNPOST_H

#include <os/log.h>
#include <os/signpost.h>

/// Begins the interval "retro_run" with `identifier`.
void arcfold_signpost_run_begin(os_log_t log, os_signpost_id_t identifier);

/// Ends the interval "retro_run" with `identifier`.
void arcfold_signpost_run_end(os_log_t log, os_signpost_id_t identifier);

/// The event "resync": the frame clock restarted its schedule from now.
void arcfold_signpost_resync(os_log_t log);

#endif
