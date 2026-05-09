// Smallest viable MiniMetal example: open a window and clear it to a solid
// color every frame.

import Metal
import MiniMetal

@main
struct HelloWindow {

    static func main() async throws {
        let window = try Window(
            title: "MiniMetal — Hello Window",
            resolution: .init(width: 1024, height: 768))
        window.view.clearColor = MTLClearColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0)

        // The render pass descriptor's load action clears the drawable to
        // `clearColor` — opening an encoder and immediately letting `Frame`
        // finish triggers the clear without issuing any draw calls.
        await window.show { (_: Frame) in .continue }
    }
}
