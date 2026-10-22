// DSEWA/ToonLakeWater: night lake landmark (2026-10-19), from the user's recipe notes:
//  - body colour by water depth: shore deep purple -> centre dark navy / black (depth = water level minus the height of
//    the ground behind the pixel, rebuilt from the depth texture), lit a little by the moon + sky ambient
//  - glints (윤슬) on the surface: fractal noise ("Musgrave", detail 2) mixed into the position at factor 0.05, then
//    Voronoi Smooth F1 (3D, third axis = time = W axis) cut with a constant ramp -> small glowing spots, neon purple or
//    emerald per cell, emission; W speed 0.08 / s = "#frame / 300" at 24 fps
//  - moonlight caustics only on the lake bed in the shallows: Voronoi F2 - F1 lines, position nudged by spherical
//    rings (wave, factor 0.03), projected on the ground behind the water, gone in deep water
//  - toon foam line at the shore. No reflection / refraction / PBR.
// Recipe values (0.05, 0.03, frame/300, detail 2, scales) are from the notes; colours, depths and widths are mine.
Shader "DSEWA/ToonLakeWater"
{
    Properties
    {
        [Header(Body)]
        _WaterLevel ("Water Level (world Y, set by LakeBuilder)", Float) = 0
        _ShoreColor ("Shore Color (deep purple)", Color) = (0.24, 0.12, 0.42, 1)
        _DeepColor ("Deep Color (navy / black)", Color) = (0.02, 0.03, 0.09, 1)
        _DepthMax ("Depth For Full Deep Color (m)", Range(0.1, 10)) = 2
        _AlphaShore ("Opacity At Shore", Range(0, 1)) = 0.55
        _AlphaDeep ("Opacity Deep", Range(0, 1)) = 0.96
        _ReceiveLight ("Receive Moon + Sky Light", Range(0, 1)) = 0.6
        [Header(Glints)]
        _GlintScale ("Glint Voronoi Scale (cells per metre)", Range(0.1, 10)) = 1.5
        _WarpScale ("Musgrave Scale (per metre)", Range(0.01, 2)) = 0.25
        _WarpMix ("Musgrave Mix Factor", Range(0, 0.3)) = 0.05
        _GlintSmooth ("Smooth F1 Smoothness", Range(0.01, 1)) = 0.6
        _GlintSize ("Glint Size (ramp cut)", Range(0, 1)) = 0.16
        _GlintColorA ("Glint Color A (neon purple)", Color) = (0.78, 0.55, 1, 1)
        _GlintColorB ("Glint Color B (emerald)", Color) = (0.45, 1, 0.82, 1)
        _GlintEmission ("Glint Emission", Range(0, 5)) = 1.6
        _WSpeed ("W Axis Speed (per second)", Range(0, 1)) = 0.08
        _GlintFadeDepth ("Glints Need This Much Depth (m)", Range(0, 2)) = 0.15
        _GlintSizeRandom ("Glint Size Random (per cell)", Range(0, 1)) = 0.7
        _GlintCluster ("Glint Clustering (Musgrave patches)", Range(0, 1)) = 0.6
        _GlintClusterScale ("Cluster Patch Scale (per metre)", Range(0.01, 1)) = 0.12
        [Header(Bed caustics in the shallows Designer mask double offset)]
        [NoScaleOffset] _CausticMap ("Caustic Mask (R, Designer)", 2D) = "black" {}
        _CausticTiling ("Caustic Tiles Per Metre", Range(0.02, 2)) = 0.25
        _CausticSpeed1 ("Set 1 Speed", Vector) = (0.03, 0.012, 0, 0)
        _CausticSpeed2 ("Set 2 Speed", Vector) = (-0.018, 0.024, 0, 0)
        _CausticGain ("Caustic Gain", Range(0.5, 5)) = 3
        _CausticScale ("Old Procedural Caustic Scale (unused)", Range(0.1, 10)) = 1.2
        _CausticTilingFine ("Fine Layer Tiles Per Metre", Range(0.1, 4)) = 0.9
        _CausticFineWeight ("Fine Layer Weight", Range(0, 2)) = 0.6
        _CausticFineNear ("Fine Layer Full Until (m from camera)", Range(0, 50)) = 6
        _CausticFineFar ("Fine Layer Gone At (m from camera)", Range(1, 150)) = 25
        _RingScale ("Ring Wave Scale (per metre)", Range(0.01, 2)) = 0.35
        _RingMix ("Ring Mix Factor", Range(0, 0.3)) = 0.03
        _RingCenter ("Ring Centre (world XZ)", Vector) = (0, 0, 0, 0)
        _CausticWidth ("Caustic Line Width", Range(0.001, 0.3)) = 0.06
        _CausticColor ("Caustic Color", Color) = (0.62, 0.9, 1, 1)
        _CausticStrength ("Caustic Strength", Range(0, 3)) = 0.7
        _CausticDepth ("Caustics Fade By Depth (m)", Range(0.05, 5)) = 1.6
        _CausticFadeIn ("Caustics Fade In From Waterline (m)", Range(0.001, 1)) = 0.12
        _CausticFadePower ("Caustic Fade Curve", Range(0.5, 4)) = 1.8
        _CausticPatch ("Caustic Patchiness (slow noise)", Range(0, 1)) = 0.55
        [Header(Shore foam)]
        _FoamColor ("Foam Color", Color) = (0.82, 0.78, 1, 1)
        _FoamWidth ("Foam Width (m of depth)", Range(0.001, 0.5)) = 0.06
        _FoamEmission ("Foam Self Glow", Range(0, 2)) = 0.35
        _FoamBreath ("Foam Width Breathing (noise)", Range(0, 1)) = 0.6
        _FoamWaves ("Rolling Wave Lines (0 off, 1 on)", Range(0, 1)) = 1
        _RimStrength ("Rim Strength (0 = no shore line)", Range(0, 1)) = 1
        _RimGlowMin ("Rim Glow Breathing Min", Range(0, 2)) = 0.5
        _RimGlowMax ("Rim Glow Breathing Max", Range(0, 3)) = 1.4
        _RimGlowPeriod ("Rim Glow Period (s)", Range(1, 20)) = 6
        _FoamWaveReach ("Wave Line Reach (m of depth)", Range(0.01, 1)) = 0.22
        _FoamWaveSpeed ("Wave Lines Per Second", Range(0, 1)) = 0.18
        _FoamWaveWidth ("Wave Line Width (m of depth)", Range(0.001, 0.1)) = 0.018
        _FoamWaveBreak ("Wave Line Gaps", Range(0, 1)) = 0.4
        _DebugTime ("Debug Fixed Time (-1 = live)", Float) = -1
        [Header(Depth cues)]
        _SkyColor ("Sky Color Seen At Grazing Angles", Color) = (0.2, 0.18, 0.4, 1)
        _FresnelStrength ("Fresnel Sky Strength", Range(0, 1)) = 0.7
        _FresnelPower ("Fresnel Power", Range(1, 10)) = 4
        _Parallax ("Bed Parallax (refraction-ish)", Range(0, 1)) = 0.35
        _Refraction ("Screen Refraction Of The Bed (UV)", Range(0, 0.05)) = 0.012
        _BankShade ("Underwater Bank Darkening (steep bed)", Range(0, 1)) = 0.5
        _BedShadow ("Moon Shadows On Bed Caustics", Range(0, 1)) = 1
        [Header(Moon path)]
        _PathStrength ("Moon Path Strength", Range(0, 3)) = 1
        _PathPower ("Moon Path Tightness", Range(2, 400)) = 60
        _PathWobble ("Moon Path Ripple Breakup", Range(0, 0.5)) = 0.18
        _PathColor ("Moon Path Color", Color) = (0.75, 0.7, 1, 1)
        _PathGlintBoost ("Glints Grow In The Path", Range(0, 3)) = 1.5
        _PathCustom ("Use Custom Path Direction (0 = main light)", Range(0, 1)) = 0
        _PathDir ("Custom Direction To Moon (world)", Vector) = (0, 0.3, -1, 0)
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent-40" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _SkyColor, _PathColor;
                float _Refraction;
                float _FresnelStrength, _FresnelPower, _Parallax, _BankShade, _BedShadow;
                float _PathStrength, _PathPower, _PathWobble, _PathGlintBoost, _PathCustom;
                float4 _PathDir;
                float _WaterLevel, _DepthMax, _GlintScale, _WarpScale, _WarpMix, _GlintSmooth, _GlintSize, _WSpeed, _GlintFadeDepth;
                float _CausticScale, _RingScale, _RingMix, _CausticWidth, _CausticDepth, _FoamWidth;
                float4 _RingCenter;
                half4 _ShoreColor, _DeepColor, _GlintColorA, _GlintColorB, _CausticColor, _FoamColor;
                half _AlphaShore, _AlphaDeep, _ReceiveLight, _GlintEmission, _CausticStrength, _FoamEmission;
                float _GlintSizeRandom, _GlintCluster, _GlintClusterScale, _CausticTiling, _CausticGain;
                float4 _CausticSpeed1, _CausticSpeed2;
                float _CausticFadeIn, _CausticFadePower, _CausticPatch;
                float _CausticTilingFine, _CausticFineWeight, _CausticFineNear, _CausticFineFar;
                float _FoamBreath, _FoamWaveReach, _FoamWaveSpeed, _FoamWaveWidth, _FoamWaveBreak, _DebugTime;
                float _FoamWaves, _RimGlowMin, _RimGlowMax, _RimGlowPeriod, _RimStrength;
            CBUFFER_END
            TEXTURE2D(_CausticMap); SAMPLER(sampler_CausticMap);
            #include "Assets/Art/Environment/Shaders/ToonCaustic.hlsl"

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 positionWS : TEXCOORD0; half fogFactor : TEXCOORD1; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs p = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = p.positionCS; o.positionWS = p.positionWS; o.fogFactor = ComputeFogFactor(p.positionCS.z);
                return o;
            }

            float3 Hash33(float3 p)
            {
                p = float3(dot(p, float3(127.1, 311.7, 74.7)), dot(p, float3(269.5, 183.3, 246.1)), dot(p, float3(113.5, 271.9, 124.6)));
                return frac(sin(p) * 43758.5453123);
            }
            // gradient-ish value noise 3D and a 3-octave fBm (Musgrave fBm, detail 2 = 1 + 2 octaves)
            float Noise3(float3 p)
            {
                float3 i = floor(p), f = frac(p); f = f * f * (3 - 2 * f);
                float n000 = Hash33(i).x, n100 = Hash33(i + float3(1,0,0)).x, n010 = Hash33(i + float3(0,1,0)).x, n110 = Hash33(i + float3(1,1,0)).x;
                float n001 = Hash33(i + float3(0,0,1)).x, n101 = Hash33(i + float3(1,0,1)).x, n011 = Hash33(i + float3(0,1,1)).x, n111 = Hash33(i + float3(1,1,1)).x;
                return lerp(lerp(lerp(n000, n100, f.x), lerp(n010, n110, f.x), f.y), lerp(lerp(n001, n101, f.x), lerp(n011, n111, f.x), f.y), f.z);
            }
            float Musgrave(float3 p)
            {
                float v = 0, a = 1, s = 0;
                [unroll] for (int k = 0; k < 3; k++) { v += a * (Noise3(p) * 2 - 1); s += a; p *= 2.0; a *= 0.5; }
                return v / s;
            }
            // 3D Voronoi: x = smooth F1 (exponential smooth min), y = F1, z = F2, w = random of the nearest cell
            float4 Voronoi3(float3 p, float smoothness)
            {
                float3 i = floor(p), f = frac(p);
                float f1 = 8, f2 = 8, sm = 0, id = 0; float k = 1.0 / max(smoothness * 0.25, 1e-3);
                [unroll] for (int z = -1; z <= 1; z++) [unroll] for (int y = -1; y <= 1; y++) [unroll] for (int x = -1; x <= 1; x++)
                {
                    float3 g = float3(x, y, z); float3 h = Hash33(i + g);
                    float d = length(g + h - f);
                    sm += exp(-k * d);
                    // cell id from a separate hash: h.z is the point's position on the time axis, so only points
                    // with h.z near the current time are close enough to glint -> using it as id made every
                    // visible glint the same colour (and they all flipped colour together over time)
                    if (d < f1) { f2 = f1; f1 = d; id = Hash33(i + g + 17.17).x; } else if (d < f2) { f2 = d; }
                }
                return float4(-log(max(sm, 1e-6)) / k, f1, f2, id);
            }

            half4 frag(Varyings i) : SV_Target
            {
                float t = _DebugTime >= 0 ? _DebugTime : _Time.y;
                // ground behind the pixel, from the depth texture
                float2 suv = GetNormalizedScreenSpaceUV(i.positionCS);
                float rawD = SampleSceneDepth(suv);
                float3 behind = ComputeWorldSpacePosition(suv, rawD, UNITY_MATRIX_I_VP);
                float depthV = max(0, _WaterLevel - behind.y);          // vertical water depth over that ground

                half3 sceneLight = lerp(half3(1, 1, 1), GetMainLight().color * saturate(GetMainLight().direction.y) + SampleSH(half3(0, 1, 0)), _ReceiveLight);
                half dd = saturate(depthV / _DepthMax);
                half3 col = lerp(_ShoreColor.rgb, _DeepColor.rgb, smoothstep(0, 1, dd)) * sceneLight;
                half alpha = lerp(_AlphaShore, _AlphaDeep, dd);
                float3 V = normalize(_WorldSpaceCameraPos - i.positionWS);

                // underwater bank shading: steep bed (from the depth-rebuilt position's screen derivatives) darker
                float3 nBed = normalize(cross(ddy(behind), ddx(behind)));
                nBed *= sign(nBed.y + 1e-5);
                half steep = 1 - saturate(nBed.y);
                col *= 1 - _BankShade * saturate(steep * 2.5) * smoothstep(0, 0.3, depthV);

                // bed caustics (shallows only): the Designer caustic mask (tutorial graph: cells > distance > levels >
                // directional warp > blur add) read twice with the double offset + min, on the ground position,
                // nudged outward by spherical rings around the lake centre (recipe mix 0.03)
                float2 rel = behind.xz - _RingCenter.xz;
                float ring = sin(length(rel) * _RingScale * 6.2831853 - t * 0.6);
                float2 bedXZ = behind.xz + normalize(rel + 1e-4) * ring * _RingMix / max(_CausticTiling, 1e-3);
                // the caustics already sit on the real bed (true parallax); refraction makes the bed look shallower,
                // i.e. shifted toward the viewer by depth / view slope
                bedXZ += V.xz / max(V.y, 0.25) * depthV * _Parallax;
                half causticLarge = DoubleOffsetCaustic(TEXTURE2D_ARGS(_CausticMap, sampler_CausticMap), bedXZ, _CausticTiling,
                    t, _CausticSpeed1.xy, _CausticSpeed2.xy, 1.1, _CausticGain);
                // two densities: a fine layer (own tiling, rotated drift, offset) adds small ripples, strongest
                // inside the big light lines; it fades out with camera distance (the tiling itself never changes
                // with distance, which would make the pattern slide while the camera moves)
                float camDist = distance(_WorldSpaceCameraPos, behind);
                half fineFade = 1 - smoothstep(_CausticFineNear, _CausticFineFar, camDist);
                half causticFine = 0;
                UNITY_BRANCH if (fineFade > 0.001)
                    causticFine = DoubleOffsetCaustic(TEXTURE2D_ARGS(_CausticMap, sampler_CausticMap), bedXZ + 13.7, _CausticTilingFine,
                        t, _CausticSpeed1.yx * float2(-1.3, 1.1), _CausticSpeed2.yx * float2(1.2, -1.4), 1.13, _CausticGain);
                half causticLine = saturate(causticLarge + causticFine * _CausticFineWeight * fineFade * (0.35 + 0.65 * causticLarge));
                // soft gradient: appears just off the waterline, long curved fade into the deep, and slow noise
                // patches so it never reads as an even band around the shore
                half fadeOut = pow(saturate(1 - depthV / _CausticDepth), _CausticFadePower);
                half fadeIn = smoothstep(0, _CausticFadeIn, depthV);
                half patchC = lerp(1, smoothstep(0.25, 0.75, Noise3(float3(behind.xz * 0.08, t * 0.03))), _CausticPatch);
                half shallow = fadeOut * fadeIn * patchC;
                // moon shadows (crystals, props) fall on the bed caustics
                half bedShadow = MainLightRealtimeShadow(TransformWorldToShadowCoord(behind));
                causticLine *= lerp(1, bedShadow, _BedShadow);
                col += _CausticColor.rgb * causticLine * shallow * _CausticStrength * sceneLight;

                // fresnel: grazing angles show the sky colour, looking down shows the water body / bed
                half fres = pow(1 - saturate(V.y), _FresnelPower) * _FresnelStrength;
                col = lerp(col, _SkyColor.rgb, fres);
                alpha = lerp(alpha, 1, fres);

                // moon path: the reflection of the moon (main light, or a custom direction) on a rippled surface;
                // a soft streak plus bigger glints inside it
                float3 Lm = _PathCustom > 0.5 ? normalize(_PathDir.xyz) : GetMainLight().direction;
                float2 wob = float2(Noise3(float3(i.positionWS.xz * 0.8, t * 0.3)), Noise3(float3(i.positionWS.xz * 0.8 + 5.3, t * 0.3))) - 0.5;
                float3 Np = normalize(float3(wob.x * _PathWobble * 2, 1, wob.y * _PathWobble * 2));
                half path = pow(saturate(dot(reflect(-V, Np), Lm)), _PathPower) * step(0, Lm.y);
                col += _PathColor.rgb * path * _PathStrength * 0.35;
                alpha = max(alpha, saturate(path * _PathStrength * 0.35));

                // glints on the surface: Musgrave-warped Smooth F1, constant ramp cut
                float3 gp = float3(i.positionWS.xz * _GlintScale, t * _WSpeed);
                float m = Musgrave(float3(i.positionWS.xz * _WarpScale, t * _WSpeed * 0.5));
                gp = lerp(gp, gp + m * 4, _WarpMix);
                float4 gv = Voronoi3(gp, _GlintSmooth);
                // per-cell size, glints gathered in slow Musgrave patches, soft (pixel-wide) ramp edge, and fewer /
                // dimmer glints where a cell gets smaller than a few pixels (far away), instead of shimmering dashes
                float cellR = frac(gv.w * 7.31);
                float patch = Musgrave(float3(i.positionWS.xz * _GlintClusterScale, t * _WSpeed * 0.3)) * 0.5 + 0.5;
                float sizeMul = lerp(1, lerp(0.3, 1.3, cellR), _GlintSizeRandom) * lerp(1, smoothstep(0.35, 0.75, patch) * 1.4, _GlintCluster);
                float cut = _GlintSize * sizeMul * (1 + path * _PathGlintBoost);
                float aa = max(fwidth(gv.x), 1e-4);
                float cellPx = 1.0 / max(length(fwidth(gp.xy)), 1e-4);    // cell size in pixels
                half glint = (1 - smoothstep(cut - aa, cut + aa, gv.x)) * smoothstep(3, 10, cellPx) * smoothstep(0, _GlintFadeDepth, depthV);
                half3 gcol = lerp(_GlintColorA.rgb, _GlintColorB.rgb, step(0.5, gv.w));
                col = lerp(col, gcol * sceneLight, glint) + gcol * glint * _GlintEmission;
                alpha = max(alpha, glint);

                // shore foam, moving: the edge band breathes with slow noise, and toon wave lines roll in from
                // _FoamWaveReach (in water depth) to the shore, broken into pieces by noise
                float2 sp = i.positionWS.xz;
                float nb = Noise3(float3(sp * 0.45, t * 0.22));
                // at least ~1.2 px wide on screen so the thin rim doesn't break into dashes far away
                float rimW = max(_FoamWidth * lerp(1, lerp(0.4, 1.6, nb), _FoamBreath), fwidth(depthV) * 1.2);
                half foam = 1 - step(rimW, depthV);
                float phase0 = Noise3(float3(sp * 0.07, 3.1)) * 0.8;
                half gaps = step(_FoamWaveBreak, Noise3(float3(sp * 0.6, t * 0.15 + 7.7)));
                [unroll] for (int w = 0; w < 2; w++)      // two lines half a cycle apart, so one is always travelling
                {
                    // waves roll IN: each line starts out in the water (faint, thin), moves toward the shore,
                    // gets stronger and thicker as it arrives and merges into the edge band
                    float phase = frac(t * _FoamWaveSpeed + phase0 + w * 0.5);
                    float waveD = _FoamWidth + (1 - phase) * _FoamWaveReach;
                    half wave = 1 - step(_FoamWaveWidth * lerp(0.4, 1, phase), abs(depthV - waveD));
                    foam = max(foam, wave * phase * gaps * step(0.15, phase) * _FoamWaves);
                }
                // rim glow breathes slowly, each stretch of shore a little out of step (light drifting along it)
                float breath = sin((t / _RimGlowPeriod + Noise3(float3(sp * 0.05, 1.7)) * 1.5) * 6.2831853) * 0.5 + 0.5;
                half rimGlow = _FoamEmission * lerp(_RimGlowMin, _RimGlowMax, breath);
                foam *= _RimStrength;
                col = lerp(col, _FoamColor.rgb * sceneLight + _FoamColor.rgb * rimGlow, foam);
                alpha = lerp(alpha, 0.95, foam);

                // see-through part refracted: composite the (slightly bent) scene behind ourselves and output opaque,
                // so the shallow bed wobbles with the surface; deeper water hides it anyway (alpha)
                float2 rUV = suv + (float2(Noise3(float3(i.positionWS.xz * 1.3, t * 0.4)), Noise3(float3(i.positionWS.xz * 1.3 + 9.1, t * 0.4))) - 0.5)
                             * _Refraction * saturate(depthV * 3);
                half3 behindCol = SampleSceneColor(rUV) * lerp(half3(1, 1, 1), _ShoreColor.rgb * 1.6, 0.4);
                col = lerp(behindCol, col, alpha);
                return half4(MixFog(col, i.fogFactor), 1);
            }
            ENDHLSL
        }
    }
}
