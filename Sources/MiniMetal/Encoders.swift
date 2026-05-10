import Metal

// Convenience uniform-setting methods that pair with `@MetalLayout` types:
// constraining `T` to `MetalUniform` keeps you on the layout-checked path
// (the `@MetalLayout` macro guarantees Swift and MSL strides agree), and
// lets you skip the `MemoryLayout<T>.stride` boilerplate.
//
// For raw `simd_float*` values or anything else not declared with
// `@MetalLayout`, fall back to the standard `setVertexBytes(_:length:index:)`.

extension MTLRenderCommandEncoder {

    /// Sets `value` at the given vertex buffer index using its Swift stride.
    public func setVertexUniforms<T: MetalUniform>(_ value: T, index: Int) {
        withUnsafeBytes(of: value) { buffer in
            setVertexBytes(buffer.baseAddress!, length: MemoryLayout<T>.stride, index: index)
        }
    }

    /// Sets `value` at the given fragment buffer index using its Swift stride.
    public func setFragmentUniforms<T: MetalUniform>(_ value: T, index: Int) {
        withUnsafeBytes(of: value) { buffer in
            setFragmentBytes(buffer.baseAddress!, length: MemoryLayout<T>.stride, index: index)
        }
    }
}

extension MTLComputeCommandEncoder {

    /// Sets `value` at the given buffer index using its Swift stride.
    public func setUniforms<T: MetalUniform>(_ value: T, index: Int) {
        withUnsafeBytes(of: value) { buffer in
            setBytes(buffer.baseAddress!, length: MemoryLayout<T>.stride, index: index)
        }
    }
}
