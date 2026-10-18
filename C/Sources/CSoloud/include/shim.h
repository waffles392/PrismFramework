#ifndef PRISM_CSOLOUD_SHIM_H
#define PRISM_CSOLOUD_SHIM_H

// Prism's view of SoLoud, for `import CSoloud` in Swift.
//
// SoLoud is vendored as the 'CSoloudCore' target, and its own generated C API
// is 'soloud_c.h' - a plain C header that lives here rather than in the
// vendored tree so that Swift can import it without dragging in SoLoud's C++
// headers. Everything the engine calls comes from it.
//
// 'soloud_bridge.h' adds the few pieces that API leaves out.

#include "soloud_c.h"
#include "soloud_bridge.h"

#endif
