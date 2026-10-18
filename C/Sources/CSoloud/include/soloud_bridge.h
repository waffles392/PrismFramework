#ifndef PRISM_SOLOUD_BRIDGE_H
#define PRISM_SOLOUD_BRIDGE_H

// SoLoud's generated C API (<soloud_c.h>) covers every filter the engine binds
// except the EQ, which upstream only offers through the C++ API. It also has no
// generic way to ask a *filter* about its parameters or to delete it without
// knowing its concrete type.
//
// This bridge fills both gaps. It is Prism's own code, covered by the
// BSD 3-Clause License - not part of SoLoud.
//
// parameter indices are SoLoud's: a filter reports its own count (0 is the wet
// mix for most of them) and the EQ's bands are 1-based, 1...8.

#ifdef __cplusplus
extern "C" {
#endif

/// Creates an EQ filter with 8 flat bands. Free it with 'Prism_Filter_destroy'.
void * Prism_EqFilter_create(void);

/// Sets one EQ band's volume. 'aBand' is 1...8; returns SoLoud's result code.
int Prism_EqFilter_setParam(void * aEqFilter, unsigned int aBand, float aVolume);

/// How many parameters the filter exposes.
unsigned int Prism_Filter_getParamCount(void * aFilter);

/// Name of parameter 'aParamIndex', or NULL when it is out of range.
const char * Prism_Filter_getParamName(void * aFilter, unsigned int aParamIndex);

/// Parameter kind: 0 float, 1 int, 2 bool.
unsigned int Prism_Filter_getParamType(void * aFilter, unsigned int aParamIndex);

/// Largest / smallest value parameter 'aParamIndex' accepts.
float Prism_Filter_getParamMax(void * aFilter, unsigned int aParamIndex);
float Prism_Filter_getParamMin(void * aFilter, unsigned int aParamIndex);

/// Deletes any filter created by SoLoud's C API or by this bridge.
void Prism_Filter_destroy(void * aFilter);

#ifdef __cplusplus
}
#endif

#endif
