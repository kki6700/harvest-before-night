// Toon moon model (MoonModel component places it along the moonlight direction).
// Self-lit: the directional light comes from the moon itself, so the shading uses an artistic phase light
// (_PhaseDir, set by MoonModel from Phase Angle / Phase Rotation) instead of the scene light.
// Three-step toon (shadow / mid / lit) with baked colour + AO + normal maps, optional procedural crater patches,
// a soft limb glow and HDR emission for bloom.
// Like ToonCloudMesh it is shrunk towards the camera (_CameraShrink) so a km-scale moon stays inside the far plane.
Shader "DSEWA/ToonMoon"
{
    Properties
    {
        _BaseMap ("Texture (optional)", 2D) = "white" {}
        [Normal] _BumpMap ("Normal Map (baked high -> low)", 2D) = "bump" {}
        _BumpScale ("Normal Strength", Range(0, 3)) = 1
        _OcclusionMap ("AO (baked)", 2D) = "white" {}
        _AORange ("AO Remap (black, white)", Vector) = (0.25, 0.5, 0, 0)
        _OcclusionStrength ("AO Strength", Range(0, 1)) = 0.8
        _LitColor ("Lit", Color) = (0.93, 0.94, 1, 1)
        _MidColor ("Mid (3rd toon step)", Color) = (0.55, 0.57, 0.78, 1)
        _ShadowColor ("Shadow (earthshine)", Color) = (0.16, 0.18, 0.38, 1)
        _Threshold ("Terminator", Range(-1, 1)) = 0
        _MidThreshold ("Mid Step (lit above this)", Range(-1, 1)) = 0.35
        _Softness ("Terminator Softness", Range(0.001, 0.3)) = 0.02
        _Smooth ("Smooth Shading (0 toon steps, 1 soft gradient: rounder, more volume)", Range(0, 1)) = 0
        _Wrap ("Smooth Light Wrap (light reaching past the terminator)", Range(0, 1)) = 0.15
        [Header(Craters)]
        _CraterColor ("Crater Colour (multiply)", Color) = (0.72, 0.74, 0.92, 1)
        _CraterScale ("Crater Scale (object space)", Float) = 3.2
        _CraterAmount ("Crater Amount", Range(0, 1)) = 0.6
        [Header(Toon Flat Colours)]
        _Flatten ("Flatten (0 painted maps, 1 flat toon areas)", Range(0, 1)) = 0
        _HighlandColor ("Highlands", Color) = (0.86, 0.85, 0.95, 1)
        _MariaColor ("Maria (dark seas)", Color) = (0.45, 0.47, 0.68, 1)
        _MariaThreshold ("Maria Threshold (colour map luminance)", Range(0, 1)) = 0.6
        _CraterFloorColor ("Crater Floor (flat)", Color) = (0.62, 0.62, 0.82, 1)
        _CraterAOThreshold ("Crater Floor Threshold (AO)", Range(0, 1)) = 0.55
        _RimLightColor ("Crater Rim Highlight", Color) = (1, 1, 1, 1)
        _RimLightThreshold ("Rim Highlight Threshold (colour luminance)", Range(0, 1.5)) = 0.93
        _NormalBlur ("Normal Simplify (mip bias)", Range(0, 6)) = 0
        [Header(Ink Outline)]
        _OutlineColor ("Outline Colour", Color) = (0.1, 0.1, 0.28, 1)
        _OutlineWidth ("Outline Width (fresnel)", Range(0, 0.5)) = 0
        [Header(Glow)]
        _RimBand ("Limb Glow Flat Band (0 soft)", Range(0, 1)) = 0
        [HDR] _RimColor ("Limb Glow", Color) = (0.75, 0.85, 1.4, 1)
        _RimPower ("Limb Glow Width", Range(0.5, 8)) = 3
        _Emission ("Brightness (HDR, bloom)", Range(0, 6)) = 1.6
        [HideInInspector] _PhaseDir ("Phase Light (world, set by MoonModel)", Vector) = (0, 0, -1, 0)
        [HideInInspector] _CameraShrink ("Camera Shrink (set by MoonModel)", Float) = 1
        [HideInInspector] _GlowMul ("Glow Multiplier (set by MoonModel)", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry+20" }

        Pass
        {
            Name "Moon"
            Tags { "LightMode" = "UniversalForward" }
            Cull Back ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);
            TEXTURE2D(_OcclusionMap); SAMPLER(sampler_OcclusionMap);
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half _BumpScale;
                float4 _AORange;
                half _OcclusionStrength, _MidThreshold;
                half4 _MidColor;
                half _Flatten, _MariaThreshold, _CraterAOThreshold, _RimLightThreshold, _NormalBlur, _OutlineWidth, _RimBand;
                half4 _HighlandColor, _MariaColor, _CraterFloorColor, _RimLightColor, _OutlineColor;
                half4 _LitColor, _ShadowColor, _CraterColor, _RimColor;
                half _Threshold, _Softness, _CraterScale, _CraterAmount, _RimPower, _Emission;
                half _Smooth, _Wrap;
                float4 _PhaseDir;
                float _CameraShrink, _GlowMul;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float4 tangentOS : TANGENT; float2 uv : TEXCOORD0; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS : TEXCOORD0;
                float3 positionOS : TEXCOORD1;
                float3 viewWS : TEXCOORD2;
                float2 uv : TEXCOORD3;
                float4 tangentWS : TEXCOORD4;
            };

            Varyings vert(Attributes input)
            {
                Varyings o;
                float3 ws = TransformObjectToWorld(input.positionOS.xyz);
                float3 eye = _WorldSpaceCameraPos;
                o.positionCS = TransformWorldToHClip(eye + (ws - eye) * _CameraShrink);
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                o.tangentWS = float4(TransformObjectToWorldDir(input.tangentOS.xyz), input.tangentOS.w * GetOddNegativeScale());
                o.positionOS = input.positionOS.xyz;
                o.viewWS = normalize(eye - ws);
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return o;
            }

            float Hash31(float3 p) { p = frac(p * 0.1031); p += dot(p, p.zyx + 31.32); return frac((p.x + p.y) * p.z); }
            // cellular craters: 1 inside a crater bowl, rim ring slightly brighter
            float2 Craters(float3 p)
            {
                float3 i = floor(p), f = frac(p);
                float best = 1, rimv = 0;
                [unroll] for (int z = -1; z <= 1; z++)
                [unroll] for (int y = -1; y <= 1; y++)
                [unroll] for (int x = -1; x <= 1; x++)
                {
                    float3 c = float3(x, y, z);
                    float3 h = float3(Hash31(i + c), Hash31(i + c + 17.3), Hash31(i + c + 41.7));
                    float r = lerp(0.18, 0.45, Hash31(i + c + 7.7));
                    float d = length(c + h - f) / r;
                    best = min(best, d);
                }
                float bowl = 1 - smoothstep(0.75, 0.85, best);
                float ring = smoothstep(0.8, 0.9, best) * (1 - smoothstep(0.95, 1.05, best));
                return float2(bowl, ring);
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 Ng = normalize(i.normalWS);                                  // geometric normal (outline)
                float3 N = Ng;
                float3 T = normalize(i.tangentWS.xyz);
                float3 B = cross(N, T) * i.tangentWS.w;
                // mip bias = simplified normals: only the big crater shapes survive -> clean toon shadow shapes
                half3 nTS = UnpackNormalScale(SAMPLE_TEXTURE2D_BIAS(_BumpMap, sampler_BumpMap, i.uv, _NormalBlur), _BumpScale);
                N = normalize(nTS.x * T + nTS.y * B + nTS.z * N);
                float ndl = dot(N, normalize(_PhaseDir.xyz));
                float w = max(fwidth(ndl), _Softness);
                float lit = smoothstep(_Threshold - w, _Threshold + w, ndl);
                float lit2 = smoothstep(_MidThreshold - w, _MidThreshold + w, ndl);      // 3 toon steps: shadow / mid / lit
                half3 tone = lerp(lerp(_ShadowColor.rgb, _MidColor.rgb, lit), _LitColor.rgb, lit2);
                // smooth option: wrapped Lambert through the same three colours -> the light rolls round the ball and the
                // normal map's craters cast long soft shadows along the terminator
                float s = saturate((ndl + _Wrap) / (1 + _Wrap));
                half3 smoothTone = s < 0.5 ? lerp(_ShadowColor.rgb, _MidColor.rgb, s * 2) : lerp(_MidColor.rgb, _LitColor.rgb, s * 2 - 1);
                tone = lerp(tone, smoothTone, _Smooth);
                lit = lerp(lit, s, _Smooth);
                half ao = saturate((SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, i.uv).r - _AORange.x) / max(_AORange.y - _AORange.x, 1e-3));
                half3 painted = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb;
                half3 albedo = painted * lerp(1, ao, _OcclusionStrength);
                // flat toon areas: maria / highlands by the colour map's brightness, crater floors by the AO,
                // crater rims by the brightest colour-map values; every edge is a crisp 1-pixel cut
                half lum = dot(painted, half3(0.3, 0.59, 0.11));
                half lw = fwidth(lum) + 0.01, aw = fwidth(ao) + 0.01;
                half3 flat = lerp(_MariaColor.rgb, _HighlandColor.rgb, smoothstep(_MariaThreshold - lw, _MariaThreshold + lw, lum));
                flat = lerp(flat, flat * _CraterFloorColor.rgb, 1 - smoothstep(_CraterAOThreshold - aw, _CraterAOThreshold + aw, ao));
                flat = lerp(flat, _RimLightColor.rgb, smoothstep(_RimLightThreshold - lw, _RimLightThreshold + lw, lum));
                albedo = lerp(albedo, flat, _Flatten);
                half3 col = tone * albedo;
                float2 cr = Craters(i.positionOS * _CraterScale) * _CraterAmount;
                cr += Craters(i.positionOS * _CraterScale * 2.3 + 5.1) * _CraterAmount * 0.5;
                col *= lerp(half3(1, 1, 1), _CraterColor.rgb, saturate(cr.x));
                col += _LitColor.rgb * cr.y * 0.15 * lit;
                col *= lerp(1, _Emission, lit);                                   // only the lit side blooms
                float fresG = 1 - saturate(dot(Ng, i.viewWS));
                float rim = pow(1 - saturate(dot(N, i.viewWS)), _RimPower);
                float rimBand = smoothstep(0.5 - fwidth(rim) - 0.02, 0.5 + fwidth(rim) + 0.02, rim);    // flat toon band
                col += _RimColor.rgb * _GlowMul * lerp(rim, rimBand * 0.6, _RimBand) * lerp(0.35, 1, lit);
                // ink outline along the silhouette (geometric normal, so the normal map does not break it)
                float ow = fwidth(fresG) + 0.005;
                col = lerp(col, _OutlineColor.rgb, smoothstep(1 - _OutlineWidth - ow, 1 - _OutlineWidth + ow, fresG) * step(1e-4, _OutlineWidth));
                return half4(col, 1);
            }
            ENDHLSL
        }

        // depth for the depth prepass (depth priming tests the forward pass Equal: without this the moon disappears),
        // with the same camera shrink
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On ColorMask R Cull Back
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half _BumpScale;
                float4 _AORange;
                half _OcclusionStrength, _MidThreshold;
                half4 _MidColor;
                half _Flatten, _MariaThreshold, _CraterAOThreshold, _RimLightThreshold, _NormalBlur, _OutlineWidth, _RimBand;
                half4 _HighlandColor, _MariaColor, _CraterFloorColor, _RimLightColor, _OutlineColor;
                half4 _LitColor, _ShadowColor, _CraterColor, _RimColor;
                half _Threshold, _Softness, _CraterScale, _CraterAmount, _RimPower, _Emission;
                half _Smooth, _Wrap;
                float4 _PhaseDir;
                float _CameraShrink, _GlowMul;
            CBUFFER_END
            float4 vert(float4 positionOS : POSITION) : SV_POSITION
            {
                float3 ws = TransformObjectToWorld(positionOS.xyz);
                return TransformWorldToHClip(_WorldSpaceCameraPos + (ws - _WorldSpaceCameraPos) * _CameraShrink);
            }
            half frag() : SV_Target { return 0; }
            ENDHLSL
        }

        // SSAO makes URP prime depth from the DepthNormals prepass, so the moon needs this one too
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }
            ZWrite On Cull Back
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half _BumpScale;
                float4 _AORange;
                half _OcclusionStrength, _MidThreshold;
                half4 _MidColor;
                half _Flatten, _MariaThreshold, _CraterAOThreshold, _RimLightThreshold, _NormalBlur, _OutlineWidth, _RimBand;
                half4 _HighlandColor, _MariaColor, _CraterFloorColor, _RimLightColor, _OutlineColor;
                half4 _LitColor, _ShadowColor, _CraterColor, _RimColor;
                half _Threshold, _Softness, _CraterScale, _CraterAmount, _RimPower, _Emission;
                half _Smooth, _Wrap;
                float4 _PhaseDir;
                float _CameraShrink, _GlowMul;
            CBUFFER_END
            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 normalWS : TEXCOORD0; };
            Varyings vert(Attributes input)
            {
                Varyings o;
                float3 ws = TransformObjectToWorld(input.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(_WorldSpaceCameraPos + (ws - _WorldSpaceCameraPos) * _CameraShrink);
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return o;
            }
            half4 frag(Varyings i) : SV_Target
            {
            #if defined(_GBUFFER_NORMALS_OCT)
                float2 oct = PackNormalOctQuadEncode(normalize(i.normalWS));
                return half4(PackFloat2To888(saturate(oct * 0.5 + 0.5)), 0);
            #else
                return half4(NormalizeNormalPerPixel(i.normalWS), 0);
            #endif
            }
            ENDHLSL
        }
    }
}
