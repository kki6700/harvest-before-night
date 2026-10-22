// Shared caustic sampling for the pool shaders (same idea as ToonPuddle flow mode 2, the Shader Graph tutorial
// "double offset"): one caustic mask read twice with Tiling & Offset sets moving in different directions, set 2 with
// a tiling multiplier and a fixed offset so the two never line up again, combined with min (only where both nets
// overlap), then gained. Needs TEXTURE2D(_CausticMap) + sampler declared by the including shader.
#ifndef DSEWA_TOON_CAUSTIC_INCLUDED
#define DSEWA_TOON_CAUSTIC_INCLUDED

float DoubleOffsetCaustic(TEXTURE2D_PARAM(tex, samp), float2 p, float tiling, float t,
                          float2 speed1, float2 speed2, float tiling2, float gain)
{
    float2 b = p * tiling;
    float m1 = SAMPLE_TEXTURE2D(tex, samp, b + t * speed1).r;
    float m2 = SAMPLE_TEXTURE2D(tex, samp, b * tiling2 + t * speed2 + 0.37).r;
    return saturate(min(m1, m2) * gain);
}

// world-space projection that works on floor and walls: floor reads xz, walls read the plane they face
float TriplanarCaustic(TEXTURE2D_PARAM(tex, samp), float3 pw, float3 n, float tiling, float t,
                       float2 speed1, float2 speed2, float tiling2, float gain)
{
    float3 w = pow(abs(n), 4);
    w /= (w.x + w.y + w.z);
    float cy = DoubleOffsetCaustic(TEXTURE2D_ARGS(tex, samp), pw.xz, tiling, t, speed1, speed2, tiling2, gain);
    float cx = DoubleOffsetCaustic(TEXTURE2D_ARGS(tex, samp), pw.zy, tiling, t, speed1, speed2, tiling2, gain);
    float cz = DoubleOffsetCaustic(TEXTURE2D_ARGS(tex, samp), pw.xy, tiling, t, speed1, speed2, tiling2, gain);
    return cx * w.x + cy * w.y + cz * w.z;
}
#endif
