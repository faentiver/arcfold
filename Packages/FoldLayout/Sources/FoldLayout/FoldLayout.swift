// FoldLayout turns the device posture and the fold rectangle into the rectangles
// for the picture and the controls of each system (docs/PLAN.md, sections 5 and 7).
//
// It reads `onHingeChange` and `reservedRegions(kind: .division)`, which need
// iOS 27.1, and animates layout changes while the emulation keeps running.
// The first layouts arrive with the DS in M2. Until then the module is empty.
