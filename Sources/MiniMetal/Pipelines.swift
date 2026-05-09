import Metal

extension MTLDevice {

    // MARK: - Render pipelines

    /// Compiles `shader.source` into a one-off `MTLLibrary` and builds an
    /// `MTLRenderPipelineState` from the named entry points.
    ///
    /// Convenient for demos. Production code typically loads a precompiled
    /// `metallib` once and uses the `library:` overload below for every
    /// pipeline so shader compilation doesn't run on the hot path.
    public func makeRenderPipeline(
        shader: MetalShader,
        vertex: String,
        fragment: String,
        color: MTLPixelFormat,
        depth: MTLPixelFormat = .invalid,
        configure: (MTLRenderPipelineDescriptor) -> Void = { _ in }
    ) async throws -> MTLRenderPipelineState {
        let library = try await makeLibrary(source: shader.source, options: nil)
        return try await makeRenderPipeline(
            library: library,
            vertex: vertex,
            fragment: fragment,
            color: color,
            depth: depth,
            configure: configure
        )
    }

    /// Builds an `MTLRenderPipelineState` from a precompiled library.
    /// `configure` runs after the basic descriptor fields are set, so
    /// callers can override or extend (e.g., set blending, vertex
    /// descriptors, raster sample count) without re-typing the basics.
    public func makeRenderPipeline(
        library: MTLLibrary,
        vertex: String,
        fragment: String,
        color: MTLPixelFormat,
        depth: MTLPixelFormat = .invalid,
        configure: (MTLRenderPipelineDescriptor) -> Void = { _ in }
    ) async throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        descriptor.colorAttachments[0].pixelFormat = color
        descriptor.depthAttachmentPixelFormat = depth
        configure(descriptor)
        return try await makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: - Compute pipelines

    /// Compiles `shader.source` and builds an `MTLComputePipelineState`
    /// from the named kernel function.
    public func makeComputePipeline(
        shader: MetalShader,
        function: String
    ) async throws -> MTLComputePipelineState {
        let library = try await makeLibrary(source: shader.source, options: nil)
        return try await makeComputePipeline(library: library, function: function)
    }

    /// Builds an `MTLComputePipelineState` from a precompiled library.
    public func makeComputePipeline(
        library: MTLLibrary,
        function: String
    ) async throws -> MTLComputePipelineState {
        guard let kernel = library.makeFunction(name: function) else {
            throw NSError(
                domain: "MiniMetal.makeComputePipeline",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "library has no function named '\(function)'"]
            )
        }
        return try await makeComputePipelineState(function: kernel)
    }

    // MARK: - Depth/stencil

    /// One-call form of `MTLDepthStencilDescriptor` + `makeDepthStencilState`,
    /// covering the configurations demos almost always want. Defaults to
    /// the standard "less, write-enabled" Z-buffer.
    public func makeDepthStencilState(
        compare: MTLCompareFunction = .less,
        write: Bool = true
    ) -> MTLDepthStencilState {
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = compare
        d.isDepthWriteEnabled = write
        guard let state = makeDepthStencilState(descriptor: d) else {
            preconditionFailure(
                "MTLDevice.makeDepthStencilState(descriptor:) returned nil for " +
                "compare=\(compare) write=\(write); these are valid inputs.")
        }
        return state
    }
}
