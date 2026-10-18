import Foundation

/// performance diagnostics and statistics for the graphics system
///
/// tracks CPU/GPU frame times, draw calls, batch counts, upload bytes, and
/// other metrics useful for profiling and optimization
///
/// nothing feeds these yet: the renderer calls 'frameCompleted()' without
/// timings and the 'record...' methods below are never called, so 'snapshot()'
/// reports zeros apart from 'frameIndex'. both are public so a game can record
/// its own numbers
///
/// 'Diagnostics' is '@unchecked Sendable' because its counters and history
/// are only written from the main thread
public final class Diagnostics: @unchecked Sendable {
    // frame timing
    private var _cpuFrameTimes: [Float] = []
    private var _gpuFrameTimes: [Float] = []
    private let maxHistoryCount = 120 // 2 seconds at 60 FPS
    
    // per-frame counters
    public private(set) var drawCalls: Int = 0
    public private(set) var batchCount: Int = 0
    public private(set) var vertexCount: Int = 0
    public private(set) var indexCount: Int = 0
    public private(set) var triangleCount: Int = 0
    public private(set) var uploadBytes: UInt64 = 0
    public private(set) var renderPassCount: Int = 0
    public private(set) var pipelineChanges: Int = 0
    public private(set) var textureChanges: Int = 0
    
    // averages
    public private(set) var avgCPUFrameTime: Float = 0
    public private(set) var avgGPUFrameTime: Float = 0
    public private(set) var avgDrawCalls: Float = 0
    public private(set) var avgBatchCount: Float = 0
    
    // frame index
    public private(set) var frameIndex: UInt64 = 0
    
    /// records the end of a frame and updates statistics
    public func frameCompleted(cpuTime: Float = 0, gpuTime: Float = 0) {
        frameIndex += 1
        
        if cpuTime > 0 {
            _cpuFrameTimes.append(cpuTime)
            if _cpuFrameTimes.count > maxHistoryCount {
                _cpuFrameTimes.removeFirst()
            }
            avgCPUFrameTime = _cpuFrameTimes.reduce(0, +) / Float(_cpuFrameTimes.count)
        }
        
        if gpuTime > 0 {
            _gpuFrameTimes.append(gpuTime)
            if _gpuFrameTimes.count > maxHistoryCount {
                _gpuFrameTimes.removeFirst()
            }
            avgGPUFrameTime = _gpuFrameTimes.reduce(0, +) / Float(_gpuFrameTimes.count)
        }
        
        // update running averages (exponential moving average)
        let alpha: Float = 0.1
        avgDrawCalls = avgDrawCalls * (1 - alpha) + Float(drawCalls) * alpha
        avgBatchCount = avgBatchCount * (1 - alpha) + Float(batchCount) * alpha
        
        // reset per-frame counters
        drawCalls = 0
        batchCount = 0
        vertexCount = 0
        indexCount = 0
        triangleCount = 0
        uploadBytes = 0
        renderPassCount = 0
        pipelineChanges = 0
        textureChanges = 0
    }
    
    /// increments the draw call counter
    public func recordDrawCall() {
        drawCalls += 1
    }
    
    /// increments the batch counter
    public func recordBatch() {
        batchCount += 1
    }
    
    /// adds to the vertex count
    public func recordVertices(_ count: Int) {
        vertexCount += count
    }
    
    /// adds to the index count
    public func recordIndices(_ count: Int) {
        indexCount += count
    }
    
    /// adds to the triangle count
    public func recordTriangles(_ count: Int) {
        triangleCount += count
    }
    
    /// adds to the upload bytes counter
    public func recordUpload(bytes: UInt64) {
        uploadBytes += bytes
    }
    
    /// increments the render pass counter
    public func recordRenderPass() {
        renderPassCount += 1
    }
    
    /// increments the pipeline change counter
    public func recordPipelineChange() {
        pipelineChanges += 1
    }
    
    /// increments the texture change counter
    public func recordTextureChange() {
        textureChanges += 1
    }
    
    /// returns a snapshot of current diagnostics
    public func snapshot() -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            frameIndex: frameIndex,
            cpuFrameTime: _cpuFrameTimes.last ?? 0,
            gpuFrameTime: _gpuFrameTimes.last ?? 0,
            avgCPUFrameTime: avgCPUFrameTime,
            avgGPUFrameTime: avgGPUFrameTime,
            drawCalls: drawCalls,
            batchCount: batchCount,
            vertexCount: vertexCount,
            indexCount: indexCount,
            triangleCount: triangleCount,
            uploadBytes: uploadBytes,
            renderPassCount: renderPassCount,
            pipelineChanges: pipelineChanges,
            textureChanges: textureChanges,
            avgDrawCalls: avgDrawCalls,
            avgBatchCount: avgBatchCount
        )
    }
    
    /// resets all diagnostics
    public func reset() {
        _cpuFrameTimes.removeAll()
        _gpuFrameTimes.removeAll()
        drawCalls = 0
        batchCount = 0
        vertexCount = 0
        indexCount = 0
        triangleCount = 0
        uploadBytes = 0
        renderPassCount = 0
        pipelineChanges = 0
        textureChanges = 0
        avgCPUFrameTime = 0
        avgGPUFrameTime = 0
        avgDrawCalls = 0
        avgBatchCount = 0
        frameIndex = 0
    }
}

/// a snapshot of diagnostics at a point in time
public struct DiagnosticsSnapshot: Sendable {
    public let frameIndex: UInt64
    public let cpuFrameTime: Float
    public let gpuFrameTime: Float
    public let avgCPUFrameTime: Float
    public let avgGPUFrameTime: Float
    public let drawCalls: Int
    public let batchCount: Int
    public let vertexCount: Int
    public let indexCount: Int
    public let triangleCount: Int
    public let uploadBytes: UInt64
    public let renderPassCount: Int
    public let pipelineChanges: Int
    public let textureChanges: Int
    public let avgDrawCalls: Float
    public let avgBatchCount: Float
    
    public var cpuFPS: Float {
        cpuFrameTime > 0 ? 1.0 / cpuFrameTime : 0
    }
    
    public var avgCPUFPS: Float {
        avgCPUFrameTime > 0 ? 1.0 / avgCPUFrameTime : 0
    }
    
    public var gpuFPS: Float {
        gpuFrameTime > 0 ? 1.0 / gpuFrameTime : 0
    }
    
    public var avgGPUFPS: Float {
        avgGPUFrameTime > 0 ? 1.0 / avgGPUFrameTime : 0
    }
}
