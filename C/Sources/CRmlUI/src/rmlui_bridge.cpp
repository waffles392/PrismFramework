#include "rmlui_bridge.h"

#include "RmlUi_Renderer_SDL_GPU.h"
#include "RmlUi_Platform_SDL.h"

#include <RmlUi/Core.h>
#include <RmlUi/Core/Element.h>
#include <RmlUi/Core/ElementDocument.h>
#include <RmlUi/Core/Event.h>
#include <RmlUi/Core/EventListener.h>

#include <SDL3/SDL.h>

#include <algorithm>
#include <memory>
#include <string>
#include <vector>

// ─────────────────────────────────────────────────────────────
// Globals
// ─────────────────────────────────────────────────────────────

static std::unique_ptr<RenderInterface_SDL_GPU> g_renderer;
static std::unique_ptr<SystemInterface_SDL> g_system;

// ─────────────────────────────────────────────────────────────
// Animation event bridge
// ─────────────────────────────────────────────────────────────

class AnimationEndListener final : public Rml::EventListener {
public:
    AnimationEndListener(
        RmlUiAnimationEndCallback callback,
        void* user_data
    )
        : callback_(callback)
        , user_data_(user_data)
    {
    }

    void ProcessEvent(Rml::Event& event) override
    {
        if (!callback_) {
            return;
        }

        Rml::Element* element = event.GetCurrentElement();

        const Rml::String element_id =
            element ? element->GetId() : Rml::String();

        const Rml::String property =
            event.GetParameter<Rml::String>(
                "property",
                ""
            );

        callback_(
            element_id.c_str(),
            property.c_str(),
            user_data_
        );
    }

private:
    RmlUiAnimationEndCallback callback_ = nullptr;
    void* user_data_ = nullptr;
};

struct AnimationListenerRegistration {
    Rml::Context* context = nullptr;
    Rml::ElementDocument* document = nullptr;
    Rml::Element* element = nullptr;

    std::unique_ptr<AnimationEndListener> listener;

    RmlUiAnimationEndCallback callback = nullptr;
    void* user_data = nullptr;
};

static std::vector<
    std::unique_ptr<AnimationListenerRegistration>
> g_animation_listeners;

class ClickListener final : public Rml::EventListener {
public:
    ClickListener(RmlUiClickCallback callback, void* user_data) : callback_(callback), user_data_(user_data) {}
    void ProcessEvent(Rml::Event&) override { if (callback_) callback_(user_data_); }
private:
    RmlUiClickCallback callback_;
    void* user_data_;
};

struct ClickRegistration {
    Rml::ElementDocument* document;
    Rml::Element* element;
    std::unique_ptr<ClickListener> listener;
};
static std::vector<std::unique_ptr<ClickRegistration>> g_click_listeners;

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

static AnimationListenerRegistration*
find_animation_listener(
    Rml::ElementDocument* document,
    const char* element_id
) {
    if (!document || !element_id) {
        return nullptr;
    }

    for (auto& registration : g_animation_listeners) {
        if (registration->document == document &&
            registration->element &&
            registration->element->GetId() == element_id) {
            return registration.get();
        }
    }

    return nullptr;
}

static void remove_animation_listener_at(
    size_t index
) {
    if (index >= g_animation_listeners.size()) {
        return;
    }

    auto& registration =
        g_animation_listeners[index];

    if (registration->element &&
        registration->listener) {

        registration->element->RemoveEventListener(
            Rml::EventId::Animationend,
            registration->listener.get()
        );
    }

    g_animation_listeners.erase(
        g_animation_listeners.begin() +
        static_cast<std::ptrdiff_t>(index)
    );
}

static bool remove_animation_listener(
    Rml::ElementDocument* document,
    const char* element_id
) {
    if (!document || !element_id) {
        return false;
    }

    for (size_t i = 0; i < g_animation_listeners.size(); ++i) {
        const auto& registration =
            g_animation_listeners[i];

        if (registration->document == document &&
            registration->element &&
            registration->element->GetId() == element_id) {

            remove_animation_listener_at(i);
            return true;
        }
    }

    return false;
}

