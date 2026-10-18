import Foundation

/// errors that can occur during GPU device operations
public enum GPUError: Error, Equatable, Sendable {
    /// the provided window handle was nil
    case invalidWindow
    
    /// failed to create the SDL properties object
    case propertyCreationFailed(String)
    
    /// the requested GPU configuration is not supported on this device
    case unsupportedConfiguration(String)
    
    /// failed to create the GPU device
    case deviceCreationFailed(String)
    
    /// failed to claim the window for the GPU device
    case windowClaimFailed(String)
    
    /// the GPU device has been shut down and cannot be used
    case deviceShutdown
    
    /// failed to acquire a command buffer
    case commandBufferAcquisitionFailed(String)
    
    /// failed to acquire the swapchain texture
    case swapchainAcquisitionFailed(String)
    
    /// the window is minimized or occluded; no swapchain texture available
    case windowMinimized
    
    /// failed to create a GPU resource
    case resourceCreationFailed(String)
    
    /// failed to create a shader module
    case shaderCreationFailed(String)
    
    /// failed to create a graphics pipeline
    case pipelineCreationFailed(String)
    
    /// failed to begin a render or copy pass
    case passBeginFailed(String)
    
    /// failed to submit the command buffer
    case commandBufferSubmitFailed(String)
}