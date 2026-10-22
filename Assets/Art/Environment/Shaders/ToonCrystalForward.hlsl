// Forward pass body of DSEWA/ToonCrystal, shared by the back-face pass (TOON_CRYSTAL_BACKFACE) and the front pass.
// Port of the Blender preview material in Art/Environment/scripts/crystal_shards.py (same order of layers):
// toon ramp (lit fades to tip colour with height) -> per-facet hue shift + saturation -> rim -> rainbow sheen ->
// core glow -> cut/edge glow, all scaled by a per-object glow pulse; then glossy reflection + light highlight with a
// Fresnel weight; alpha from Fresnel (glass: see-through face-on, solid at the edges). MatCap is a Unity-only extra.
#ifndef DSEWA_TOON_CRYSTAL_FORWARD_INCLUDED
#define DSEWA_TOON_CRYSTAL_FORWARD_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
#include "Assets/Art/Environment/Shaders/CloudShadow.hlsl"
#include "Assets/Art/Environment/Shaders/ToonShadow.hlsl"
#include "Assets/Art/Environment/Shaders/GroundFog.hlsl"   // same distance fog as ToonTerrain / ToonFoliage

TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
TEXTURE2D(_MatCap); SAMPLER(sampler_MatCap);
TEXTURE2D(_BrushTex); SAMPLER(sampler_BrushTex);

// painterly stroke value around 0 (-0.5..0.5): triplanar in world space, offset per object so neighbours differ
half BrushStroke(float3 positionWS, float3 N)
{
    float3 objPos = GetObjectToWorldMatrix()._m03_m13_m23;
    float3 p = positionWS * _BrushTiling + frac(sin(dot(objPos, float3(12.9898, 78.233, 37.719))) * float3(43758.5, 22578.1, 19642.3));
    float3 w = pow(abs(N), 4.0);
    w /= max(w.x + w.y + w.z, 1e-4);
    half b = SAMPLE_TEXTURE2D(_BrushTex, sampler_BrushTex, p.zy).r * w.x
           + SAMPLE_TEXTURE2D(_BrushTex, sampler_BrushTex, p.xz).r * w.y
           + SAMPLE_TEXTURE2D(_BrushTex, sampler_BrushTex, p.xy).r * w.z;
    return b - 0.5h;
}

// Base colour projected from the three object axes instead of the mesh UVs, for tileable materials (wood planks) on
// props whose UVs are auto-unwrapped: side faces get the texture upright (texture V = object up, so planks stand
// vertical), top / bottom faces get it from above. Object space, so it sticks to the prop when it moves; the import
// scale is baked into the mesh, so tiles per metre is real size.
half3 BoxMapBase(float3 posOS, float3 nOS)
{
    float3 w = pow(abs(normalize(nOS)), 4.0);
    w /= (w.x + w.y + w.z);
    float3 p = posOS * _BoxMapScale;
    half3 cx = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, p.zy).rgb;
    half3 cy = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, p.xz).rgb;
    half3 cz = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, p.xy).rgb;
    return cx * w.x + cy * w.y + cz * w.z;
}

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 color : COLOR;
    float2 uv : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
    float3 positionWS : TEXCOORD1;
    float3 normalWS : TEXCOORD2;
    half2 mask : TEXCOORD3;      // x = edge (R), y = cut face (G)
    half fogFactor : TEXCOORD4;
    float3 positionOS : TEXCOORD5;
    float3 normalOS : TEXCOORD6;
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

Varyings CrystalVert(Attributes input)
{
    Varyings o = (Varyings)0;
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
    VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
    o.positionCS = pos.positionCS;
    o.positionWS = pos.positionWS;
    o.normalWS = TransformObjectToWorldNormal(input.normalOS);
    o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
    o.positionOS = input.positionOS.xyz;
    o.normalOS = input.normalOS;
    o.mask = half2(input.color.r * _EdgeFromVertexColor, input.color.g * _CutFromVertexColor);
    o.fogFactor = ComputeFogFactor(pos.positionCS.z);
    return o;
}

