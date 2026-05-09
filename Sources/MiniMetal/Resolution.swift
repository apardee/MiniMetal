import CoreGraphics

/// The pixel dimensions of a ``MiniMetalWindow``'s content area.
///
/// `Resolution` is a lightweight value type so that callers can construct it
/// inline without importing CoreGraphics:
///
///     let window = MiniMetalWindow(
///         title: "Demo",
///         resolution: .init(width: 1280, height: 720))
public struct Resolution: Sendable, Hashable {
    /// Width in pixels.
    public var width: Int

    /// Height in pixels.
    public var height: Int

    /// Creates a resolution with the given pixel dimensions.
    /// - Parameters:
    ///   - width: Width in pixels. Must be positive.
    ///   - height: Height in pixels. Must be positive.
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// The resolution expressed as a `CGSize`, suitable for use with AppKit
    /// and Metal APIs.
    public var size: CGSize {
        CGSize(width: width, height: height)
    }
}
