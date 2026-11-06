// Renderer presents what a core produces (docs/PLAN.md, section 5).
//
// Picture: software cores deliver a pixel buffer (RGB565 or XRGB8888) that is
// drawn as a Metal texture at whole-number scale factors. GPU cores (PSP, PS2)
// get a hardware render context, see ADR 0001.
// Sound: samples go into a lock-free ring buffer played by an AVAudioSourceNode,
// with light dynamic resampling against clock drift.
// The first implementation arrives with the GBA in M1. Until then the module is empty.
