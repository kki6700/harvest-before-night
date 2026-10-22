// Cloud shadow — port of SurvivalKit's sun Light Function MM_CloudShadow / MI_CloudShadow
// (stylized-shading-research, SurvivalKit_Shader_Analysis_KO "하늘 구체와 구름").
// World XZ sampled at two sizes, panned, mixed, SmoothStep(Levels Min, Max), then Lerp(1, mask, Opacity).
// Research values: tiling 830.007629 / 1675.230957 UE units (cm) -> 8.300 / 16.752 m, Speed -0.005,
// Levels 0.292 / 0.762758, Opacity 1.675799 (> 1 extrapolates, clamped to 0..1 like a light value).
// The original noise texture is not in the clone: value noise stands in, and the two samples are averaged.
// Multiply it into the main light's DIRECT term only — never BaseColor or ambient (research rule).
// Globals come from CloudShadowSettings.cs; _DSEWA_CloudShadowTiling.x == 0 means off (returns 1).
#ifndef DSEWA_CLOUD_SHADOW_INCLUDED
#define DSEWA_CLOUD_SHADOW_INCLUDED

float4 _DSEWA_CloudShadowTiling;   // x = size A (m), y = size B (m), z = pan speed (UV per second), w = opacity
float4 _DSEWA_CloudShadowLevels;   // x = SmoothStep min, y = max
float4 _DSEWA_CloudShadowTweak;    // my controls on top of the research values: x = coverage offset (+ = fewer shadows),
                                   // y = strength (0 = no shadow, 1 = research result). Unset (0, 0) = research as-is

float CloudShadowHash(float2 p)
{
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

float CloudShadowNoise(float2 p)
{
    float2 i = floor(p), f = frac(p);
    f = f * f * (3 - 2 * f);
    return lerp(lerp(CloudShadowHash(i), CloudShadowHash(i + float2(1, 0)), f.x),
                lerp(CloudShadowHash(i + float2(0, 1)), CloudShadowHash(i + float2(1, 1)), f.x), f.y);
}

half EvaluateCloudShadow(float3 positionWS)
{
    if (_DSEWA_CloudShadowTiling.x <= 0) return 1;
    float pan = _Time.y * _DSEWA_CloudShadowTiling.z;
    float a = CloudShadowNoise(positionWS.xz / _DSEWA_CloudShadowTiling.x + pan);
    float b = CloudShadowNoise(positionWS.xz / _DSEWA_CloudShadowTiling.y + pan);
    float mask = smoothstep(_DSEWA_CloudShadowLevels.x, _DSEWA_CloudShadowLevels.y, (a + b) * 0.5 + _DSEWA_CloudShadowTweak.x);
    half light = saturate(lerp(1, mask, _DSEWA_CloudShadowTiling.w));
    half strength = _DSEWA_CloudShadowTweak.y > 0 ? _DSEWA_CloudShadowTweak.y : 1;
    return lerp(1, light, strength);
}
#endif
