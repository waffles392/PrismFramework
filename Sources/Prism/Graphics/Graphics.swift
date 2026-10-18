// Prism Graphics - 2D mesh rendering layer
//
// a fast, general-purpose rendering layer for games ranging from tile-based
// platformers to particle-heavy, Geometry Wars-style games, with room to grow
// into 3D. built on Swift + SDL3 GPU
//
// module layout:
// - GPUDevice / GPUError: device lifetime and resource creation
// - Renderer / FrameContext: frame lifecycle management
// - Resources: buffers, textures, shaders, pipelines
// - Memory: upload arena, frame slots, resource retirement
// - Pipeline: pipeline descriptors, objects, cache
// - Drawing2D: canvas2D, mesh builder, primitive geometry
// - PostProcessing: bloom, color grading, and VHS post effects
// - Particles: CPU particle simulation and vertex generation
// - Diagnostics: statistics and GPU profiling
// - Color: color and blend modes

// all types are in the Graphics module; subdirectories are for
// organization only