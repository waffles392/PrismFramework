import CSDL3
import Foundation

/// manages frame lifecycle and submission
///
/// the FrameContext handles acquiring frames, presenting, and managing
/// the swapchain. it also tracks the number of frames in flight
///
/// 'FrameContext' is '@unchecked Sendable' because 'isActive' and the
/// swapchain texture are only driven from the main thread
public final class FrameContext: @unchecked Sendable {
    private let device: GPUDevice
    private let window: OpaquePointer
    private var isActive = false
    
    public init(device: GPUDevice, window: OpaquePointer) {
        self.device = device
        self.window = window
    }
    
    /// begins a new frame
    ///
    /// returns nil if the GPU is interrupted or a frame is already active
    /// throws if frame acquisition fails
    public func beginFrame() throws -> Frame? {
        guard !isActive else { return nil }
        
        guard let deviceHandle = device.handle else {
            throw GPUError.deviceShutdown
        }
        
        isActive = true
        return try Frame(device: deviceHandle, window: window)
    }
    
    /// ends the current frame and presents it
    ///
    /// if the frame has no swapchain texture (window minimized), the command
    /// buffer is still submitted to maintain frame pacing
    public func endFrame(_ frame: Frame) {
        isActive = false
        
        // submit even if no swapchain texture (minimized window)
        // the command buffer was acquired and must be submitted/canceled
        do {
            try frame.submit()
        } catch {
            // if submit fails, cancel the command buffer
            frame.cancel()
        }
    }
    
    /// cancels the current frame without presenting
    public func cancelFrame(_ frame: Frame) {
        isActive = false
        frame.cancel()
    }
    
    /// sets the swapchain present mode (vsync/immediate/mailbox)
    public func setPresentMode(_ mode: GPUPresentMode) throws {
        guard let deviceHandle = device.handle else {
            throw GPUError.deviceShutdown
        }
        
        guard mode.isSupported(device: deviceHandle, window: window) else { return }
        
        SDL_SetGPUSwapchainParameters(
            deviceHandle,
            window,
            SDL_GPU_SWAPCHAINCOMPOSITION_SDR,
            mode.sdlValue
        )
    }
    
    /// enables or disables vertical sync
    public func setVsync(_ enabled: Bool) throws {
        try setPresentMode(enabled ? .vsync : .immediate)
    }
    
    /// sets the maximum number of frames in flight
    public func setMaxFramesInFlight(_ frames: Int) throws {
        guard let deviceHandle = device.handle else {
            throw GPUError.deviceShutdown
        }
        SDL_SetGPUAllowedFramesInFlight(deviceHandle, UInt32(max(1, frames)))
    }
    
    /// waits for the GPU to become idle
    public func waitForIdle() throws {
        guard let deviceHandle = device.handle else {
            throw GPUError.deviceShutdown
        }
        _ = SDL_WaitForGPUIdle(deviceHandle)
    }
}

/// presentation mode of the GPU swapchain
public enum GPUPresentMode: Sendable {
    case vsync
    case immediate
    case mailbox
    
    var sdlValue: SDL_GPUPresentMode {
        switch self {
        case .vsync: return SDL_GPU_PRESENTMODE_VSYNC
        case .immediate: return SDL_GPU_PRESENTMODE_IMMEDIATE
        case .mailbox: return SDL_GPU_PRESENTMODE_MAILBOX
        }
    }
    
    /// whether the device and window support this mode
    public func isSupported(device: OpaquePointer, window: OpaquePointer) -> Bool {
        SDL_WindowSupportsGPUPresentMode(device, window, sdlValue)
    }
}