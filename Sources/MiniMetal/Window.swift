import AppKit
import Metal
import MetalKit

/// A simple macOS window backed by an `MTKView`, designed for Metal rendering
/// demos and prototypes.
///
/// `Window` collapses the usual AppKit ceremony — `NSApplication`
/// activation, window creation, `MTKViewDelegate` conformance, and run-loop
/// management — into two lines of user code:
///
///     let window = try Window(
///         title: "Demo",
///         resolution: .init(width: 640, height: 480))
///     await window.show { view in
///         // ...issue Metal draw commands against `view`...
///         return .continue
///     }
///
/// There are two ways to drive rendering:
///
/// 1. **Delegate.** Set ``delegate`` to an object adopting
///    ``MiniMetalWindowDelegate``, then `await` ``show()``. The delegate's
///    ``MiniMetalWindowDelegate/draw(in:)`` runs each frame.
/// 2. **Closure.** `await` ``show(_:)`` with a closure. The closure runs each
///    frame and returns ``FrameAction/quit`` to tear the window down.
///
/// In both cases the `await` returns when the window has closed (whether by
/// the user clicking the close button, the closure returning
/// ``FrameAction/quit``, or a call to ``close()``).
///
/// The underlying ``window`` and ``view`` are exposed for callers that need
/// direct access to AppKit / MetalKit features that aren't surfaced here.
@MainActor
public final class Window {

    /// Window-related errors.
    public enum Error: Swift.Error {
        /// Error creating during window construction.
        case deviceCreationFailed
    }

    /// The underlying `NSWindow`. Exposed for advanced configuration; most
    /// callers shouldn't need to touch it.
    public let window: NSWindow

    /// The underlying `MTKView`. Use this to query the Metal device, create
    /// command queues, configure pixel formats, etc.
    public let view: MTKView

    /// The Metal device backing ``view``.
    public var device: MTLDevice {
        // The view always has a device because `init` precondition-fails
        // without one.
        view.device!
    }

    /// The delegate that receives draw and resize callbacks while ``show()``
    /// is running. Ignored by ``show(_:)``, which uses its closure instead.
    public weak var delegate: (any MiniMetalWindowDelegate)? {
        get { drawAdapter.userDelegate }
        set { drawAdapter.userDelegate = newValue }
    }

    private let drawAdapter: DrawAdapter
    private let windowAdapter: WindowAdapter

