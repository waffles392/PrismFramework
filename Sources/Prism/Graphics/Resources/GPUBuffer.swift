import CSDL3
import Foundation

/// a GPU buffer resource (vertex, index, uniform, or storage buffer)
///
/// GPU buffers are created through 'GPUDevice' and are reference-counted through
/// the device's resource tracking. the buffer is automatically released when
/// this object is deinitialized
///
/// 'GPUBuffer' is '@unchecked Sendable' because it is read-only after init:
/// the C handle is stored once and only read
public final class GPUBuffer: @unchecked Sendable {
    internal let handle: OpaquePointer
    public let size: UInt32
    public let usage: SDL_GPUBufferUsageFlags
    
    private let device: GPUDevice
    private let resourceToken: UInt64
    
    internal init(device: GPUDevice, size: UInt32, usage: SDL_GPUBufferUsageFlags) throws {
        self.device = device
        self.size = size
        self.usage = usage
        
        guard let handle = device.handle else {
            throw GPUError.deviceShutdown
        }
        
        var info = SDL_GPUBufferCreateInfo()
        info.usage = usage
        info.size = size
        
        guard let buffer = SDL_CreateGPUBuffer(handle, &info) else {
            throw GPUError.resourceCreationFailed(String(cString: SDL_GetError()))
        }
        
        self.handle = buffer
        self.resourceToken = device.registerResource { [weak device] in
            guard let deviceHandle = device?.handle else { return }
            SDL_ReleaseGPUBuffer(deviceHandle, buffer)
        }
    }
    
    deinit {
        guard device.unregisterResource(resourceToken) else { return }
        guard let deviceHandle = device.handle else { return }
        SDL_ReleaseGPUBuffer(deviceHandle, handle)
    }
}

/// a typed GPU buffer with CPU-side staging array for uniform/instance data
///
/// this provides a convenient way to update uniform or instance data each frame
/// without manual transfer buffer management. the CPU-side data is uploaded
/// to the GPU buffer during the frame's copy pass
///
/// 'TypedGPUBuffer' is '@unchecked Sendable' because the engine never touches
/// 'data' from more than one thread; the staging buffer is not synchronised
public final class TypedGPUBuffer<T>: @unchecked Sendable {
    private let buffer: GPUBuffer
    private let rawPointer: UnsafeMutablePointer<T>
    private let count: Int
    private let stride: Int
    private let device: GPUDevice
    
    public var handle: OpaquePointer { buffer.handle }
    public var byteSize: UInt32 { buffer.size }
    
    /// access to the CPU-side staging data
    public var data: UnsafeMutableBufferPointer<T> {
        UnsafeMutableBufferPointer(start: rawPointer, count: count)
    }
    
    internal init(device: GPUDevice, count: Int, usage: SDL_GPUBufferUsageFlags = SDL_GPU_BUFFERUSAGE_VERTEX) throws {
        self.device = device
        self.count = count
        self.stride = MemoryLayout<T>.stride
        let byteCount = UInt32(count * stride)
        
        self.buffer = try GPUBuffer(device: device, size: byteCount, usage: usage)
        
        // allocate CPU staging array
        self.rawPointer = UnsafeMutablePointer<T>.allocate(capacity: count)
    }
    
    /// uploads the CPU-side data to the GPU buffer using a transfer buffer
    /// call this during the frame's copy pass (or from within a render pass)
    public func upload(commandBuffer: OpaquePointer) throws {
        guard count > 0 else { return }
        let byteCount = count * stride
        
        let transferBuffer = try GPUTransferBuffer(device: device, size: UInt32(byteCount))
        
        try rawPointer.withMemoryRebound(to: UInt8.self, capacity: byteCount) { bytes in
            try transferBuffer.write(from: bytes, byteCount: byteCount)
        }
        
        try transferBuffer.upload(to: buffer, size: UInt32(byteCount), commandBuffer: commandBuffer)
    }
    
    deinit {
        // deallocate the CPU staging array
        // using a pointer to avoid Sendable issues in deinit
        let ptr = rawPointer
        ptr.deallocate()
    }
}

/// a GPU transfer buffer for uploading data to GPU resources
///
/// transfer buffers are CPU-visible and used for one-time uploads. they are
/// deliberately separate from 'GPUBuffer' as they have different usage,
/// lifetime, and mapping APIs in SDL
///
/// 'GPUTransferBuffer' is '@unchecked Sendable' because it is read-only after
/// init and mapping only happens on the main thread
public final class GPUTransferBuffer: @unchecked Sendable {
    private let device: GPUDevice
    internal let handle: OpaquePointer
    private let resourceToken: UInt64
    
    internal init(device: GPUDevice, size: UInt32) throws {
        self.device = device
        
        guard let deviceHandle = device.handle else {
            throw GPUError.deviceShutdown
        }
        
        var info = SDL_GPUTransferBufferCreateInfo()
        info.usage = SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD
        info.size = size
        
        guard let buffer = SDL_CreateGPUTransferBuffer(deviceHandle, &info) else {
            throw GPUError.resourceCreationFailed(String(cString: SDL_GetError()))
        }
        
        self.handle = buffer
        self.resourceToken = device.registerResource { [weak device] in
            guard let deviceHandle = device?.handle else { return }
            SDL_ReleaseGPUTransferBuffer(deviceHandle, buffer)
        }
    }
    
    /// writes data into the transfer buffer's CPU-visible memory
    ///
    /// throws if the buffer cannot be mapped, which happens when the device
    /// has run out of staging memory
    public func write(from source: UnsafeRawPointer, byteCount: Int) throws {
        guard let deviceHandle = device.handle else { return }
        
        guard let mapped = SDL_MapGPUTransferBuffer(deviceHandle, handle, true) else {
            throw GPUError.resourceCreationFailed(String(cString: SDL_GetError()))
        }
        
        mapped.copyMemory(from: source, byteCount: byteCount)
        SDL_UnmapGPUTransferBuffer(deviceHandle, handle)
    }
    
    /// uploads the transfer buffer contents to a GPU buffer via a copy pass
    public func upload(to destination: GPUBuffer, size: UInt32, commandBuffer: OpaquePointer) throws {
        guard device.handle != nil else { return }
        
        guard let copyPass = SDL_BeginGPUCopyPass(commandBuffer) else {
            throw GPUError.resourceCreationFailed(String(cString: SDL_GetError()))
        }
        
        var source = SDL_GPUTransferBufferLocation()
        source.transfer_buffer = handle
        source.offset = 0
        
        var dest = SDL_GPUBufferRegion()
        dest.buffer = destination.handle
        dest.offset = 0
        dest.size = size
        
        SDL_UploadToGPUBuffer(copyPass, &source, &dest, true)
        SDL_EndGPUCopyPass(copyPass)
    }
    
    deinit {
        guard device.unregisterResource(resourceToken) else { return }
        guard let deviceHandle = device.handle else { return }
        SDL_ReleaseGPUTransferBuffer(deviceHandle, handle)
    }
}