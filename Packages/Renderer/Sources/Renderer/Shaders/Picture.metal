// Draws one emulated picture at a whole-number scale (ADR 0005, section 5).
//
// The viewport covers the visible part of the scaled picture; one triangle
// covers the viewport. Each fragment reads exactly one texel with read() at
// integer coordinates, so no sampler and no filtering is involved and every
// drawable pixel shows its source pixel unchanged.

#include <metal_stdlib>
using namespace metal;

// Matches PictureUniforms in PictureRenderer.swift.
struct PictureUniforms {
    int2 origin;   // top left of the scaled picture in drawable pixels, may be negative
    int scale;     // whole-number factor, at least 1
};

vertex float4 picture_vertex(uint id [[vertex_id]]) {
    float2 corner = float2((id << 1) & 2, id & 2);
    return float4(corner * 2.0 - 1.0, 0.0, 1.0);
}

static uint2 picture_texel(float4 position, constant PictureUniforms &uniforms) {
    int2 pixel = int2(position.xy) - uniforms.origin;
    return uint2(pixel / uniforms.scale);
}

// RGB565 in an r16Uint texture: red in bits 15-11, green in 10-5, blue in 4-0.
// b5g6r5Unorm would decode this in hardware, but the Simulator does not support it.
fragment float4 picture_rgb565(float4 position [[position]],
                               texture2d<ushort, access::read> picture [[texture(0)]],
                               constant PictureUniforms &uniforms [[buffer(0)]]) {
    uint value = picture.read(picture_texel(position, uniforms)).r;
    float3 rgb = float3((value >> 11) & 31, (value >> 5) & 63, value & 31) / float3(31.0, 63.0, 31.0);
    return float4(rgb, 1.0);
}

// XRGB8888 in a bgra8Unorm texture: in memory blue, green, red, unused.
fragment float4 picture_xrgb8888(float4 position [[position]],
                                 texture2d<float, access::read> picture [[texture(0)]],
                                 constant PictureUniforms &uniforms [[buffer(0)]]) {
    return float4(picture.read(picture_texel(position, uniforms)).rgb, 1.0);
}