    /// Creates a window with the given title and content resolution.
    ///
    /// The window is created but **not** displayed until ``show()`` or
    /// ``show(_:)`` is called.
    ///
    /// - Parameters:
    ///   - title: The window title bar text.
    ///   - resolution: The pixel size of the content area.
    ///   - device: The Metal device to render with. Defaults to the system's
    ///     default device. Pass an explicit device to target, e.g., a
    ///     non-default GPU.
    public init(
        title: String,
        resolution: Resolution,
        device: MTLDevice? = nil
    ) throws(Error) {
        guard let metalDevice = device ?? MTLCreateSystemDefaultDevice() else {
            throw .deviceCreationFailed
        }

        let frame = NSRect(x: 0, y: 0, width: resolution.width, height: resolution.height)
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let nsWindow = NSWindow(
            contentRect: frame,
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        nsWindow.title = title
        nsWindow.center()

        let mtkView = MTKView(frame: frame, device: metalDevice)
        mtkView.colorPixelFormat = .bgra8Unorm
        nsWindow.contentView = mtkView

        let drawAdapter = DrawAdapter()
        let windowAdapter = WindowAdapter()
        mtkView.delegate = drawAdapter
        nsWindow.delegate = windowAdapter

        self.window = nsWindow
        self.view = mtkView
        self.drawAdapter = drawAdapter
        self.windowAdapter = windowAdapter
    }

    /// Displays the window and awaits its closure.
    ///
    /// While running, draw and resize callbacks are dispatched to ``delegate``
    /// (if one is set). The call returns when the window is closed by the
    /// user, by ``close()``, or by any other means.
    public func show() async {
        runUntilClosed()
    }

    /// Displays the window and awaits its closure, driving each frame from a
    /// closure rather than a delegate.
    ///
    /// The closure runs once per frame on the main actor with the
    /// Metal-backed view. Return ``FrameAction/continue`` to keep rendering or
    /// ``FrameAction/quit`` to close the window and return from this call.
    /// Any value previously assigned to ``delegate`` is ignored for the
    /// duration of this call but otherwise left intact.
    ///
    /// - Parameter render: The per-frame render closure.
    public func show(_ render: @MainActor @escaping (MTKView) -> FrameAction) async {
        drawAdapter.closure = render
        defer { drawAdapter.closure = nil }
        runUntilClosed()
    }

    /// Displays the window and awaits its closure, driving each frame from a
    /// closure that receives a fully-prepared ``Frame``.
    ///
    /// This overload owns a command queue internally, acquires a render pass
    /// descriptor / drawable / command buffer / encoder for each frame, and
    /// presents+commits after the closure returns. Frames where the drawable
    /// isn't ready are skipped silently.
    ///
    /// Return ``FrameAction/continue`` to keep rendering or
    /// ``FrameAction/quit`` to close the window and return from this call.
    ///
    /// - Parameter render: The per-frame render closure.
    public func show(_ render: @MainActor @escaping (Frame) -> FrameAction) async {
        guard let queue = device.makeCommandQueue() else {
            assertionFailure("MTLDevice.makeCommandQueue() returned nil")
            return
        }
        await show { (view: MTKView) -> FrameAction in
            guard let frame = view.beginFrame(queue: queue) else { return .continue }
            defer { frame.finish() }
            return render(frame)
        }
    }

    /// Displays the window and awaits its closure, driving each frame from a
    /// closure that receives a fully-prepared ``Frame4`` (Metal 4).
    ///
    /// This overload owns a Metal 4 command queue, command buffer, and
    /// command allocator internally — single-frame-in-flight, matching
    /// Apple's reference sample. Frames where the drawable isn't ready are
    /// skipped silently.
    ///
    /// For higher throughput (multi-frame-in-flight with a pool of
    /// allocators), drop down to ``MetalKit/MTKView/beginFrame4(queue:commandBuffer:allocator:)``
    /// directly.
    ///
    /// - Parameter render: The per-frame render closure.
    @available(macOS 26.0, *)
    public func show(_ render: @MainActor @escaping (Frame4) -> FrameAction) async {
        guard let queue = device.makeMTL4CommandQueue(),
            let buffer = device.makeCommandBuffer(),
            let allocator = device.makeCommandAllocator()
        else {
            assertionFailure("Metal 4 setup failed (queue / buffer / allocator)")
            return
        }
        await show { (view: MTKView) -> FrameAction in
            guard let frame = view.beginFrame4(
                queue: queue, commandBuffer: buffer, allocator: allocator)
            else { return .continue }
            defer { frame.finish(queue: queue) }
            return render(frame)
        }
    }

    /// Programmatically closes the window. If a ``show()`` call is currently
    /// awaiting, it will return shortly after.
    public func close() {
        window.performClose(nil)
    }

    // MARK: - Internals

    private func runUntilClosed() {
        Self.ensureAppLaunched()

        var done = false
        windowAdapter.onClose = { done = true }
        drawAdapter.onQuit = { [weak self] in
            self?.window.performClose(nil)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        view.isPaused = true
        view.enableSetNeedsDisplay = false

        // Drive draws from a CADisplayLink so rendering tracks the display's
        // native refresh rate (60Hz, 120Hz ProMotion, etc.). MTKView's own
        // display link doesn't fire under our manual run loop, but a
        // CADisplayLink we install ourselves does.
        let driver = DisplayLinkDriver(view: view)
        let displayLink = view.displayLink(
            target: driver, selector: #selector(DisplayLinkDriver.tick(_:)))
        displayLink.add(to: .main, forMode: .common)
        defer { displayLink.invalidate() }

        while !done {
            // NSApp.run() / Swift's @main async runtime each want to own the
            // main thread but don't cooperate, so we drain AppKit's event
            // queue ourselves to keep window controls (close, resize,
            // miniaturize) responsive.
            while let event = NSApp.nextEvent(
                matching: .any,
                until: Date.distantPast,
                inMode: .default,
                dequeue: true
            ) {
                NSApp.sendEvent(event)
            }

            // Park in the run loop until something happens — a display-link
            // tick, a new event, a timer, or the timeout.
            CFRunLoopRunInMode(.defaultMode, 0.1, false)
        }
    }

    private static var didLaunchApp = false

    private static func ensureAppLaunched() {
        guard !didLaunchApp else { return }
        didLaunchApp = true
        let app = NSApplication.shared
        if app.activationPolicy() != .regular {
            app.setActivationPolicy(.regular)
        }
        app.finishLaunching()
    }
}

/// Bridges `CADisplayLink`'s `@objc` selector callback to a `view.draw()` call.
@MainActor
final class DisplayLinkDriver: NSObject {
    weak var view: MTKView?

    init(view: MTKView) {
        self.view = view
    }

    @objc func tick(_ sender: CADisplayLink) {
        view?.draw()
    }
}

// MARK: - Internal AppKit / MetalKit adapters

/// Bridges `MTKViewDelegate` (a nonisolated, NSObjectProtocol-constrained
/// protocol) to either a ``MiniMetalWindowDelegate`` or a per-frame closure.
@MainActor
final class DrawAdapter: NSObject, MTKViewDelegate {
    weak var userDelegate: (any MiniMetalWindowDelegate)?
    var closure: (@MainActor (MTKView) -> FrameAction)?
    var onQuit: (@MainActor () -> Void)?

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        MainActor.assumeIsolated {
            userDelegate?.mtkView(view, drawableSizeWillChange: size)
        }
    }

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            if let closure {
                let action = closure(view)
                if action == .quit {
                    onQuit?()
                }
            } else {
                userDelegate?.draw(in: view)
            }
        }
    }
}

/// Bridges `NSWindowDelegate` so the owning ``Window`` can break out
/// of its run loop when the window is dismissed.
@MainActor
final class WindowAdapter: NSObject, NSWindowDelegate {
    var onClose: (@MainActor () -> Void)?

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            onClose?()
        }
    }
}
