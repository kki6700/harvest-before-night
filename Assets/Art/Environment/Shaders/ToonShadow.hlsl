#ifndef DSEWA_TOON_SHADOW_INCLUDED
#define DSEWA_TOON_SHADOW_INCLUDED

// Smooth-contoured main light shadow for toon shading.
// URP's shadow filter is only ~1 texel wide; the toon step (smoothstep over a narrow band) then turns that thin
// gradient back into a hard line that follows the shadow map's texel staircase. Here the shadow map is read with
// a 12-tap Poisson disk of radius blurTexels (each tap a hardware 2x2 compare), so the averaged field is smooth
// over several texels and its iso-line - where the toon step cuts it - becomes a round curve. The edge stays crisp
// because the field is cut at 0.5 with a one-pixel step; only its shape changes. blurTexels <= 0 falls back to URP.
// Include after Lighting.hlsl; needs the _MAIN_LIGHT_SHADOWS(_CASCADE) keywords the forward pass already has.

static const float2 kToonShadowDisk[12] =
{
    float2(-0.326, -0.406), float2(-0.840, -0.074), float2(-0.696,  0.457), float2(-0.203,  0.621),
    float2( 0.962, -0.195), float2( 0.473, -0.480), float2( 0.519,  0.767), float2( 0.185, -0.893),
    float2( 0.507,  0.064), float2( 0.896,  0.412), float2(-0.322, -0.933), float2(-0.792, -0.598)
};

half ToonMainLightShadow(float3 positionWS, half blurTexels)
{
    // Single exit: early returns before the fwidth() below made FXC flag the result as "potentially
    // uninitialized" (X4000) once the branches are flattened around the derivative.
    half result = 1;
#if defined(_MAIN_LIGHT_SHADOWS) || defined(_MAIN_LIGHT_SHADOWS_CASCADE) || defined(_MAIN_LIGHT_SHADOWS_SCREEN)
    float4 coord = TransformWorldToShadowCoord(positionWS);
    if (blurTexels <= 0.01)
    {
        result = GetMainLight(coord).shadowAttenuation;
    }
    else if (coord.z > 0.0 && coord.z < 1.0)   // inside the shadow far plane
    {
        float2 radius = _MainLightShadowmapSize.xy * blurTexels;
        half s = 0;
        UNITY_UNROLL
        for (int k = 0; k < 12; k++)
            s += SAMPLE_TEXTURE2D_SHADOW(_MainLightShadowmapTexture, sampler_LinearClampCompare,
                                         float3(coord.xy + kToonShadowDisk[k] * radius, coord.z));
        s *= 1.0 / 12.0;
        // cut the smooth field at its middle with a one-pixel anti-aliased step: round contour, crisp toon edge,
        // independent of the material's lighting threshold (which would otherwise cut the soft ramp at its foot)
        half aa = max(fwidth(s), 1e-3);
        s = smoothstep(0.5 - aa, 0.5 + aa, s);

        s = LerpWhiteTo(s, GetMainLightShadowParams().x);        // light's shadow strength
        result = lerp(s, 1, GetMainLightShadowFade(positionWS)); // fade out towards the shadow distance
    }
#endif
    return result;
}

// ---------------------------------------------------------------- character shadow (CharacterShadow.cs)
// Characters cast only into their own tightly fitted map; only the environment calls this (no character self-shadow).
TEXTURE2D_FLOAT(_DSEWA_CharShadowMap); SAMPLER(sampler_DSEWA_CharShadowMap);   // point / clamp from the RT
float4x4 _DSEWA_CharShadowView;    // world -> light space (+z along the light)
float4 _DSEWA_CharShadowRect;      // light-space (minX, minY, 1/sizeX, 1/sizeY)
float4 _DSEWA_CharShadowParams;    // (on, texel uv, depth bias m, shadow strength)

half ToonCharacterShadow(float3 positionWS, half blurTexels)
{
    half result = 1;
    float3 lv = mul(_DSEWA_CharShadowView, float4(positionWS, 1)).xyz;
    float2 uv = (lv.xy - _DSEWA_CharShadowRect.xy) * _DSEWA_CharShadowRect.zw;
    if (_DSEWA_CharShadowParams.x >= 0.5 && all(uv == saturate(uv)))
    {
        float2 radius = _DSEWA_CharShadowParams.yy * max(blurTexels, 0.5) * 2;   // map texels are tiny: a wider disk
        float depth = lv.z - _DSEWA_CharShadowParams.z;
        half s = 0;
        UNITY_UNROLL
        for (int k = 0; k < 12; k++)
        {
            float occluder = SAMPLE_TEXTURE2D_LOD(_DSEWA_CharShadowMap, sampler_DSEWA_CharShadowMap, uv + kToonShadowDisk[k] * radius, 0).r;
            s += depth > occluder ? 0 : 1;
        }
        s *= 1.0 / 12.0;
        half aa = max(fwidth(s), 1e-3);
        s = smoothstep(0.5 - aa, 0.5 + aa, s);
        result = LerpWhiteTo(s, _DSEWA_CharShadowParams.w);
    }
    return result;
}

#endif
