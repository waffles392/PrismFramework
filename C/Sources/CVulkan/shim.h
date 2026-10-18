#ifndef PRISM_CVULKAN_SHIM_H
#define PRISM_CVULKAN_SHIM_H

// Prism never calls the Vulkan API itself: it only needs the structs and
// enums to build the feature list handed to SDL_GPU. dropping the function
// prototypes keeps the imported module small
#define VK_NO_PROTOTYPES

#include <vulkan/vulkan_core.h>

#endif