// 0..1 position in the current beat; shared cell phase (see DSEWA/GlowPool)
float CrystalPulseCycle(float3 objPos)
{
    float3 key = _PulseCell > 0.01 ? float3(floor(objPos.xz / _PulseCell), 0).xzy : objPos;
    float phase = frac(sin(dot(key, float3(12.9898, 78.233, 37.719))) * 43758.5453);
    return frac(_Time.y / max(_PulsePeriod, 0.01) + phase);
}

// sphere-map lookup that stays stable toward the screen edges (reflected view ray, not the raw normal)
float2 MatCapUV(float3 positionWS, float3 normalWS)
{
    float3 viewPos = normalize(TransformWorldToView(positionWS));
    float3 viewN = normalize(TransformWorldToViewDir(normalWS));
    float3 r = reflect(viewPos, viewN);
    float m = 2.0 * sqrt(r.x * r.x + r.y * r.y + (r.z + 1.0) * (r.z + 1.0));
    return r.xy / max(m, 1e-4) + 0.5;
}

// 4-stop rainbow (pink -> blue -> mint -> yellow), the Blender SHEEN ramp
half3 Sheen(half t)
{
    half3 c = lerp(_Sheen0.rgb, _Sheen1.rgb, saturate(t / 0.35));
    c = lerp(c, _Sheen2.rgb, saturate((t - 0.35) / 0.35));
    return lerp(c, _Sheen3.rgb, saturate((t - 0.7) / 0.3));
}

