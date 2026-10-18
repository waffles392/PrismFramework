import CSDL3
import Foundation

/// per-frame upload arena for efficient GPU resource uploads
///
/// the upload arena manages a ring of transfer buffers that are reused
/// across frames to avoid repeated allocation/deallocation. each frame
/// gets a slice of the arena for its uploads
///
/// 'UploadArena' is '@unchecked Sendable' because its buffer ring and frame
/// index are only advanced from the main thread
public final class UploadArena: @unchecked Sendable {
    private let device: GPUDevice
    private var buffers: [UploadBuffer] = []
    private var currentFrameIndex = 0
    private let maxFramesInFlight: Int
    private let bufferSize: UInt32
    
    private struct UploadBuffer {
        let transferBuffer: GPUTransferBuffer
        var usedBytes: UInt32 = 0
    }
    
    /// creates a new upload arena
    /// - Parameters:
    ///   - device: the GPU device
    ///   - maxFramesInFlight: max frames in flight. defaults to the device
    ///   - bufferSize: size of each transfer buffer in bytes (default 1MB)
    public init(device: GPUDevice, maxFramesInFlight: Int? = nil, bufferSize: UInt32 = 1024 * 1024) {
        self.device = device
        self.maxFramesInFlight = maxFramesInFlight ?? device.capabilities.preferredFramesInFlight
        self.bufferSize = bufferSize
        
        // pre-allocate buffers for each frame in flight
        for _ in 0..<self.maxFramesInFlight {
            if let buffer = try? GPUTransferBuffer(device: device, size: bufferSize) {
                buffers.append(UploadBuffer(transferBuffer: buffer))
            }
        }
    }
    
    /// gets the current frame's upload buffer, advancing the frame index
    /// returns nil if no buffers are available
    public func nextFrame() -> GPUTransferBuffer? {
        guard !buffers.isEmpty else { return nil }
        
        var buffer = buffers[currentFrameIndex]
        buffer.usedBytes = 0
        buffers[currentFrameIndex] = buffer
        currentFrameIndex = (currentFrameIndex + 1) % buffers.count
        return buffer.transferBuffer
    }
    
    /// allocates space in the current frame's upload buffer
    /// returns a pointer to the mapped memory and the offset, or nil if out of space
    public func allocate(bytes: UInt32, alignment: UInt32 = 256) -> (transferBuffer: GPUTransferBuffer, offset: UInt32, mappedPointer: UnsafeMutableRawPointer)? {
        guard !buffers.isEmpty else { return nil }
        
        var buffer = buffers[currentFrameIndex]
        
        // align offset
        let alignedOffset = (buffer.usedBytes + alignment - 1) & ~(alignment - 1)
        
        guard alignedOffset + bytes <= bufferSize else {
            return nil // Out of space
        }
        
        guard let deviceHandle = device.handle else { return nil }
        let mapped = SDL_MapGPUTransferBuffer(deviceHandle, buffer.transferBuffer.handle, true)
        guard mapped != nil else { return nil }
        
        let pointer = mapped!.advanced(by: Int(alignedOffset))
        buffer.usedBytes = alignedOffset + bytes
        buffers[currentFrameIndex] = buffer
        
        return (buffer.transferBuffer, alignedOffset, pointer)
    }
    
    /// uploads data using the current frame's transfer buffer
    /// this is a convenience method that allocates, copies, and queues the upload
    public func upload(
        data: UnsafeRawPointer,
        byteCount: Int,
        to destination: GPUBuffer,
        destinationOffset: UInt32 = 0,
        commandBuffer: OpaquePointer
    ) -> Bool {
        guard let allocation = allocate(bytes: UInt32(byteCount)) else {
            return false
        }
        
        allocation.mappedPointer.copyMemory(from: data, byteCount: byteCount)
        
        guard let deviceHandle = device.handle else { return false }
        SDL_UnmapGPUTransferBuffer(deviceHandle, allocation.transferBuffer.handle)
        
        // queue the upload in a copy pass
        guard let copyPass = SDL_BeginGPUCopyPass(commandBuffer) else {
            return false
        }
        
        var source = SDL_GPUTransferBufferLocation()
        source.transfer_buffer = allocation.transferBuffer.handle
        source.offset = allocation.offset
        
        var dest = SDL_GPUBufferRegion()
        dest.buffer = destination.handle
        dest.offset = destinationOffset
        dest.size = UInt32(byteCount)
        
        SDL_UploadToGPUBuffer(copyPass, &source, &dest, true)
        SDL_EndGPUCopyPass(copyPass)
        
        return true
    }
    
    /// uploads data from a Swift array
    public func upload<T>(
        _ array: [T],
        to destination: GPUBuffer,
        destinationOffset: UInt32 = 0,
        commandBuffer: OpaquePointer
    ) -> Bool {
        let byteCount = array.count * MemoryLayout<T>.stride
        return array.withUnsafeBytes { bytes in
            upload(
                data: bytes.baseAddress!,
                byteCount: byteCount,
                to: destination,
                destinationOffset: destinationOffset,
                commandBuffer: commandBuffer
            )
        }
    }
}