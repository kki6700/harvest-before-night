// DSEWA/ToonSoft: "chewy" pastel shading for props (the soft clay / gummy look of the Mixar renders of the Varco props),
// next to the hard two-tone DSEWA toon shaders.
//   - wrapped light with a wide, soft terminator (no hard cel step)
//   - sky / ground ambient: up-facing surfaces catch the sky colour, so top and sides separate even in shadow
//   - pastel base (lifted toward white) and a deeper, more saturated shadow (light seems to sink into the material)
//   - a round, soft-edged gloss blob from the main light plus one that follows the view (always visible, like a toy
//     under studio light), and a soft rim
//   - main-light colour, toon cast + cloud shadow, ground fog, inverted-hull outline, depth passes for the forced depth
//     priming + SSAO DepthNormals prepass (without them an opaque shader is not drawn here)
// All defaults are my own starting values.
Shader "DSEWA/ToonSoft"
{
    Properties
    {
        _BaseMap ("Base Map (optional)", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (0.6, 0.8, 0.8, 1)
        _Pastel ("Pastel (lift toward white)", Range(0, 1)) = 0.25
        [Header(Surface Detail)]
        [Normal] _BumpMap ("Normal Map (optional, OpenGL, same tiling as the base map)", 2D) = "bump" {}
        _BumpScale ("Normal Strength", Range(0, 2)) = 1
        _OcclusionMap ("Occlusion Map (optional)", 2D) = "white" {}
        _OcclusionStrength ("Occlusion On Ambient", Range(0, 1)) = 1
        _OcclusionDirect ("Occlusion On Direct Light", Range(0, 1)) = 0.5
        [Header(Soft Light)]
        _Wrap ("Light Wrap", Range(0, 1)) = 0.5
        _Softness ("Terminator Softness", Range(0.01, 0.5)) = 0.3
        _ShadowTint ("Shadow Tint", Color) = (0.62, 0.6, 0.9, 1)
        _ShadowSaturation ("Shadow Saturation", Range(0.5, 2)) = 1.3
        _LightColorAmount ("Light Color Influence", Range(0, 1)) = 0.5
        _PointLightStrength ("Point / Spot Light Strength (0 = main light only)", Range(0, 2)) = 1
        [ToggleUI] _ReceiveShadows ("Receive Shadows (cast + cloud)", Float) = 1
        _ShadowBlur ("Cast Shadow Smoothing (texels)", Range(0, 4)) = 1.5
        [Header(Sky and Ground Ambient)]
        _SkyColor ("Sky Color (up)", Color) = (0.72, 0.78, 1, 1)
        _GroundColor ("Ground Color (down)", Color) = (0.3, 0.26, 0.45, 1)
        _AmbientStrength ("Ambient Strength", Range(0, 1)) = 0.4
        [ToggleUI] _SceneAmbient ("Use The Scene's Ambient (not the colours above)", Float) = 0
        [Header(Gloss Blob)]
        _GlossColor ("Gloss Color", Color) = (1, 1, 1, 1)
        _GlossSize ("Gloss Size", Range(0.001, 0.3)) = 0.06
        _GlossSoftness ("Gloss Edge Softness", Range(0.001, 0.2)) = 0.04
        _GlossStrength ("Gloss From The Light", Range(0, 2)) = 0.5
        _ViewGloss ("Gloss Following The View", Range(0, 2)) = 0.35
        [Header(Rim)]
        _RimColor ("Rim Color", Color) = (0.85, 0.9, 1, 1)
        _RimStrength ("Rim Strength", Range(0, 1)) = 0.3
        _RimPower ("Rim Falloff", Range(0.5, 8)) = 2.5
        [Header(Emission)]
        [HDR] _EmissionColor ("Emission", Color) = (0, 0, 0, 1)
        _TexGlowStrength ("Texture Glow Strength (bright map parts, 0 = off)", Range(0, 4)) = 0
        _TexGlowThreshold ("Brightness Where Glow Starts", Range(0, 1)) = 0.5
        _TexGlowSoftness ("Glow Edge Softness", Range(0.01, 0.5)) = 0.2
        _TexGlowPulse ("Glow Min / Max Over The Breath (1, 1 = steady)", Vector) = (1, 1, 0, 0)
        [NoScaleOffset] _GlowMask ("Texture Glow Mask (optional, white = may glow)", 2D) = "white" {}
        _PulsePeriod ("Breath Period (s)", Range(0.2, 20)) = 4.5
        [Header(Outline)]
        _OutlineColor ("Outline Color", Color) = (0.1, 0.1, 0.26, 1)
        _OutlineWidth ("Outline Width (m at the model's own size, 0 = off)", Float) = 0.004
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            half _Pastel, _Wrap, _Softness;
            half _BumpScale, _OcclusionStrength, _OcclusionDirect;
            half4 _ShadowTint;
            half _ShadowSaturation, _LightColorAmount, _ReceiveShadows, _ShadowBlur;
            half _PointLightStrength;
            half4 _SkyColor, _GroundColor;
            half _AmbientStrength;
            half _SceneAmbient;
            half4 _GlossColor;
            half _GlossSize, _GlossSoftness, _GlossStrength, _ViewGloss;
            half4 _RimColor;
            half _RimStrength, _RimPower;
            half4 _EmissionColor;
            half _TexGlowStrength, _TexGlowThreshold, _TexGlowSoftness;
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
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Assets/Art/Environment/Shaders/CloudShadow.hlsl"
            #include "Assets/Art/Environment/Shaders/ToonShadow.hlsl"
            #include "Assets/Art/Environment/Shaders/GroundFog.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);
            TEXTURE2D(_OcclusionMap); SAMPLER(sampler_OcclusionMap);
            TEXTURE2D(_GlowMask); SAMPLER(sampler_GlowMask);

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float4 tangentOS : TANGENT; float2 uv : TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                half fogFactor : TEXCOORD3;
                float4 tangentWS : TEXCOORD4;   // w = bitangent sign
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
                VertexNormalInputs n = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                o.normalWS = n.normalWS;
                o.tangentWS = float4(n.tangentWS, input.tangentOS.w * GetOddNegativeScale());
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                o.fogFactor = ComputeFogFactor(p.positionCS.z);
                return o;
            }

            half Blob(half nDotH)   // round soft-edged highlight
            {
                return smoothstep(1.0 - _GlossSize - _GlossSoftness, 1.0 - _GlossSize + _GlossSoftness, nDotH);
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float3 Ngeo = normalize(i.normalWS);
                // normal map (planks bevel, grain ridges): bends the lighting only; the rim keeps the mesh normal
                half3 nTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.uv), _BumpScale);
                float3 bitangent = i.tangentWS.w * cross(Ngeo, i.tangentWS.xyz);
                float3 N = normalize(TransformTangentToWorld(nTS, float3x3(i.tangentWS.xyz, bitangent, Ngeo)));
                half occ = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, i.uv).r;
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                Light light = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                half shadow = lerp(1.0h, ToonMainLightShadow(i.positionWS, _ShadowBlur) * EvaluateCloudShadow(i.positionWS), _ReceiveShadows);

                half3 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb;
                half3 base = tex * _BaseColor.rgb;
                base = lerp(base, half3(1, 1, 1), _Pastel);

                // soft wrapped terminator
                half wrap = (dot(N, light.direction) + _Wrap) / (1.0 + _Wrap);
                half lit = smoothstep(0.5 - _Softness, 0.5 + _Softness, wrap) * shadow * lerp(1.0h, occ, _OcclusionDirect);

                // shadow side: tinted and more saturated, the colour "sinks in"
                half3 hsv = RgbToHsv(base * _ShadowTint.rgb);
                hsv.y = saturate(hsv.y * _ShadowSaturation);
                half3 shadowCol = HsvToRgb(hsv);
                half3 col = lerp(shadowCol, base, lit);
                col *= lerp(half3(1, 1, 1), light.color, _LightColorAmount);

                // point / spot lights (shop lamps): the same soft wrapped terminator, added in the light's own colour
                #if defined(_ADDITIONAL_LIGHTS) || defined(_ADDITIONAL_LIGHTS_VERTEX)
                {
                    InputData inputData = (InputData)0;
                    inputData.positionWS = i.positionWS;
                    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);
                    half3 addCol = 0;
                    uint pixelLightCount = GetAdditionalLightsCount();
                    LIGHT_LOOP_BEGIN(pixelLightCount)
                        Light al = GetAdditionalLight(lightIndex, i.positionWS);
                        half aw = (dot(N, al.direction) + _Wrap) / (1.0 + _Wrap);
                        half alit = smoothstep(0.5 - _Softness, 0.5 + _Softness, aw) * lerp(1.0h, occ, _OcclusionDirect);
                        addCol += base * al.color * (al.distanceAttenuation * al.shadowAttenuation * alit);
                    LIGHT_LOOP_END
                    col += addCol * _PointLightStrength;
                }
                #endif

                // sky above, ground below
                half3 hemi = lerp(_GroundColor.rgb, _SkyColor.rgb, N.y * 0.5 + 0.5);
                // or the scene's own ambient (spherical harmonics), so a prop dropped into another scene (the shop)
                // follows that scene's brightness instead of the field's night sky colours
                hemi = lerp(hemi, SampleSH(N), _SceneAmbient);
                col += base * hemi * _AmbientStrength * lerp(1.0h, occ, _OcclusionStrength);

                // gloss blobs: one from the main light, one from just above-left of the camera (always in view)
                half glossLight = Blob(saturate(dot(N, normalize(light.direction + V)))) * lit;
                float3 camUp = UNITY_MATRIX_V[1].xyz, camRight = UNITY_MATRIX_V[0].xyz;
                float3 viewKey = normalize(V + camUp * 0.55 - camRight * 0.35);
                half glossView = Blob(saturate(dot(N, normalize(viewKey + V))));
                col += _GlossColor.rgb * (glossLight * _GlossStrength * Luminance(light.color) + glossView * _ViewGloss);

                // soft rim
                col += _RimColor.rgb * pow(1.0 - saturate(dot(Ngeo, V)), _RimPower) * _RimStrength;
                col += _EmissionColor.rgb;
                // bright painted parts of the map glow in their own colour, breathing slowly per object
                float3 objPos = GetObjectToWorldMatrix()._m03_m13_m23;
                float phase = frac(sin(dot(objPos, float3(12.9898, 78.233, 37.719))) * 43758.5453);
                float breath = 0.5 + 0.5 * sin((_Time.y / max(_PulsePeriod, 0.01) + phase) * TWO_PI);
                half texLum = max(tex.r, max(tex.g, tex.b));
                // the optional mask limits the glow to painted strokes (white in the mask); default white = whole map
                half glowMask = SAMPLE_TEXTURE2D(_GlowMask, sampler_GlowMask, i.uv).r;
                col += tex * smoothstep(_TexGlowThreshold, _TexGlowThreshold + _TexGlowSoftness, texLum) * glowMask
                       * _TexGlowStrength * lerp(_TexGlowPulse.x, _TexGlowPulse.y, breath);

                col = ApplyGroundFog(col, i.positionWS);
                col = MixFog(col, i.fogFactor);
                return half4(col, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "Outline"
            Tags { "LightMode" = "DSEWAOutline" }
            Cull Front

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; half fogFactor : TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, o);
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                positionWS += TransformObjectToWorldNormal(input.normalOS) * _OutlineWidth * OutlineObjectScale();
                o.positionCS = TransformWorldToHClip(positionWS);
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }
            half4 frag(Varyings i) : SV_Target { UNITY_SETUP_INSTANCE_ID(i); return half4(MixFog(_OutlineColor.rgb, i.fogFactor), 1); }
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
