// Umbrella header of CLibretro; SwiftPM builds the module map from it.
//
// Every header of include/ is listed here on purpose. With an umbrella
// directory instead, a header added later did not reach precompiled modules
// that Xcode had cached before, and the build failed with "cannot find ... in
// scope" until DerivedData was removed.

#include "libretro.h"
#include "arcfold_log.h"
#include "arcfold_signpost.h"
