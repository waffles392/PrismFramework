#ifndef RMLUI_BRIDGE_H
#define RMLUI_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ─────────────────────────────────────────────────────────────
// Engine lifecycle
// ─────────────────────────────────────────────────────────────

bool rmlui_init(
    void* sdl_gpu_device,
    void* sdl_window
);

void rmlui_shutdown(void);

// ─────────────────────────────────────────────────────────────
// Fonts
// ─────────────────────────────────────────────────────────────

bool rmlui_load_font(
    const char* file_path,
    bool fallback
);

// ─────────────────────────────────────────────────────────────
// Contexts
// ─────────────────────────────────────────────────────────────

void* rmlui_create_context(
    const char* name,
    int width,
    int height
);

void rmlui_destroy_context(
    void* context
);

void rmlui_set_dimensions(
    void* context,
    int width,
    int height
);

void rmlui_update_context(
    void* context
);

// ─────────────────────────────────────────────────────────────
// Documents
// ─────────────────────────────────────────────────────────────

void* rmlui_load_document(
    void* context,
    const char* file_path
);

void* rmlui_load_document_from_memory(
    void* context,
    const char* content
);

void rmlui_show_document(
    void* document
);

void rmlui_close_document(
    void* document
);

// ─────────────────────────────────────────────────────────────
// Elements
// ─────────────────────────────────────────────────────────────

bool rmlui_set_element_inner_rml(
    void* document,
    const char* element_id,
    const char* rml
);

bool rmlui_set_element_property(
    void* document,
    const char* element_id,
    const char* property_name,
    const char* property_value
);

bool rmlui_set_element_attribute(
    void* document,
    const char* element_id,
    const char* attribute_name,
    const char* attribute_value
);

bool rmlui_set_element_class(
    void* document,
    const char* element_id,
    const char* class_name,
    bool enabled
);

// ─────────────────────────────────────────────────────────────
// CSS animation control
// ─────────────────────────────────────────────────────────────

/*
 * Adds class_name to element and forces its RCSS animations
 * to restart on the next RmlUi update.
 *
 * This is the main API used by GameHUD.
 */
bool rmlui_trigger_animation(
    void* document,
    const char* element_id,
    const char* class_name
);

/*
 * Forces existing RCSS animations on this element to restart.
 *
 * Useful when the animation is inherited from an ancestor,
 * for example:
 *
 *   #hud.damage .pip { animation: ...; }
 */
bool rmlui_restart_animations(
    void* document,
    const char* element_id
);

// ─────────────────────────────────────────────────────────────
// Animation events
// ─────────────────────────────────────────────────────────────

typedef void (*RmlUiAnimationEndCallback)(
    const char* element_id,
    const char* property,
    void* user_data
);

bool rmlui_add_animation_end_listener(
    void* document,
    const char* element_id,
    RmlUiAnimationEndCallback callback,
    void* user_data
);

bool rmlui_remove_animation_end_listener(
    void* document,
    const char* element_id
);

typedef void (*RmlUiClickCallback)(void* user_data);
bool rmlui_add_click_listener(void* document, const char* element_id, RmlUiClickCallback callback, void* user_data);
bool rmlui_remove_click_listener(void* document, const char* element_id);

// ─────────────────────────────────────────────────────────────
// Rendering
// ─────────────────────────────────────────────────────────────

void rmlui_begin_frame(
    void* command_buffer,
    void* swapchain_or_target_texture,
    int width,
    int height
);

void rmlui_render_context(
    void* context
);

void rmlui_end_frame(void);

// ─────────────────────────────────────────────────────────────
// Input
// ─────────────────────────────────────────────────────────────

bool rmlui_process_event(
    void* context,
    void* sdl_window,
    void* sdl_event
);

#ifdef __cplusplus
}
#endif

#endif // RMLUI_BRIDGE_H
