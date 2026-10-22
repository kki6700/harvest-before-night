// Toon stem / branch for plant props (lantern fruit): the SDCatToon two-tone ramp (threshold / softness / ambient,
// cloud + toon cast shadow, 3-tone shadow form lift) with the inverted-hull outline, minus the fur / mouth / tuft
// code. Mesh inputs (Blender curve -> mesh): UV0.x = around the stem 0..1, UV0.y = along the spline 0 base -> 1 tip.
// Ramp values are the research values shared with SDCat_Body; gradient, ridge, rim and outline numbers are my own.
Shader "DSEWA/ToonStem"
{
    Properties
    {
        _BaseMap ("Base Color", 2D) = "white" {}
        _LitColor ("Lit Color", Color) = (0.30, 0.27, 0.66, 1)
        _ShadowColor ("Shadow Color", Color) = (0.12, 0.10, 0.35, 1)
        _Threshold ("Shadow Threshold", Range(-1, 1.5)) = 0.393
        _Softness ("Shadow Edge Width", Range(0.001, 0.3)) = 0.053
        _ShadowBlur ("Cast Shadow Smoothing (texels, 0 = URP)", Range(0, 4)) = 1.5
        _AmbientShade ("Ambient Shade", Range(0, 1)) = 0.105
        _ShadowFormLift ("Lit Side Lift In Shadow", Range(0, 1)) = 0.45
        _LightColorAmount ("Light Color Influence", Range(0, 1)) = 0
        [Header(Paint Detail)]
        _PaintMap ("Paint Detail (linear grey, 0.5 = none)", 2D) = "grey" {}
        _PaintStrength ("Paint Strength (0 = off)", Range(0, 2)) = 0
        [Header(Glow Lines)]
        _GlowMap ("Glow Lines (stem uv, r = line)", 2D) = "black" {}
        [HDR] _GlowColor ("Glow Color", Color) = (0.55, 0.75, 1.0, 1)
        _GlowStrength ("Glow Strength (0 = off)", Range(0, 4)) = 0
        _GlowFlowSpeed ("Glow Flow Speed (pulses up the stem)", Float) = 0.35
        _GlowFlowAmount ("Glow Flow Amount", Range(0, 1)) = 0.45
        [Header(Length Gradient)]
        _BaseTint ("Base Tint (multiply at uv.y 0)", Color) = (0.55, 0.50, 0.80, 1)
        _GradientEnd ("Gradient End (uv.y)", Range(0.01, 1)) = 0.35
        _TipTint ("Tip Tint (multiply at uv.y 1)", Color) = (1.15, 1.08, 1.25, 1)
        _TipStart ("Tip Start (uv.y)", Range(0, 1)) = 0.75
        [Header(Ridges)]
        _RidgeCount ("Ridge Count (around)", Float) = 4
        _RidgeAmount ("Ridge Shade Amount", Range(0, 1)) = 0.18
        _RidgeSharpness ("Ridge Sharpness", Range(0.5, 8)) = 1.5
        _RidgeTwist ("Ridge Twist (turns along length)", Float) = 0.5
        [Header(Rim)]
        _RimColor ("Rim Color", Color) = (0.55, 0.62, 1.0, 1)
        _RimStrength ("Rim Strength", Range(0, 1)) = 0.25
        _RimMin ("Rim Start", Range(0, 1)) = 0.78
        _RimMax ("Rim End", Range(0, 1)) = 0.84
        _RimInShadow ("Rim In Shadow", Range(0, 1)) = 0.6
        [Header(Outline)]
        _OutlineColor ("Outline Color", Color) = (0.06, 0.05, 0.20, 1)
        _OutlineWidth ("Outline Width (m)", Float) = 0.006
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST, _PaintMap_ST;
            half _PaintStrength;
            float4 _GlowMap_ST; half4 _GlowColor; half _GlowStrength, _GlowFlowSpeed, _GlowFlowAmount;
            half4 _LitColor, _ShadowColor;
            half _Threshold, _Softness, _ShadowBlur, _AmbientShade, _ShadowFormLift, _LightColorAmount;
            half4 _BaseTint, _TipTint;
            half _GradientEnd, _TipStart;
            half _RidgeCount, _RidgeAmount, _RidgeSharpness, _RidgeTwist;
            half4 _RimColor;
            half _RimStrength, _RimMin, _RimMax, _RimInShadow;
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
            #include "Assets/Art/Environment/Shaders/CloudShadow.hlsl"
            #include "Assets/Art/Environment/Shaders/ToonShadow.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_PaintMap); SAMPLER(sampler_PaintMap);
            TEXTURE2D(_GlowMap); SAMPLER(sampler_GlowMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

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

            half4 frag(Varyings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);

                Light light = GetMainLight();
                half direct = ToonMainLightShadow(i.positionWS, _ShadowBlur) * EvaluateCloudShadow(i.positionWS);
                float ndl = saturate(dot(N, light.direction));
                // Ridges: a cosine comb around the stem (uv.x), slowly twisting along the length, nudges the ramp
                // input so the toon edge wobbles into lobes like the fruit's four ribs.
                float ridge = 0.5 + 0.5 * cos((i.uv.x * _RidgeCount + i.uv.y * _RidgeTwist * _RidgeCount) * 6.2831853);
                ridge = pow(ridge, _RidgeSharpness);
                float shade = ndl * direct + _AmbientShade - (1.0 - ridge) * _RidgeAmount * 0.5;
                float lit = smoothstep(_Threshold, _Threshold + _Softness, shade);
                float facesLight = smoothstep(_Threshold, _Threshold + _Softness, shade - ndl * (direct - 1));
                float tone = lit + (facesLight - lit) * _ShadowFormLift;

                half3 base = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb;
                half3 color = lerp(_ShadowColor.rgb, _LitColor.rgb, tone) * base;
                // Length gradient: darker, duller base; a touch lighter toward the tips.
                color *= lerp(_BaseTint.rgb, half3(1, 1, 1), smoothstep(0.0, _GradientEnd, i.uv.y));
                color *= lerp(half3(1, 1, 1), _TipTint.rgb, smoothstep(_TipStart, 1.0, i.uv.y));
                // Hand-painted detail (bark strokes): grey 0.5 leaves the colour alone
                half3 paint = SAMPLE_TEXTURE2D(_PaintMap, sampler_PaintMap, i.uv * _PaintMap_ST.xy + _PaintMap_ST.zw).rgb;
                color *= lerp(half3(1, 1, 1), paint * 2.0h, _PaintStrength);
                // Ridge shading on the colour as well (flat multiply, so it shows in the shadow side too)
                color *= 1.0 - (1.0 - ridge) * _RidgeAmount;

                float facing = 1.0 - abs(dot(N, V));
                color += _RimColor.rgb * smoothstep(_RimMin, _RimMax, facing) * _RimStrength * lerp(_RimInShadow, 1, lit);
                color *= lerp(half3(1, 1, 1), light.color, _LightColorAmount);
                // Glow lines: thin light streaks along the stem; a soft pulse travels from the root to the tips
                half glow = SAMPLE_TEXTURE2D(_GlowMap, sampler_GlowMap, i.uv * _GlowMap_ST.xy + _GlowMap_ST.zw).r;
                half flow = 1.0 - _GlowFlowAmount * (0.5 + 0.5 * sin((i.uv.y * 3.0 - _Time.y * _GlowFlowSpeed) * 6.2831853));
                color += _GlowColor.rgb * glow * flow * _GlowStrength;
                color = MixFog(color, i.fogFactor);
                return half4(color, 1);
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

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                half fogFactor : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                positionWS += normalWS * _OutlineWidth * OutlineObjectScale();
                o.positionCS = TransformWorldToHClip(positionWS);
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                return half4(MixFog(_OutlineColor.rgb, i.fogFactor), 1);
            }
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
                return half4(PackFloat2To888(saturate(PackNormalOctQuadEncode(n) * 0.5 + 0.5)), 0);
            #else
                return half4(n, 0);
            #endif
            }
            ENDHLSL
        }
    }
    FallBack Off
}
