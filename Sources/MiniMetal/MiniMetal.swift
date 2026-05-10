// MiniMetal is a macOS package that allows simple Swift executable packages
// to initialize a window and MTKView for rendering demos. It eliminates the
// boilerplate involved with setting up windows, views, delegates, etc. so
// that the user can focus on rendering content. It is loosely modeled off
// of the C++ SDL interface.
//
// Quick start:
//
//     import MiniMetal
//
//     let window = try Window(
//         title: "Test Renderer",
//         resolution: .init(width: 640, height: 480))
//
//     await window.show { view in
//         // ...issue Metal draw commands against `view`...
//         return .continue
//     }
//
// See ``Window`` for the full API.
