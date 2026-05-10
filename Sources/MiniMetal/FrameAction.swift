/// The action a per-frame render closure requests after producing a frame.
///
/// Returned from the closure passed to ``Window/show(_:)`` to either
/// keep the run loop going or tear it down.
public enum FrameAction: Sendable, Hashable {
    /// Continue running the window: another frame will be requested.
    case `continue`

    /// Stop running the window: ``Window/show(_:)`` will return.
    case quit
}
