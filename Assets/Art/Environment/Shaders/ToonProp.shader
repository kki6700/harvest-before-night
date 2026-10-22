// DSEWA/ToonProp: shared shader for textured props coming from AI generators (VARCO / Mixar: painted base colour with
// lighting already drawn in). Turns the painted texture into the scene's cel look so it sits next to the hand-made
// toon assets (crystals, lantern fruit, door):
//   1. Delight     - flatten the brightness painted into the texture, keep its hue / saturation (the cel ramp below
//                    does the shading, so shading is not doubled)
//   2. Posterize   - cut the remaining brightness into a few steps so it reads as flat colour areas
//   3. Palette     - remap the texture's brightness onto the scene palette (dark navy -> lavender -> sky) and blend
//                    that over the texture colour, so every generated asset lands in the same colour family
//   4. Same lighting language as the other DSEWA toon shaders: two-tone ramp, toon cast + cloud shadow, rim, ground
//      fog, inverted-hull outline (DSEWAOutline pass), DayNightBlend-friendly colour properties
//   5. Texture glow: the brightest painted parts (measured on the ORIGINAL texture) emit their own colour, with an
//      optional slow per-object breath
// All defaults are my own starting values.
Shader "DSEWA/ToonProp"
{
    Properties
    {
        _BaseMap ("Base Color", 2D) = "white" {}
        [Header(Texture Clean Up)]
        _Delight ("Remove Painted Shading", Range(0, 1)) = 0.7
        _DelightLevel ("Flattened Brightness", Range(0.2, 1)) = 0.75
        _PosterizeSteps ("Posterize Steps (0 = off)", Range(0, 8)) = 4
        _Saturation ("Saturation", Range(0, 2)) = 1
        [Header(Scene Palette)]
        _PaletteMix ("Palette Blend", Range(0, 1)) = 0.45
        _PaletteDark ("Palette Dark", Color) = (0.12, 0.14, 0.34, 1)
        _PaletteMid ("Palette Mid", Color) = (0.45, 0.45, 0.86, 1)
        _PaletteLight ("Palette Light", Color) = (0.76, 0.86, 1, 1)
        [Header(Toon Lighting)]
        _LitColor ("Lit Color", Color) = (1, 1, 1, 1)
        _ShadowColor ("Shadow Color", Color) = (0.42, 0.43, 0.72, 1)
        _Threshold ("Shadow Threshold", Range(-1, 1.5)) = 0.35
        _Softness ("Shadow Edge Width", Range(0.001, 0.3)) = 0.04
        _ShadowBlur ("Cast Shadow Smoothing (texels, 0 = URP)", Range(0, 4)) = 1.5
        _AmbientShade ("Ambient Shade", Range(0, 1)) = 0.1
        [ToggleUI] _ReceiveShadows ("Receive Shadows (cast + cloud)", Float) = 1
        _RimColor ("Rim Color", Color) = (0.75, 0.8, 1, 1)
        _RimStrength ("Rim Strength", Range(0, 1)) = 0.15
        _RimMin ("Rim Start", Range(0, 1)) = 0.78
        _RimMax ("Rim End", Range(0, 1)) = 0.84
        [Header(Texture Glow (bright painted parts))]
        _TexGlowStrength ("Texture Glow Strength (0 = off)", Range(0, 4)) = 0
        _TexGlowThreshold ("Brightness Where Glow Starts", Range(0, 1)) = 0.7
        _TexGlowSoftness ("Glow Edge Softness", Range(0.01, 0.5)) = 0.14
        [HDR] _TexGlowTint ("Texture Glow Tint", Color) = (1, 1, 1, 1)
        _TexGlowPulse ("Glow Min / Max Over The Breath (1, 1 = steady)", Vector) = (1, 1, 0, 0)
        _PulsePeriod ("Breath Period (s)", Range(0.2, 20)) = 4.5
        [Header(Outline)]
        _OutlineColor ("Outline Color", Color) = (0.1, 0.1, 0.26, 1)
        _OutlineWidth ("Outline Width (m at the model's own size, 0 = off)", Float) = 0.006
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half _Delight, _DelightLevel, _PosterizeSteps, _Saturation;
            half _PaletteMix;
            half4 _PaletteDark, _PaletteMid, _PaletteLight;
            half4 _LitColor, _ShadowColor;
            half _Threshold, _Softness, _ShadowBlur, _AmbientShade, _ReceiveShadows;
            half4 _RimColor;
            half _RimStrength, _RimMin, _RimMax;
            half _TexGlowStrength, _TexGlowThreshold, _TexGlowSoftness;
            half4 _TexGlowTint;
            float4 _TexGlowPulse;
            float _PulsePeriod;
            half4 _OutlineColor;
            float _OutlineWidth;
        CBUFFER_END
                // outline width is in metres at the model's own size: a prefab scaled to 0.18 gets a 0.18x line
        // (geometric mean of the object scale, so non-uniform boxes do not blow up)
        float OutlineObjectScale()
        {
            float3x3 m = (float3x3)GetObjectToWorldMatrix();
            return pow(abs(determinant(m)), 1.0 / 3.0);
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
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Assets/Art/Environment/Shaders/CloudShadow.hlsl"
            #include "Assets/Art/Environment/Shaders/ToonShadow.hlsl"
            #include "Assets/Art/Environment/Shaders/GroundFog.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                half fogFactor : TEXCOORD3;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                o.positionCS = pos.positionCS;
                o.positionWS = pos.positionWS;
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                o.fogFactor = ComputeFogFactor(pos.positionCS.z);
                return o;
            }

            half3 Palette(half t)
            {
                return t < 0.5 ? lerp(_PaletteDark.rgb, _PaletteMid.rgb, t * 2.0) : lerp(_PaletteMid.rgb, _PaletteLight.rgb, t * 2.0 - 1.0);
            }

            half4 frag(Varyings i, bool frontFace : SV_IsFrontFace) : SV_Target
            {
                half3 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb;
                half texV = max(tex.r, max(tex.g, tex.b));

                // 1 + 2: flatten the painted brightness, then posterize what is left
                half3 hsv = RgbToHsv(tex);
                hsv.z = lerp(hsv.z, _DelightLevel * (0.75 + 0.25 * hsv.z), _Delight);
                if (_PosterizeSteps >= 1) hsv.z = (floor(hsv.z * _PosterizeSteps) + 0.5) / _PosterizeSteps;
                hsv.y = saturate(hsv.y * _Saturation);
                half3 albedo = HsvToRgb(hsv);
                // 3: scene palette by the texture's own brightness (keeps light/dark areas of the painting)
                half pT = smoothstep(0.15, 0.9, texV);
                if (_PosterizeSteps >= 1) pT = (floor(pT * _PosterizeSteps) + 0.5) / _PosterizeSteps;
                albedo = lerp(albedo, Palette(pT) * (0.6 + 0.4 * albedo / max(max(albedo.r, max(albedo.g, albedo.b)), 1e-3)), _PaletteMix);

                // 4: toon ramp
                float3 N = normalize(i.normalWS) * (frontFace ? 1 : -1);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                Light light = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                half direct = lerp(1.0h, ToonMainLightShadow(i.positionWS, _ShadowBlur) * EvaluateCloudShadow(i.positionWS), _ReceiveShadows);
                float shade = saturate(dot(N, light.direction)) * direct + _AmbientShade;
                float lit = smoothstep(_Threshold, _Threshold + _Softness, shade);
                half3 color = lerp(_ShadowColor.rgb, _LitColor.rgb, lit) * albedo;
                color += _RimColor.rgb * smoothstep(_RimMin, _RimMax, 1.0 - saturate(dot(N, V))) * _RimStrength;

                // 5: glow from the original painting's brightest parts
                float3 objPos = GetObjectToWorldMatrix()._m03_m13_m23;
                float phase = frac(sin(dot(objPos, float3(12.9898, 78.233, 37.719))) * 43758.5453);
                float p01 = 0.5 + 0.5 * sin((_Time.y / max(_PulsePeriod, 0.01) + phase) * TWO_PI);
                float glowK = lerp(_TexGlowPulse.x, _TexGlowPulse.y, p01);
                // glow colour from the cleaned-up albedo (not the raw painting, which would paint every brush stroke back
                // in at 3x); the mask still comes from the painting so the patterns / petal rims are what lights up
                half3 glowCol = albedo / max(max(albedo.r, max(albedo.g, albedo.b)), 1e-3);
                half mask = smoothstep(_TexGlowThreshold, _TexGlowThreshold + _TexGlowSoftness, texV);
                if (_PosterizeSteps >= 1) mask = step(0.5, mask);   // hard-edged glow shapes, like painted cel highlights
                color += glowCol * _TexGlowTint.rgb * mask * _TexGlowStrength * 0.6 * glowK;

                color = ApplyGroundFog(color, i.positionWS);
                color = MixFog(color, i.fogFactor);
                return half4(color, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "Outline"
            // drawn by the outline RenderObjects feature (see DSEWA/ToonCharacter); width 0 = nothing visible
            Tags { "LightMode" = "DSEWAOutline" }
            Cull Front

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; half fogFactor : TEXCOORD0; UNITY_VERTEX_OUTPUT_STEREO };

            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                positionWS += TransformObjectToWorldNormal(input.normalOS) * _OutlineWidth * OutlineObjectScale();
                o.positionCS = TransformWorldToHClip(positionWS);
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target { return half4(MixFog(_OutlineColor.rgb, i.fogFactor), 1); }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; UNITY_VERTEX_INPUT_INSTANCE_ID };

            float4 vert(Attributes input) : SV_POSITION
            {
                UNITY_SETUP_INSTANCE_ID(input);
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDir = normalize(_LightPosition - positionWS);
            #else
                float3 lightDir = _LightDirection;
            #endif
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDir));
            #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                return positionCS;
            }

            half4 frag() : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On ColorMask R Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            struct Attributes { float4 positionOS : POSITION; UNITY_VERTEX_INPUT_INSTANCE_ID };

            float4 vert(Attributes input) : SV_POSITION
            {
                UNITY_SETUP_INSTANCE_ID(input);
                return TransformObjectToHClip(input.positionOS.xyz);
            }

            half frag() : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }
            ZWrite On Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; float3 normalWS : TEXCOORD0; };

            Varyings vert(Attributes input)
            {
                UNITY_SETUP_INSTANCE_ID(input);
                Varyings o;
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 n = normalize(i.normalWS);
            #if defined(_GBUFFER_NORMALS_OCT)
                float2 oct = PackNormalOctQuadEncode(n);
                return half4(PackFloat2To888(saturate(oct * 0.5 + 0.5)), 0);
            #else
                return half4(n, 0);
            #endif
            }
            ENDHLSL
        }
    }
}
