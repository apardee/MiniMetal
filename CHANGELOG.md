# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-06-06

Initial release.

### Added
- `Window` — opens an `MTKView`-backed window without touching AppKit directly.
- `@MetalLayout` macro — mirrors a Swift struct's memory layout into an MSL
  `struct` declaration, with a runtime stride check.
- `#shader` macro — embeds MSL source, discovers `vertex` / `fragment` / `kernel`
  entry points, and prepends `@MetalLayout` declarations via `using:`.
- Convenience pipeline/encoder APIs on `MTLDevice` and `MTLRenderCommandEncoder`.
- Examples: `HelloWindow`, `HelloTriangle`, `SpinningCube`.

[0.1.0]: https://github.com/apardee/MiniMetal/releases/tag/0.1.0
