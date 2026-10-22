// Toon terrain (Notion "잔디 카드 제작" page) — Unity Terrain with the same two-tone ramp as SDCatToon (M_Ground_Toon
// look), up to 4 Terrain Layers blended by the splat map, the SurvivalKit cloud shadow on direct light only.
// Use on a Terrain with "Draw Instanced" OFF (plain mesh path; the terrain fills _Control / _Splat0..3 / _Normal0..3
// and their _ST from the Terrain Layers' tile size).
// The "GroundColorBake" pass is drawn by GroundColorBaker on a flat quad over the terrain (uv = terrain 0..1) so the
// grass roots keep taking the ground colour (RVT stand-in).
Shader "DSEWA/ToonTerrain"
{
    Properties
    {
        [HideInInspector] _Control ("Control (RGBA)", 2D) = "red" {}
        [HideInInspector] _Splat0 ("Layer 0", 2D) = "grey" {}
        [HideInInspector] _Splat1 ("Layer 1", 2D) = "grey" {}
        [HideInInspector] _Splat2 ("Layer 2", 2D) = "grey" {}
        [HideInInspector] _Splat3 ("Layer 3", 2D) = "grey" {}
        [HideInInspector] _Normal0 ("Normal 0", 2D) = "bump" {}
        [HideInInspector] _Normal1 ("Normal 1", 2D) = "bump" {}
        [HideInInspector] _Normal2 ("Normal 2", 2D) = "bump" {}
        [HideInInspector] _Normal3 ("Normal 3", 2D) = "bump" {}
        [HideInInspector] _Mask0 ("Mask 0 (B = height)", 2D) = "grey" {}
        [HideInInspector] _Mask1 ("Mask 1 (B = height)", 2D) = "grey" {}
        [HideInInspector] _Mask2 ("Mask 2 (B = height)", 2D) = "grey" {}
        [HideInInspector] _Mask3 ("Mask 3 (B = height)", 2D) = "grey" {}
        _LitColor ("Lit Color", Color) = (1, 1, 1, 1)
        _ShadowColor ("Shadow Color", Color) = (0.62, 0.68, 0.78, 1)
        _Threshold ("Shadow Threshold", Range(-1, 1.5)) = 0.393
        _Softness ("Shadow Edge Width", Range(0.001, 0.3)) = 0.053
        _ShadowBlur ("Cast Shadow Smoothing (texels, 0 = URP)", Range(0, 4)) = 1.5
        _AmbientShade ("Ambient Shade", Range(0, 1)) = 0.105
        _BumpScale ("Normal Strength", Float) = 1
        [Header(Random Tiling (hex grid))]
        [Toggle] _HexEnable ("Randomize Tiling", Float) = 1
        _HexCellSize ("Cell Size (tiles)", Range(0.25, 4)) = 1
        _HexRotation ("Random Rotation", Range(0, 1)) = 1
        _HexSharpness ("Cell Edge Sharpness", Range(1, 32)) = 8
        [Header(Height Blend (layer mask map B))]
        [Toggle] _HeightBlend ("Height Blend", Float) = 1
        _HeightBlendScale ("Height Influence", Range(0, 1)) = 0.5
        _HeightBlendWidth ("Blend Edge Width", Range(0.005, 0.5)) = 0.05
        [Header(Grass Border (coverage baked by GroundColorBaker))]
        _GrassTintColor ("Ground Tint Under Grass (multiply)", Color) = (0.62, 0.54, 0.86, 1)
        _GrassTintAmount ("Ground Tint Amount", Range(0, 1)) = 1
        _GrassTintRange ("Ground Tint Range (coverage lo, hi)", Vector) = (0.03, 0.55, 0, 0)
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry-100" "TerrainCompatible" = "True" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _Control_ST;
            float4 _Splat0_ST, _Splat1_ST, _Splat2_ST, _Splat3_ST;
            half4 _LitColor, _ShadowColor;
            half _Threshold, _Softness, _AmbientShade, _BumpScale;
            half _ShadowBlur;
            half _HexEnable, _HexCellSize, _HexRotation, _HexSharpness;
            half _HeightBlend, _HeightBlendScale, _HeightBlendWidth;
            half4 _GrassTintColor, _GrassTintRange;
            half _GrassTintAmount;
        CBUFFER_END

        // global from GroundColorBaker: blurred grass detail density over the terrain (uv = terrain 0..1); rect.z == 0 = off
        TEXTURE2D(_DSEWA_GrassCoverage); SAMPLER(sampler_DSEWA_GrassCoverage);
        float4 _DSEWA_GrassCoverageRect;

        TEXTURE2D(_Control); SAMPLER(sampler_Control);
        TEXTURE2D(_Splat0); SAMPLER(sampler_Splat0);
        TEXTURE2D(_Splat1); TEXTURE2D(_Splat2); TEXTURE2D(_Splat3);
        TEXTURE2D(_Normal0); SAMPLER(sampler_Normal0);
        TEXTURE2D(_Normal1); TEXTURE2D(_Normal2); TEXTURE2D(_Normal3);
        TEXTURE2D(_Mask0); TEXTURE2D(_Mask1); TEXTURE2D(_Mask2); TEXTURE2D(_Mask3);

        // ---- Random tiling: hex (triangle) grid, each cell samples the layer at a random offset / rotation
        // (Heitz & Neyret 2018 / Mikkelsen 2022). Weights are sharpened so cell borders stay crisp (toon).
        struct HexTile { float2 uv0, uv1, uv2; float2 cs0, cs1, cs2; float3 w; float2 dx, dy; };

        float2 HexHash(float2 p)
        {
            p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
            return frac(sin(p) * 43758.5453);
        }
        float2 HexRot(float2 p, float2 cs) { return float2(p.x * cs.x - p.y * cs.y, p.x * cs.y + p.y * cs.x); }

        // dx / dy = screen derivatives of uvT, taken outside any branch by the caller
        HexTile HexSetup(float2 uvT, float2 dx, float2 dy)
        {
            HexTile h = (HexTile)0;
            h.dx = dx; h.dy = dy;
            // skewed triangle grid (GLSL mat2(1, 0, -0.577, 1.155) is column-major)
            float2 skewed = mul(float2x2(1.0, -0.57735027, 0.0, 1.15470054), uvT * (3.4641016 / _HexCellSize));
            float2 base = floor(skewed);
            float3 t = float3(frac(skewed), 0); t.z = 1.0 - t.x - t.y;
            float2 v0 = 0, v1 = 0, v2 = 0; float3 w = 0;
            if (t.z > 0) { w = float3(t.z, t.y, t.x); v0 = base; v1 = base + float2(0, 1); v2 = base + float2(1, 0); }
            else { w = float3(-t.z, 1 - t.y, 1 - t.x); v0 = base + 1; v1 = base + float2(1, 0); v2 = base + float2(0, 1); }
            float2 r0 = HexHash(v0), r1 = HexHash(v1), r2 = HexHash(v2);
            float a = 6.2831853 * _HexRotation;
            h.cs0 = float2(cos(r0.x * a), sin(r0.x * a));
            h.cs1 = float2(cos(r1.x * a), sin(r1.x * a));
            h.cs2 = float2(cos(r2.x * a), sin(r2.x * a));
            h.uv0 = HexRot(uvT, h.cs0) + r0 * 17.0;
            h.uv1 = HexRot(uvT, h.cs1) + r1 * 17.0;
            h.uv2 = HexRot(uvT, h.cs2) + r2 * 17.0;
            w = pow(max(w, 1e-4), _HexSharpness);
            h.w = w / dot(w, 1);
            return h;
        }

        half4 HexSample(TEXTURE2D_PARAM(tex, samp), HexTile h)
        {
            return SAMPLE_TEXTURE2D_GRAD(tex, samp, h.uv0, HexRot(h.dx, h.cs0), HexRot(h.dy, h.cs0)) * h.w.x
                 + SAMPLE_TEXTURE2D_GRAD(tex, samp, h.uv1, HexRot(h.dx, h.cs1), HexRot(h.dy, h.cs1)) * h.w.y
                 + SAMPLE_TEXTURE2D_GRAD(tex, samp, h.uv2, HexRot(h.dx, h.cs2), HexRot(h.dy, h.cs2)) * h.w.z;
        }

        // tangent-space normal: each sample is rotated back by its cell's angle before blending
        half3 HexNormal(TEXTURE2D_PARAM(tex, samp), HexTile h)
        {
            half3 n0 = UnpackNormalScale(SAMPLE_TEXTURE2D_GRAD(tex, samp, h.uv0, HexRot(h.dx, h.cs0), HexRot(h.dy, h.cs0)), _BumpScale);
            half3 n1 = UnpackNormalScale(SAMPLE_TEXTURE2D_GRAD(tex, samp, h.uv1, HexRot(h.dx, h.cs1), HexRot(h.dy, h.cs1)), _BumpScale);
            half3 n2 = UnpackNormalScale(SAMPLE_TEXTURE2D_GRAD(tex, samp, h.uv2, HexRot(h.dx, h.cs2), HexRot(h.dy, h.cs2)), _BumpScale);
            n0.xy = HexRot(n0.xy, float2(h.cs0.x, -h.cs0.y));
            n1.xy = HexRot(n1.xy, float2(h.cs1.x, -h.cs1.y));
            n2.xy = HexRot(n2.xy, float2(h.cs2.x, -h.cs2.y));
            return n0 * h.w.x + n1 * h.w.y + n2 * h.w.z;
        }

        // duv = (ddx(uv), ddy(uv)) of the terrain 0..1 uv. Returns albedo.rgb + height (mask map B) in .a;
        // both read through the same random-tiling cells so the height edges line up with the albedo.
        half4 LayerSample(TEXTURE2D_PARAM(tex, samp), TEXTURE2D_PARAM(mask, msamp), float2 uv, float4 duv, float4 st)
        {
            float2 uvT = uv * st.xy + st.zw, dx = duv.xy * st.xy, dy = duv.zw * st.xy;
            half4 result;   // single exit: two returns around the derivative-based hex setup raised FXC X4000
            if (_HexEnable > 0.5)
            {
                HexTile h = HexSetup(uvT, dx, dy);
                result = half4(HexSample(TEXTURE2D_ARGS(tex, samp), h).rgb, HexSample(TEXTURE2D_ARGS(mask, msamp), h).b);
            }
            else
            {
                result = half4(SAMPLE_TEXTURE2D_GRAD(tex, samp, uvT, dx, dy).rgb, SAMPLE_TEXTURE2D_GRAD(mask, msamp, uvT, dx, dy).b);
            }
            return result;
        }

        // Height blend (Unreal LB_HeightBlend style): weight + height decides which layer shows, so the border follows
        // the texture detail (pebbles, clumps) instead of the coarse splat-map grid. Narrow width = crisp toon border.
        half4 HeightBlendWeights(half4 w, half4 h)
        {
            half4 hw = w + h * _HeightBlendScale;
            hw = lerp(-1.0h, hw, step(0.002h, w));            // layers with no paint never win
            half top = max(max(hw.r, hw.g), max(hw.b, hw.a)) - _HeightBlendWidth;
            half4 b = max(hw - top, 0);
            return b / max(dot(b, 1), 1e-4);
        }

        half3 LayerNormal(TEXTURE2D_PARAM(tex, samp), float2 uv, float4 duv, float4 st)
        {
            float2 uvT = uv * st.xy + st.zw, dx = duv.xy * st.xy, dy = duv.zw * st.xy;
            half3 result;
            if (_HexEnable > 0.5)
                result = HexNormal(TEXTURE2D_ARGS(tex, samp), HexSetup(uvT, dx, dy));
            else
                result = UnpackNormalScale(SAMPLE_TEXTURE2D_GRAD(tex, samp, uvT, dx, dy), _BumpScale);
            return result;
        }

        // Splat-weighted albedo (4 layers); uv = terrain 0..1. Layers with no paint here are skipped.
        half3 TerrainAlbedo(float2 uv, out half4 w)
        {
            w = SAMPLE_TEXTURE2D(_Control, sampler_Control, uv);
            w /= max(dot(w, 1), 1e-3);
            float4 duv = float4(ddx(uv), ddy(uv));
            half4 s0 = 0, s1 = 0, s2 = 0, s3 = 0;
            UNITY_BRANCH if (w.r > 0.002) s0 = LayerSample(TEXTURE2D_ARGS(_Splat0, sampler_Splat0), TEXTURE2D_ARGS(_Mask0, sampler_Splat0), uv, duv, _Splat0_ST);
            UNITY_BRANCH if (w.g > 0.002) s1 = LayerSample(TEXTURE2D_ARGS(_Splat1, sampler_Splat0), TEXTURE2D_ARGS(_Mask1, sampler_Splat0), uv, duv, _Splat1_ST);
            UNITY_BRANCH if (w.b > 0.002) s2 = LayerSample(TEXTURE2D_ARGS(_Splat2, sampler_Splat0), TEXTURE2D_ARGS(_Mask2, sampler_Splat0), uv, duv, _Splat2_ST);
            UNITY_BRANCH if (w.a > 0.002) s3 = LayerSample(TEXTURE2D_ARGS(_Splat3, sampler_Splat0), TEXTURE2D_ARGS(_Mask3, sampler_Splat0), uv, duv, _Splat3_ST);
            if (_HeightBlend > 0.5)
                w = HeightBlendWeights(w, half4(s0.a, s1.a, s2.a, s3.a));   // the normals use these weights too
            half3 albedo = s0.rgb * w.r + s1.rgb * w.g + s2.rgb * w.b + s3.rgb * w.a;
            // ground darkens towards the grass roots near grass -> the border fades from both sides
            if (_DSEWA_GrassCoverageRect.z > 0 && _GrassTintAmount > 0)
            {
                half cov = SAMPLE_TEXTURE2D_LOD(_DSEWA_GrassCoverage, sampler_DSEWA_GrassCoverage, uv, 0).r;
                albedo *= lerp(1, _GrassTintColor.rgb, smoothstep(_GrassTintRange.x, _GrassTintRange.y, cov) * _GrassTintAmount);
            }
            return albedo;
        }
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fog
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Art/Environment/Shaders/CloudShadow.hlsl"   // SurvivalKit cloud shadow: direct light only
            #include "Assets/Art/Environment/Shaders/ToonShadow.hlsl"     // smooth-contoured toon cast shadow
            #include "Assets/Art/Environment/Shaders/GroundFog.hlsl"      // ground-only distance fog

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                half fogFactor : TEXCOORD3;
            };

            Varyings vert(Attributes input)
            {
                Varyings o;
                o.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                o.uv = input.uv;
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                half4 w;
                half3 albedo = TerrainAlbedo(i.uv, w);

                // Layer normals (terrain has no tangents: build them from the normal, u = +x, v = +z)
                float3 N = normalize(i.normalWS);
                float3 T = normalize(cross(N, float3(0, 0, 1)));
                float3 B = cross(T, N);
                float4 duv = float4(ddx(i.uv), ddy(i.uv));
                half3 nTS = 0;
                UNITY_BRANCH if (w.r > 0.002) nTS += LayerNormal(TEXTURE2D_ARGS(_Normal0, sampler_Normal0), i.uv, duv, _Splat0_ST) * w.r;
                UNITY_BRANCH if (w.g > 0.002) nTS += LayerNormal(TEXTURE2D_ARGS(_Normal1, sampler_Normal0), i.uv, duv, _Splat1_ST) * w.g;
                UNITY_BRANCH if (w.b > 0.002) nTS += LayerNormal(TEXTURE2D_ARGS(_Normal2, sampler_Normal0), i.uv, duv, _Splat2_ST) * w.b;
                UNITY_BRANCH if (w.a > 0.002) nTS += LayerNormal(TEXTURE2D_ARGS(_Normal3, sampler_Normal0), i.uv, duv, _Splat3_ST) * w.a;
                N = normalize(nTS.x * T + nTS.y * B + nTS.z * N);

                Light light = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                half direct = min(ToonMainLightShadow(i.positionWS, _ShadowBlur), ToonCharacterShadow(i.positionWS, _ShadowBlur)) * EvaluateCloudShadow(i.positionWS);
                float shade = saturate(dot(N, light.direction)) * direct + _AmbientShade;
                float lit = smoothstep(_Threshold, _Threshold + _Softness, shade);
                half3 color = lerp(_ShadowColor.rgb, _LitColor.rgb, lit) * albedo;
                color = ApplyGroundFog(color, i.positionWS);
                return half4(MixFog(color, i.fogFactor), 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings { float4 positionCS : SV_POSITION; };

            Varyings vert(Attributes input)
            {
                Varyings o;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDir = normalize(_LightPosition - positionWS);
            #else
                float3 lightDir = _LightDirection;
            #endif
                o.positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDir));
            #if UNITY_REVERSED_Z
                o.positionCS.z = min(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                o.positionCS.z = max(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                return o;
            }

            half4 frag(Varyings i) : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On ColorMask R

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings { float4 positionCS : SV_POSITION; };
            Varyings vert(Attributes input) { Varyings o; o.positionCS = TransformObjectToHClip(input.positionOS.xyz); return o; }
            half frag(Varyings i) : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }
            ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT
            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 normalWS : TEXCOORD0; };
            Varyings vert(Attributes input)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return o;
            }
            half4 frag(Varyings i) : SV_Target
            {
                float3 n = normalize(i.normalWS);
            #if defined(_GBUFFER_NORMALS_OCT)
                return half4(PackFloat2To888(saturate(PackNormalOctQuadEncode(n) * 0.5 + 0.5)), 0);
            #else
                return half4(n, 0);
            #endif
            }
            ENDHLSL
        }

        // RVT stand-in: lit albedo only, drawn by GroundColorBaker on a flat quad (uv = terrain 0..1) from above
        Pass
        {
            Name "GroundColorBake"
            Tags { "LightMode" = "DSEWAGroundBake" }
            Cull Off ZWrite Off ZTest Always

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };
            Varyings vert(Attributes input) { Varyings o; o.positionCS = TransformObjectToHClip(input.positionOS.xyz); o.uv = input.uv; return o; }
            half4 frag(Varyings i) : SV_Target { half4 w; return half4(TerrainAlbedo(i.uv, w) * _LitColor.rgb, 1); }
            ENDHLSL
        }
    }
}
