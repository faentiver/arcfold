#include "arcfold_signpost.h"

void arcfold_signpost_run_begin(os_log_t log, os_signpost_id_t identifier) {
    os_signpost_interval_begin(log, identifier, "retro_run");
}

void arcfold_signpost_run_end(os_log_t log, os_signpost_id_t identifier) {
    os_signpost_interval_end(log, identifier, "retro_run");
}

void arcfold_signpost_resync(os_log_t log) {
    os_signpost_event_emit(log, OS_SIGNPOST_ID_EXCLUSIVE, "resync");
}
