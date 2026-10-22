// DSEWA/ToonPuddle: a rain puddle lying on the ground (mesh built by PuddleSurface.cs, conformed to the terrain).
//   - shape: irregular blob in the mesh UV (-1..1), different per puddle (seed from the object position)
//   - wet ground ring around the water that just darkens the terrain
//   - water: screen-space reflection of the scene (ray march on the depth texture, sampled from the opaque texture),
//     falling back to the sky / reflection probe where the ray finds nothing; deep colour seen straight down,
//     more reflection at grazing angles
//   - light wind ripples, a bright edge line and two painted glint streaks for the toon look
// Composition 1 (toon, 2026-10-19): flat water colour body; caustic = saturate(smoothstep(sharp R) + glow G * intensity)
// lerps the body to the highlight colour and adds highlight * caustic * emission; the caustic never touches alpha.
// One caustic layer by default (the second rotated layer is what made the doubled net). Composition 0 = the old look.
// Ripple map: T_PuddleCaustic (Designer PoolCaustics_B: R = sharp caustic mask, G = soft glow used as height),
// tiled 0.7 per metre. Older map T_PuddleRipple (liquid noise -> make_ripple.py) kept, works at 0.35.
// SSR ray march ported from the URP Moon sample (URPMoon_Env/Shaders/URPWater/HLSL/Water.hlsl, Raymarch_half +
// OutOfBoundsFade; graph values steps 12, step size 0.2 growing x1.5 per step, thickness 1) and its normal strength
// 0.145. Everything else (colours, widths, ripple and glint values) is my own.
Shader "DSEWA/ToonPuddle"
{
    Properties
    {
        [Header(Shape)]
        _WaterRadius ("Water Radius (0-1 of mesh)", Range(0.2, 1)) = 0.72
        _Irregularity ("Edge Irregularity", Range(0, 0.5)) = 0.22
        _WetWidth ("Wet Ground Ring Width", Range(0, 0.5)) = 0.2
        _WetDarken ("Wet Ground Darkening", Range(0, 1)) = 0.35
        _EdgeSoftness ("Water Edge Softness", Range(0.001, 0.1)) = 0.015
        [Header(Water)]
        _DeepColor ("Deep Color (looking straight down)", Color) = (0.06, 0.14, 0.18, 1)
        _ReflectionTint ("Reflection Tint", Color) = (0.85, 0.95, 1, 1)
        _ReflectMin ("Reflection Straight Down", Range(0, 1)) = 0.45
        _ReflectMax ("Reflection At Grazing Angles", Range(0, 1)) = 0.95
        _SkyReflection ("Sky Fallback Strength", Range(0, 2)) = 0.55
        _Alpha ("Water Opacity", Range(0, 1)) = 0.92
        [Header(Ripples Designer liquid noise Art Materials PuddleRipples)]
        [NoScaleOffset] _RippleMap ("Ripple Map (R caustic lines, G height)", 2D) = "black" {}
        _RippleScale ("Ripple Map Tiles Per Metre", Range(0.05, 3)) = 0.35
        _RippleSpeed ("Ripple Speed", Range(0, 2)) = 0.5
        _NormalStrength ("Ripple Strength", Range(0, 0.5)) = 0.145
        _CausticColor ("Line Color", Color) = (0.7, 0.95, 1, 1)
        _CausticStrength ("Line Strength", Range(0, 2)) = 0.7
        [Header(Toon Water flat body plus caustic highlight used when Composition is 1)]
        _ToonMode ("Composition (0 legacy reflection, 1 toon)", Range(0, 1)) = 1
        _WaterColor ("Water Color", Color) = (0.098, 0.722, 0.816, 1)
        _HighlightColor ("Highlight Color", Color) = (0.71, 0.973, 1, 1)
        _ToonReflection ("Reflection Mix In Toon Mode", Range(0, 1)) = 0
        _ReceiveLight ("Receive Scene Light (main light + ambient)", Range(0, 1)) = 1
        _SharpLow ("Sharp Line Threshold Low", Range(0, 1)) = 0.35
        _SharpHigh ("Sharp Line Threshold High", Range(0, 1)) = 0.6
        _SharpIntensity ("Sharp Intensity", Range(0, 2)) = 1
        _GlowIntensity ("Glow Intensity", Range(0, 1)) = 0.2
        _EmissionIntensity ("Emission Intensity", Range(0, 2)) = 0.4
        _UVDistortion ("Caustic UV Distortion", Range(0, 0.05)) = 0.015
        [Header(Caustic layers and scroll debug switches)]
        _CausticOn ("Caustic On", Range(0, 1)) = 1
        _SecondLayer ("Second Caustic Layer", Range(0, 1)) = 0
        _Scroll1 ("Scroll Layer 1", Range(0, 1)) = 1
        _Scroll2 ("Scroll Layer 2", Range(0, 1)) = 1
        _Layer1Weight ("Layer 1 Line Weight", Range(0, 1)) = 1
        [Header(Flow like the URP Moon caustics decal two copies drifting opposite warped together)]
        _FlowMode ("Flow Mode (0 rotated layers, 1 Moon flow, 2 double offset)", Range(0, 2)) = 0
        _FlowTimeScale ("Flow Time Scale", Float) = 0.6
        _FlowDir ("Flow Direction (caustic UV per flow second)", Vector) = (0.18, 0.09, 0, 0)
        _FlowScale2 ("Second Copy Scale", Float) = 1.1
        _FlowDistort ("Flow Warp Strength (UV)", Range(0, 0.15)) = 0.05
        _FlowWarpScroll ("Flow Warp Scroll (UV per flow second)", Vector) = (0, 0.3, 0, 0)
        _DebugTime ("Debug Fixed Time (-1 = live)", Float) = -1
        [Header(Double offset Shader Graph tutorial two Tiling and Offset sets used when Flow Mode is 2)]
        _Speed1 ("Set 1 Speed (UV per second)", Vector) = (0.05, 0.02, 0, 0)
        _Speed2 ("Set 2 Speed (UV per second)", Vector) = (-0.03, 0.04, 0, 0)
        _Tiling2 ("Set 2 Tiling Multiplier (1 = tutorial copy)", Range(0.5, 2)) = 1
        _Channel2 ("Set 2 Channel (0 R, 1 G)", Range(0, 1)) = 0
        _Combine ("Combine (0 min, 1 multiply, 2 max)", Range(0, 2)) = 0
        _CombineGain ("Combined Mask Gain", Range(0.5, 4)) = 1
        [Header(Toon)]
        _EdgeColor ("Edge Line Color", Color) = (0.62, 0.86, 0.95, 1)
        _EdgeWidth ("Edge Line Width", Range(0, 0.1)) = 0.025
        _GlintColor ("Glint Streak Color", Color) = (0.85, 0.95, 1, 1)
        _GlintStrength ("Glint Streak Strength", Range(0, 1)) = 0.35
        [Header(SSR)]
        _SSRSteps ("Ray Steps", Range(1, 32)) = 12
        _SSRStepSize ("Ray Step Size (m)", Range(0.01, 1)) = 0.2
        _SSRThickness ("Ray Thickness", Range(0.1, 4)) = 1
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent-50" "RenderPipeline" = "UniversalPipeline" }

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
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
            #include "Assets/Art/Environment/Shaders/GroundFog.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half _WaterRadius, _Irregularity, _WetWidth, _WetDarken, _EdgeSoftness;
                half4 _DeepColor, _ReflectionTint;
                half _ReflectMin, _ReflectMax, _SkyReflection, _Alpha;
                half _NormalStrength, _RippleScale, _RippleSpeed;
                half4 _CausticColor;
                half _CausticStrength;
                half4 _EdgeColor;
                half _EdgeWidth;
                half4 _GlintColor;
                half _GlintStrength;
                float _SSRSteps, _SSRStepSize, _SSRThickness;
                half _ToonMode;
                half4 _WaterColor, _HighlightColor;
                half _ToonReflection, _SharpLow, _SharpHigh, _SharpIntensity, _GlowIntensity, _EmissionIntensity, _UVDistortion;
                half _CausticOn, _SecondLayer, _Scroll1, _Scroll2, _ReceiveLight, _Layer1Weight;
                float _FlowMode, _FlowTimeScale, _FlowScale2, _FlowDistort, _DebugTime;
                float4 _FlowDir, _FlowWarpScroll;
                float4 _Speed1, _Speed2;
                half _Channel2, _Combine, _CombineGain, _Tiling2;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                half fogFactor : TEXCOORD2;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                VertexPositionInputs p = GetVertexPositionInputs(input.positionOS.xyz);
                o.positionCS = p.positionCS;
                o.positionWS = p.positionWS;
                o.uv = input.uv;
                o.fogFactor = ComputeFogFactor(p.positionCS.z);
                return o;
            }

            float Hash11(float n) { return frac(sin(n) * 43758.5453); }

            // --- SSR (URP Moon sample) ---
            float3 ViewPosFromDepth(float2 positionNDC, float deviceDepth)
            {
                float4 positionCS = ComputeClipSpacePosition(positionNDC, deviceDepth);
                float4 hpositionVS = mul(UNITY_MATRIX_I_P, positionCS);
                return hpositionVS.xyz / hpositionVS.w;
            }
            float2 ViewSpacePosToUV(float3 pos) { return ComputeNormalizedDeviceCoordinates(pos, UNITY_MATRIX_P); }
            half OutOfBoundsFade(half2 uv)
            {
                half2 f = saturate(1 - abs(uv - 0.5) * 2);
                return f.x * f.y;
            }
            void Raymarch(float3 origin, float3 direction, out float2 sampleUV, out half valid, out half outOfBounds)
            {
                sampleUV = 0; valid = 0; outOfBounds = 0;
                direction *= _SSRStepSize;
                [loop]
                for (int i = 0; i < (int)_SSRSteps; i++)
                {
                    origin += direction;
                    direction *= 1.5;
                    sampleUV = ViewSpacePosToUV(origin);
                    outOfBounds = OutOfBoundsFade(sampleUV);
                    if (any(sampleUV < 0) || any(sampleUV > 1)) return;
                    float3 samplePos = ViewPosFromDepth(sampleUV, SampleSceneDepth(sampleUV));
                    if (distance(samplePos.z, origin.z) > length(direction) * _SSRThickness) continue;
                    if (samplePos.z > origin.z)
                    {
                        // refine (my addition): halve back and forth between the last miss and this hit,
                        // otherwise the growing steps land the hit far from the real surface (smeared blobs)
                        float3 lo = origin - direction / 1.5, hi = origin;
                        [unroll] for (int b = 0; b < 6; b++)
                        {
                            float3 mid = (lo + hi) * 0.5;
                            float2 muv = ViewSpacePosToUV(mid);
                            float3 mpos = ViewPosFromDepth(muv, SampleSceneDepth(muv));
                            if (mpos.z > mid.z) hi = mid; else lo = mid;
                        }
                        sampleUV = ViewSpacePosToUV(hi);
                        outOfBounds = OutOfBoundsFade(sampleUV);
                        valid = 1; return;
                    }
                }
            }

            TEXTURE2D(_RippleMap); SAMPLER(sampler_RippleMap);
            // two layers of the ripple map, different size / angle, drifting different ways.
            // x = surface height, y = caustic line brightness
            // raw samples of both layers: xy = layer 1 (r, g), zw = layer 2 (r, g); _Scroll1/_Scroll2 freeze a layer
            float SceneTime() { return _DebugTime >= 0 ? _DebugTime : _Time.y; }
            float4 RippleLayers(float2 pw, float t, float2 distort)
            {
                float2 uv1 = pw * _RippleScale + t * _Scroll1 * float2(0.031, 0.019) + distort;
                float2 r2 = float2(pw.x * 0.8 - pw.y * 0.6, pw.x * 0.6 + pw.y * 0.8);
                float2 uv2 = r2 * _RippleScale * 1.37 + t * _Scroll2 * float2(-0.023, 0.029) + 0.37 + distort;
                UNITY_BRANCH if (_FlowMode > 0.5)
                {
                    // Moon decal: uv1 = (p + t(0.6,0.3)) * 0.3, uv2 = (p - t(0.6,0.3)) * 0.33, both + normalTex.xy * 0.05,
                    // normal uv = p * 0.4 + t(0, 0.3), t = time * 0.6. Here base = p * 0.3 = pw * _RippleScale, and the
                    // warp reads this map's soft G channel twice (no normal map in the project; my substitute)
                    float tf = SceneTime() * _FlowTimeScale;
                    float2 base = pw * _RippleScale;
                    float2 uvN = base * (0.4 / 0.3) + tf * _FlowWarpScroll.xy;
                    float2 warp = float2(SAMPLE_TEXTURE2D_LOD(_RippleMap, sampler_RippleMap, uvN, 0).g,
                                         SAMPLE_TEXTURE2D_LOD(_RippleMap, sampler_RippleMap, uvN.yx + 0.5, 0).g) * 2 - 1;
                    warp *= _FlowDistort;
                    uv1 = base + tf * _Scroll1 * _FlowDir.xy + warp + distort;
                    uv2 = (base - tf * _Scroll2 * _FlowDir.xy) * _FlowScale2 + 0.37 + warp + distort;
                }
                half2 a = SAMPLE_TEXTURE2D_LOD(_RippleMap, sampler_RippleMap, uv1, 0).rg;
                half2 b = SAMPLE_TEXTURE2D_LOD(_RippleMap, sampler_RippleMap, uv2, 0).rg;
                return float4(a, b);
            }
            float2 Ripple(float2 pw, float t)
            {
                float4 l = RippleLayers(pw, t, 0);
                return float2(l.y * 0.6 + l.w * 0.4, max(l.x, l.z * 0.75));
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float3 objPos = GetObjectToWorldMatrix()._m03_m13_m23;
                float seed = Hash11(dot(objPos, float3(12.9898, 78.233, 37.719))) * 100.0;

                // shape: radius wobbles with the angle (three sines of unrelated frequencies)
                float r = length(i.uv);
                float a = atan2(i.uv.y, i.uv.x);
                float wob = 0.55 * sin(3 * a + seed) + 0.3 * sin(5 * a + seed * 1.7) + 0.15 * sin(9 * a + seed * 2.3);
                float edgeR = _WaterRadius * (1 + _Irregularity * wob);
                float water = 1 - smoothstep(edgeR - _EdgeSoftness, edgeR + _EdgeSoftness, r);
                float wetR = edgeR + _WetWidth * (1 + 0.5 * wob);
                float wet = (1 - smoothstep(edgeR, wetR, r)) * (1 - water);
                if (water + wet < 0.001) discard;

                // ripples: two scrolling sine fields make a small normal tilt
                float t = SceneTime() * _RippleSpeed;
                float e = 0.01;                                              // finite difference step (m)
                float2 rp = Ripple(i.positionWS.xz, t);
                float hx = Ripple(i.positionWS.xz + float2(e, 0), t).x;
                float hz = Ripple(i.positionWS.xz + float2(0, e), t).x;
                float2 g = float2(hx - rp.x, hz - rp.x) / e * 0.08;
                float3 N = normalize(float3(-g.x * _NormalStrength, 1, -g.y * _NormalStrength));

                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);

                // reflection: SSR first, sky / probe where it misses
                float3 posVS = TransformWorldToView(i.positionWS);
                float3 nVS = TransformWorldToViewDir(N, true);
                float3 dirVS = reflect(normalize(posVS), nVS);
                float2 hitUV; half valid, oob;
                Raymarch(posVS, dirVS, hitUV, valid, oob);
                half3 sky = GlossyEnvironmentReflection(reflect(-V, N), i.positionWS, 0.05h, 1.0h, screenUV) * _SkyReflection;
                half3 ssr = SampleSceneColor(hitUV);
                half3 refl = lerp(sky, ssr, valid * oob) * _ReflectionTint.rgb;

                half facing = saturate(dot(N, V));
                half fres = lerp(_ReflectMin, _ReflectMax, pow(1 - facing, 3));
                half3 legacyCol = lerp(_DeepColor.rgb, refl, fres);
                // toon body: flat water colour lit like the ground around it (main light + sky ambient, no ramp:
                // the puddle is flat), reflection only as much as asked for
                half3 sceneLight = lerp(half3(1, 1, 1), GetMainLight().color * saturate(GetMainLight().direction.y) + SampleSH(half3(0, 1, 0)), _ReceiveLight);
                half3 toonCol = lerp(_WaterColor.rgb * sceneLight, refl, _ToonReflection * fres);
                half3 col = lerp(legacyCol, toonCol, _ToonMode);

                // toon: bright line along the water edge, two diagonal glint streaks across the surface
                float edgeLine = smoothstep(edgeR - _EdgeWidth - _EdgeSoftness, edgeR - _EdgeWidth, r) * water;
                col = lerp(col, _EdgeColor.rgb * lerp(half3(1, 1, 1), sceneLight, _ToonMode), edgeLine * 0.8);
                float edgeFade = smoothstep(edgeR, edgeR * 0.8, r);
                // legacy: bright cell borders from both layers, added on top
                float legacyCaustic = rp.y * _CausticStrength;
                // toon: R = sharp line mask, G = soft glow mask; black adds nothing, only bright lines count
                float2 distort = (SAMPLE_TEXTURE2D_LOD(_RippleMap, sampler_RippleMap, i.positionWS.xz * _RippleScale * 0.31 + t * 0.011, 0).g - 0.5) * _UVDistortion;
                float4 l = RippleLayers(i.positionWS.xz, t, distort);
                // weighted sum like the Moon decal (it adds its two copies); 0.5 + 0.5 = lines only fully on where they meet
                float sharpMask = l.x * _Layer1Weight + l.z * _SecondLayer;
                float glowMask = max(l.y, l.w * _SecondLayer);
                UNITY_BRANCH if (_FlowMode > 1.5)
                {
                    // Shader Graph tutorial "double offset": Tiling & Offset (tiling = _RippleScale, offset = Time x Speed)
                    // -> Sample Texture 2D, twice with different speeds; set 1 reads R, set 2 reads R or G; then Min
                    // (only where both nets overlap), Multiply or Max. The baked mask already holds its own soft glow.
                    float st = SceneTime();
                    float2 b0 = i.positionWS.xz * _RippleScale;
                    half4 s1 = SAMPLE_TEXTURE2D_LOD(_RippleMap, sampler_RippleMap, b0 + st * _Speed1.xy, 0);
                    // set 2: optional tiling multiplier + fixed 0.37 offset; with identical tiling both sets line up
                    // whenever their offset difference is a whole tile (every 50 s at the tutorial speeds) and the
                    // whole net flashes back (seen in Unity renders)
                    half4 s2 = SAMPLE_TEXTURE2D_LOD(_RippleMap, sampler_RippleMap, b0 * _Tiling2 + st * _Speed2.xy + (_Tiling2 != 1 ? 0.37 : 0), 0);
                    float m1 = s1.r, m2 = lerp(s2.r, s2.g, _Channel2);
                    float comb = _Combine < 0.5 ? min(m1, m2) : (_Combine < 1.5 ? m1 * m2 : max(m1, m2));
                    sharpMask = saturate(comb * _CombineGain);
                    glowMask = sharpMask;
                }
                float sharp = smoothstep(_SharpLow, _SharpHigh, sharpMask) * _SharpIntensity;
                float toonCaustic = saturate(sharp + glowMask * _GlowIntensity);
                float caustic = lerp(legacyCaustic, toonCaustic, _ToonMode) * edgeFade * _CausticOn;
                half3 legacyAdd = col + _CausticColor.rgb * caustic;
                // highlight lerp is lit like the body, the emission term glows on its own (visible at night)
                half3 toonMix = lerp(col, _HighlightColor.rgb * sceneLight, caustic) + _HighlightColor.rgb * caustic * _EmissionIntensity;
                col = lerp(legacyAdd, toonMix, _ToonMode);
                float2 q = i.uv + g * 0.02;
                float s1 = smoothstep(0.035, 0.0, abs(q.x * 0.7 + q.y - 0.18 * edgeR));
                float s2 = smoothstep(0.018, 0.0, abs(q.x * 0.7 + q.y - 0.32 * edgeR));
                col += _GlintColor.rgb * _GlintStrength * max(s1, s2 * 0.7) * smoothstep(edgeR * 0.85, edgeR * 0.4, r);

                col = ApplyGroundFog(col, i.positionWS);
                col = MixFog(col, i.fogFactor);
                half alpha = max(water * _Alpha, wet * _WetDarken);
                half3 outC = lerp(half3(0, 0, 0), col, water);       // wet ring = black at low alpha (darkens the ground)
                return half4(outC, alpha);
            }
            ENDHLSL
        }
    }
}