static void remove_animation_listeners_for_document(
    Rml::ElementDocument* document
) {
    if (!document) {
        return;
    }

    for (size_t i = g_animation_listeners.size();
         i > 0;
         --i) {

        const size_t index = i - 1;

        if (g_animation_listeners[index]->document == document) {
            remove_animation_listener_at(index);
        }
    }
}

static void remove_animation_listeners_for_context(
    Rml::Context* context
) {
    if (!context) {
        return;
    }

    for (size_t i = g_animation_listeners.size();
         i > 0;
         --i) {

        const size_t index = i - 1;

        if (g_animation_listeners[index]->context == context) {
            remove_animation_listener_at(index);
        }
    }
}

/*
 * RmlUi keeps CSS animation definitions in computed style.
 *
 * SetProperty("animation", "none") + RemoveProperty("animation")
 * marks the animation property dirty without leaving an inline
 * animation override behind.
 *
 * On Context::Update(), RmlUi sees dirty_animation and rebuilds
 * the animations from the RCSS stylesheet.
 */
static bool restart_css_animations(
    Rml::Element* element
) {
    if (!element) {
        return false;
    }

    if (!element->SetProperty(
            "animation",
            "none")) {
        return false;
    }

    element->RemoveProperty(
        "animation"
    );

    return true;
}

// ─────────────────────────────────────────────────────────────
// C API
// ─────────────────────────────────────────────────────────────

