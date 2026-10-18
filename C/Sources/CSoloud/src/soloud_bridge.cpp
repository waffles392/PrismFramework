// Prism's bridge to the parts of SoLoud that its generated C API
// (<soloud_c.h>) does not expose. See soloud_bridge.h.
//
// This file is Prism's own code, covered by the BSD 3-Clause License - not
// part of SoLoud.

#include <soloud.h>
#include <soloud_eqfilter.h>

extern "C" {

void * Prism_EqFilter_create(void) { return (void *)new SoLoud::EqFilter; }
int Prism_EqFilter_setParam(void * aEqFilter, unsigned int aBand, float aVolume) { return (int)((SoLoud::EqFilter *)aEqFilter)->setParam(aBand, aVolume); }

unsigned int Prism_Filter_getParamCount(void * aFilter) { return (unsigned int)((SoLoud::Filter *)aFilter)->getParamCount(); }
const char * Prism_Filter_getParamName(void * aFilter, unsigned int aParamIndex) { return ((SoLoud::Filter *)aFilter)->getParamName(aParamIndex); }
unsigned int Prism_Filter_getParamType(void * aFilter, unsigned int aParamIndex) { return ((SoLoud::Filter *)aFilter)->getParamType(aParamIndex); }

float Prism_Filter_getParamMax(void * aFilter, unsigned int aParamIndex) { return ((SoLoud::Filter *)aFilter)->getParamMax(aParamIndex); }
float Prism_Filter_getParamMin(void * aFilter, unsigned int aParamIndex) { return ((SoLoud::Filter *)aFilter)->getParamMin(aParamIndex); }

void Prism_Filter_destroy(void * aFilter) {
    // SoLoud::Filter has a virtual destructor, so this is correct for every
    // filter regardless of which create function produced it.
    delete (SoLoud::Filter *)aFilter;
}

// extern "C"
}