half4 CrystalFrag(Varyings i, bool frontFace : SV_IsFrontFace) : SV_Target
{
    UNITY_SETUP_INSTANCE_ID(i);
    float3 smoothN = normalize(i.normalWS) * (frontFace ? 1 : -1);
    float3 facetN = normalize(cross(ddy(i.positionWS), ddx(i.positionWS)));
    facetN *= sign(dot(facetN, smoothN) + 1e-5);
    float3 N = normalize(lerp(smoothN, facetN, _FlatShading));
    float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
    float NdotV = saturate(dot(N, V));

    // height 0 (bottom of the renderer bounds) .. 1 (top)
    float span = max(unity_RendererBounds_Max.y - unity_RendererBounds_Min.y, 1e-3);
    float h01 = smoothstep(_GradientRange.x, _GradientRange.y, (i.positionWS.y - unity_RendererBounds_Min.y) / span);

    // toon ramp, lit colour base -> tip, shadow colour base -> darker tip
    Light light = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
    // self-lit crystals: cast and cloud shadows can be switched off so they keep their colour in shade
    half direct = lerp(1.0h, ToonMainLightShadow(i.positionWS, _ShadowBlur) * EvaluateCloudShadow(i.positionWS), _ReceiveShadows);
    float shade = saturate(dot(N, light.direction)) * direct + _AmbientShade;
    half brush = BrushStroke(i.positionWS, N);
    shade += brush * _BrushEdge;                 // the light/shadow border wanders like a painted edge
    float lit = smoothstep(_Threshold, _Threshold + _Softness, shade);
    half3 litC = lerp(_LitColor.rgb, _TipColor.rgb, h01);
    half3 shadowC = lerp(_ShadowColor.rgb, _TipColor.rgb * _TipShadow, h01);
    half3 base = _BoxMap > 0.5 ? BoxMapBase(i.positionOS, i.normalOS) : SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb;
    half3 color = lerp(shadowC, litC, lit) * base;

    // per-facet hue shift + saturation
    half3 hsv = RgbToHsv(color);
    hsv.x = frac(hsv.x + dot(facetN, float3(0.62, 0.7, -0.35)) * _HueShift + brush * _BrushHue);
    hsv.z = saturate(hsv.z * (1.0 + brush * 2.0 * _BrushValue));   // strokes of lighter / darker paint   // Unity is Y-up (Blender axis (x, z, -y))
    hsv.y = saturate(hsv.y * _Saturation);
    color = HsvToRgb(hsv);

    half3 cap = SAMPLE_TEXTURE2D(_MatCap, sampler_MatCap, MatCapUV(i.positionWS, N)).rgb;
    color += cap * _MatCapColor.rgb * _MatCapStrength * lerp(_MatCapInShadow, 1, lit);

    half graze = 1.0 - NdotV;
    color += _RimColor.rgb * smoothstep(_RimMin, _RimMax, graze) * _RimStrength;
    color += Sheen(graze) * pow(graze, _SheenPower) * _SheenStrength;
    color *= lerp(half3(1, 1, 1), light.color, _LightColorAmount);

    // glow pulse: one beat per ground cell (_PulseCell m; 0 = per object) so a cluster and the glow pool under it
    // breathe together; same formula as DSEWA/GlowPool
    float cycle = CrystalPulseCycle(GetObjectToWorldMatrix()._m03_m13_m23);
    float p01 = 0.5 + 0.5 * sin(cycle * TWO_PI);
    float glowK = lerp(_PulseGlow.x, _PulseGlow.y, p01);
    float baseK = lerp(_PulseBase.x, _PulseBase.y, p01);

    // radial light like the lantern fruit: from the foot of the crystal outward (0 = foot centre, 1 = crystal height)
    float3 foot = float3((unity_RendererBounds_Min.x + unity_RendererBounds_Max.x) * 0.5, unity_RendererBounds_Min.y,
                         (unity_RendererBounds_Min.z + unity_RendererBounds_Max.z) * 0.5);
    float d01 = distance(i.positionWS, foot) / span;
    float radial = pow(saturate(1.0 - d01 * 0.85), _RadialPower);
    // each beat a wave of light runs from the foot to the tip (first _WaveSpan of the cycle), fading as it goes
    float front = cycle / max(_WaveSpan, 0.05);
    float wave = front < 1.0 ? exp(-pow((d01 - front * 1.1) / max(_WaveWidth, 0.01), 2.0)) * (1.0 - front) : 0.0;

    half3 glow = _CoreColor.rgb * lerp(pow(NdotV, _CorePower), radial, _RadialMix) * _CoreStrength;
    glow += _CoreColor.rgb * wave * _WaveStrength;
    glow += _EdgeColor.rgb * i.mask.x * _EdgeStrength;
    glow += _CutColor.rgb * i.mask.y * _CutStrength;
    color = (color + glow * glowK) * baseK;
    // the glow covers most of the body, so the strokes are painted over it too (else they vanish under the light)
    color *= 1.0 + brush * 2.0 * _BrushValue;

    // texture glow: the brightest painted parts (patterns, petal rims) emit their own colour; not shadowed.
    // _TexGlowPulse breathes it with the same beat as the glow (min near 0 = lights up and goes out)
    half texLum = max(base.r, max(base.g, base.b));
    float texK = lerp(_TexGlowPulse.x, _TexGlowPulse.y, p01);
    color += base * _TexGlowTint.rgb * smoothstep(_TexGlowThreshold, _TexGlowThreshold + _TexGlowSoftness, texLum) * _TexGlowStrength * texK;

    // gloss: environment reflection (sky / probes) + sharp main-light highlight, Fresnel-weighted, tinted to the tip
    half fres = 0.03 + 0.97 * pow(1.0 - NdotV, 5.0);
    half glossW = _GlossFacing + _GlossGrazing * fres;
    half3 glossTint = lerp(half3(1, 1, 1), _TipColor.rgb, _GlossTint);
    half3 env = GlossyEnvironmentReflection(reflect(-V, N), i.positionWS, _GlossRoughness, 1.0);
    float3 H = normalize(light.direction + V);
    half spec = pow(saturate(dot(N, H)), 2.0 / max(_GlossRoughness * _GlossRoughness, 1e-3)) * _SpecStrength * direct;
    color += (env * glossW + light.color * spec) * glossTint;

    // the scene's ground fog (Unity fog is off here): far crystals melt into the horizon like the terrain and grass
    color = ApplyGroundFog(color, i.positionWS);
    color = MixFog(color, i.fogFactor);
    half alpha = lerp(_OpacityFacing, _OpacityGrazing, fres);
#ifdef TOON_CRYSTAL_BACKFACE
    alpha *= _BackFaceOpacity;
#endif
    return half4(color, alpha);
}

#endif