extern "C" {

// ─────────────────────────────────────────────────────────────
// Engine lifecycle
// ─────────────────────────────────────────────────────────────

bool rmlui_init(
    void* sdl_gpu_device,
    void* sdl_window
) {
    if (!sdl_gpu_device ||
        !sdl_window) {
        return false;
    }

    auto* device =
        static_cast<SDL_GPUDevice*>(
            sdl_gpu_device
        );

    auto* window =
        static_cast<SDL_Window*>(
            sdl_window
        );

    g_renderer =
        std::make_unique<RenderInterface_SDL_GPU>(
            device,
            window
        );

    g_system =
        std::make_unique<SystemInterface_SDL>(
            window
        );

    Rml::SetRenderInterface(
        g_renderer.get()
    );

    Rml::SetSystemInterface(
        g_system.get()
    );

    return Rml::Initialise();
}

void rmlui_shutdown(
    void
) {
    // Detach our listeners before the RmlUi objects disappear.
    g_animation_listeners.clear();

    Rml::Shutdown();

    if (g_renderer) {
        g_renderer->Shutdown();
        g_renderer.reset();
    }

    g_system.reset();
}

// ─────────────────────────────────────────────────────────────
// Fonts
// ─────────────────────────────────────────────────────────────

bool rmlui_load_font(
    const char* file_path,
    bool fallback
) {
    if (!file_path) {
        return false;
    }

    return Rml::LoadFontFace(
        file_path,
        fallback
    );
}

// ─────────────────────────────────────────────────────────────
// Contexts
// ─────────────────────────────────────────────────────────────

void* rmlui_create_context(
    const char* name,
    int width,
    int height
) {
    if (!name) {
        return nullptr;
    }

    Rml::Context* context =
        Rml::CreateContext(
            name,
            Rml::Vector2i(
                width,
                height
            )
        );

    return context;
}

void rmlui_destroy_context(
    void* context
) {
    if (!context) {
        return;
    }

    auto* ctx =
        static_cast<Rml::Context*>(
            context
        );

    remove_animation_listeners_for_context(
        ctx
    );

    Rml::RemoveContext(
        ctx->GetName()
    );
}

void rmlui_set_dimensions(
    void* context,
    int width,
    int height
) {
    if (!context) {
        return;
    }

    auto* ctx =
        static_cast<Rml::Context*>(
            context
        );

    ctx->SetDimensions(
        Rml::Vector2i(
            width,
            height
        )
    );
}

void rmlui_update_context(
    void* context
) {
    if (!context) {
        return;
    }

    auto* ctx =
        static_cast<Rml::Context*>(
            context
        );

    ctx->Update();
}

// ─────────────────────────────────────────────────────────────
// Documents
// ─────────────────────────────────────────────────────────────

void* rmlui_load_document(
    void* context,
    const char* file_path
) {
    if (!context ||
        !file_path) {
        return nullptr;
    }

    auto* ctx =
        static_cast<Rml::Context*>(
            context
        );

    return ctx->LoadDocument(
        file_path
    );
}

void* rmlui_load_document_from_memory(
    void* context,
    const char* content
) {
    if (!context ||
        !content) {
        return nullptr;
    }

    auto* ctx =
        static_cast<Rml::Context*>(
            context
        );

    return ctx->LoadDocumentFromMemory(
        content
    );
}

void rmlui_show_document(
    void* document
) {
    if (!document) {
        return;
    }

    auto* doc =
        static_cast<Rml::ElementDocument*>(
            document
        );

    doc->Show();
}

void rmlui_close_document(
    void* document
) {
    if (!document) {
        return;
    }

    auto* doc =
        static_cast<Rml::ElementDocument*>(
            document
        );

    remove_animation_listeners_for_document(
        doc
    );

    doc->Close();
}

// ─────────────────────────────────────────────────────────────
// Elements
// ─────────────────────────────────────────────────────────────

bool rmlui_set_element_inner_rml(
    void* document,
    const char* element_id,
    const char* rml
) {
    if (!document ||
        !element_id ||
        !rml) {
        return false;
    }

    auto* doc =
        static_cast<Rml::ElementDocument*>(
            document
        );

    Rml::Element* element =
        doc->GetElementById(
            element_id
        );

    if (!element) {
        return false;
    }

    element->SetInnerRML(
        rml
    );

    return true;
}

bool rmlui_set_element_property(
    void* document,
    const char* element_id,
    const char* property_name,
    const char* property_value
) {
    if (!document ||
        !element_id ||
        !property_name ||
        !property_value) {
        return false;
    }

    auto* doc =
        static_cast<Rml::ElementDocument*>(
            document
        );

    Rml::Element* element =
        doc->GetElementById(
            element_id
        );

    if (!element) {
        return false;
    }

    return element->SetProperty(
        property_name,
        property_value
    );
}

bool rmlui_set_element_attribute(
    void* document,
    const char* element_id,
    const char* attribute_name,
    const char* attribute_value
) {
    if (!document ||
        !element_id ||
        !attribute_name ||
        !attribute_value) {
        return false;
    }

    auto* doc =
        static_cast<Rml::ElementDocument*>(
            document
        );

    Rml::Element* element =
        doc->GetElementById(
            element_id
        );

    if (!element) {
        return false;
    }

    element->SetAttribute(
        attribute_name,
        attribute_value
    );

    return true;
}

bool rmlui_set_element_class(
    void* document,
    const char* element_id,
    const char* class_name,
    bool enabled
) {
    if (!document ||
        !element_id ||
        !class_name) {
        return false;
    }

    auto* doc =
        static_cast<Rml::ElementDocument*>(
            document
        );

    Rml::Element* element =
        doc->GetElementById(
            element_id
        );

    if (!element) {
        return false;
    }

    element->SetClass(
        class_name,
        enabled
    );

    return true;
}

// ─────────────────────────────────────────────────────────────
// Animation control
// ─────────────────────────────────────────────────────────────

bool rmlui_trigger_animation(
    void* document,
    const char* element_id,
    const char* class_name
) {
    if (!document ||
        !element_id ||
        !class_name) {
        return false;
    }

    auto* doc =
        static_cast<Rml::ElementDocument*>(
            document
        );

    Rml::Element* element =
        doc->GetElementById(
            element_id
        );

    if (!element) {
        return false;
    }

    // The trigger class is persistent until GameHUD removes it
    // through animationend. If it is already present, this call
    // still restarts the animation.
    element->SetClass(
        class_name,
        true
    );

    return restart_css_animations(
        element
    );
}

bool rmlui_restart_animations(
    void* document,
    const char* element_id
) {
    if (!document ||
        !element_id) {
        return false;
    }

    auto* doc =
        static_cast<Rml::ElementDocument*>(
            document
        );

    Rml::Element* element =
        doc->GetElementById(
            element_id
        );

    if (!element) {
        return false;
    }

    return restart_css_animations(
        element
    );
}

// ─────────────────────────────────────────────────────────────
// Animation events
// ─────────────────────────────────────────────────────────────

bool rmlui_add_animation_end_listener(
    void* document,
    const char* element_id,
    RmlUiAnimationEndCallback callback,
    void* user_data
) {
    if (!document ||
        !element_id ||
        !callback) {
        return false;
    }

    auto* doc =
        static_cast<Rml::ElementDocument*>(
            document
        );

    Rml::Element* element =
        doc->GetElementById(
            element_id
        );

    if (!element) {
        return false;
    }

    // One listener per element.
    remove_animation_listener(
        doc,
        element_id
    );

    auto registration =
        std::make_unique<
            AnimationListenerRegistration
        >();

    registration->context =
        doc->GetContext();

    registration->document =
        doc;

    registration->element =
        element;

    registration->callback =
        callback;

    registration->user_data =
        user_data;

    registration->listener =
        std::make_unique<
            AnimationEndListener
        >(
            callback,
            user_data
        );

    element->AddEventListener(
        Rml::EventId::Animationend,
        registration->listener.get()
    );

    g_animation_listeners.push_back(
        std::move(registration)
    );

    return true;
}

bool rmlui_remove_animation_end_listener(
    void* document,
    const char* element_id
) {
    if (!document ||
        !element_id) {
        return false;
    }

    auto* doc =
        static_cast<Rml::ElementDocument*>(
            document
        );

    return remove_animation_listener(
        doc,
        element_id
    );
}

bool rmlui_add_click_listener(void* document, const char* element_id, RmlUiClickCallback callback, void* user_data) {
    if (!document || !element_id || !callback) return false;
    auto* doc = static_cast<Rml::ElementDocument*>(document);
    Rml::Element* element = doc->GetElementById(element_id);
    if (!element) return false;
    rmlui_remove_click_listener(document, element_id);
    auto registration = std::make_unique<ClickRegistration>();
    registration->document = doc;
    registration->element = element;
    registration->listener = std::make_unique<ClickListener>(callback, user_data);
    element->AddEventListener(Rml::EventId::Click, registration->listener.get());
    g_click_listeners.push_back(std::move(registration));
    return true;
}

bool rmlui_remove_click_listener(void* document, const char* element_id) {
    if (!document || !element_id) return false;
    auto* doc = static_cast<Rml::ElementDocument*>(document);
    for (size_t i = 0; i < g_click_listeners.size(); ++i) {
        auto& registration = g_click_listeners[i];
        if (registration->document == doc && registration->element && registration->element->GetId() == element_id) {
            registration->element->RemoveEventListener(Rml::EventId::Click, registration->listener.get());
            g_click_listeners.erase(g_click_listeners.begin() + static_cast<std::ptrdiff_t>(i));
            return true;
        }
    }
    return false;
}

// ─────────────────────────────────────────────────────────────
// Rendering
// ─────────────────────────────────────────────────────────────

void rmlui_begin_frame(
    void* command_buffer,
    void* swapchain_or_target_texture,
    int width,
    int height
) {
    if (!g_renderer ||
        !command_buffer ||
        !swapchain_or_target_texture) {
        return;
    }

    auto* cmd =
        static_cast<SDL_GPUCommandBuffer*>(
            command_buffer
        );

    auto* tex =
        static_cast<SDL_GPUTexture*>(
            swapchain_or_target_texture
        );

    g_renderer->BeginFrame(
        cmd,
        tex,
        static_cast<uint32_t>(width),
        static_cast<uint32_t>(height)
    );
}

void rmlui_render_context(
    void* context
) {
    if (!context) {
        return;
    }

    auto* ctx =
        static_cast<Rml::Context*>(
            context
        );

    ctx->Render();
}

void rmlui_end_frame(
    void
) {
    if (!g_renderer) {
        return;
    }

    g_renderer->EndFrame();
}

// ─────────────────────────────────────────────────────────────
// Input
// ─────────────────────────────────────────────────────────────

bool rmlui_process_event(
    void* context,
    void* sdl_window,
    void* sdl_event
) {
    if (!context ||
        !sdl_window ||
        !sdl_event) {
        return false;
    }

    auto* ctx =
        static_cast<Rml::Context*>(
            context
        );

    auto* win =
        static_cast<SDL_Window*>(
            sdl_window
        );

    auto* ev =
        static_cast<SDL_Event*>(
            sdl_event
        );

    return RmlSDL::InputEventHandler(
        ctx,
        win,
        *ev
    );
}

} // extern "C"
