// Lantern-fruit shell: the same two-tone toon ramp as SDCatToon (threshold / softness / ambient, cloud + toon
// cast shadow), drawn as a translucent surface so the emissive glow sphere inside shows through.
// Ramp values are the research values shared with SDCat_Body; the glow / alpha / rim numbers below are my own.
// No inverted-hull outline: a hull drawn after the opaques would show through the translucent shell, so the
// edge line is a fresnel band instead (RimLine*).
Shader "DSEWA/ToonLanternShell"
{
    Properties
    {
        _BaseMap ("Base Color", 2D) = "white" {}
        _LitColor ("Lit Color", Color) = (1.0, 0.72, 0.38, 1)
        _ShadowColor ("Shadow Color", Color) = (0.78, 0.40, 0.36, 1)
        _Threshold ("Shadow Threshold", Range(-1, 1.5)) = 0.393
        _Softness ("Shadow Edge Width", Range(0.001, 0.3)) = 0.053
        _ShadowBlur ("Cast Shadow Smoothing (texels, 0 = URP)", Range(0, 4)) = 1.5
        _AmbientShade ("Ambient Shade", Range(0, 1)) = 0.105
        _ShadowFormLift ("Lit Side Lift In Shadow", Range(0, 1)) = 0.45
        _LightColorAmount ("Light Color Influence", Range(0, 1)) = 0
        [Header(Translucency)]
        [HDR] _GlowColor ("Inner Glow Color", Color) = (1.0, 0.70, 0.30, 1)
        _GlowStrength ("Inner Glow Strength", Range(0, 4)) = 1.2
        _GlowPower ("Inner Glow Falloff (centre -> edge)", Range(0.5, 8)) = 2.0
        _GlowInShadow ("Glow Visible In Shadow", Range(0, 1)) = 1
        _GlowCentre ("Glow Centre (object space xyz)", Vector) = (0, -1.0, 0, 0)
        _GlowRadius ("Glow Reach (object units)", Float) = 1.3
        _GlowViewMix ("View Facing Mix (0 = pure radial)", Range(0, 1)) = 0.25
        _RayCount ("Ray Count (0 = off)", Float) = 8
        _RayAmount ("Ray Amount", Range(0, 1)) = 0.35
        _RaySharpness ("Ray Sharpness", Range(0.5, 8)) = 2.0
        _RaySpin ("Ray Spin (turns/s)", Float) = 0.02
        [Header(Volume)]
        [HDR] _GlowOuterColor ("Outer Glow Color (edge of the spread)", Color) = (0.85, 0.45, 0.75, 1)
        _GlowWide ("Wide Layer Strength", Range(0, 3)) = 0.7
        _GlowWideRadius ("Wide Layer Reach (object units)", Float) = 2.2
        _PulseAmount ("Breathing Amount", Range(0, 1)) = 0.18
        _PulseSpeed ("Breathing Speed (cycles/s)", Float) = 0.35
        [Header(Halo)]
        [HDR] _HaloColor ("Halo Color", Color) = (1.0, 0.62, 0.45, 1)
        _HaloSize ("Halo Size (object units)", Float) = 0.35
        _HaloStrength ("Halo Strength", Range(0, 3)) = 0.9
        _HaloPower ("Halo Softness (higher = tighter)", Range(0.5, 8)) = 2.5
        _AlphaCentre ("Alpha At Centre", Range(0, 1)) = 0.55
        _AlphaEdge ("Alpha At Edge", Range(0, 1)) = 1.0
        _AlphaPower ("Alpha Falloff", Range(0.5, 8)) = 2.5
        [Header(Edge Line)]
        _RimLineColor ("Edge Line Color", Color) = (0.45, 0.18, 0.22, 1)
        _RimLineMin ("Edge Line Start", Range(0, 1)) = 0.80
        _RimLineMax ("Edge Line End", Range(0, 1)) = 0.86
        _RimLineStrength ("Edge Line Strength", Range(0, 1)) = 0.85
        [Header(Iridescent Rim)]
        [HDR] _IriColorA ("Rim Color A (cyan side)", Color) = (0.45, 1.0, 0.95, 1)
        [HDR] _IriColorB ("Rim Color B (pink side)", Color) = (1.0, 0.45, 0.85, 1)
        _IriStrength ("Rim Glow Strength (0 = off)", Range(0, 4)) = 0
        _IriMin ("Rim Start (fresnel)", Range(0, 1)) = 0.45
        _IriMax ("Rim End (fresnel)", Range(0, 1)) = 0.95
        _IriBands ("Colour Bands Around", Float) = 1.0
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline" "Queue" = "Transparent" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _LitColor, _ShadowColor;
            half _Threshold, _Softness, _ShadowBlur, _AmbientShade, _ShadowFormLift, _LightColorAmount;
            half4 _GlowColor;
            half _GlowStrength, _GlowPower, _GlowInShadow;
            float4 _GlowCentre;
            half _GlowRadius, _GlowViewMix, _RayCount, _RayAmount, _RaySharpness, _RaySpin;
            half4 _GlowOuterColor, _HaloColor;
            half _GlowWide, _GlowWideRadius, _PulseAmount, _PulseSpeed, _HaloSize, _HaloStrength, _HaloPower;
            half _AlphaCentre, _AlphaEdge, _AlphaPower;
            half4 _RimLineColor;
            half _RimLineMin, _RimLineMax, _RimLineStrength;
            half4 _IriColorA, _IriColorB;
            half _IriStrength, _IriMin, _IriMax, _IriBands;
        CBUFFER_END

        // Per-object breathing: each fruit pulses out of phase (phase from its world position).
        half LanternPulse()
        {
            float3 wp = float3(UNITY_MATRIX_M._m03, UNITY_MATRIX_M._m13, UNITY_MATRIX_M._m23);
            float phase = frac(dot(wp, float3(12.9898, 78.233, 37.719)) * 0.1);
            return 1.0 + _PulseAmount * sin((_Time.y * _PulseSpeed + phase) * 6.2831853);
        }
        ENDHLSL

        // Additive aura: the shell inflated along its normals, brightest over the fruit, fading to nothing at the
        // inflated rim, so a soft light volume hangs around each lantern. Drawn before the shell pass.
        Pass
        {
            Name "Halo"
            Tags { "LightMode" = "SRPDefaultUnlit" }
            Blend One One
            ZWrite Off
            Cull Back

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
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 positionOS : TEXCOORD2;
                half fogFactor : TEXCOORD3;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                float3 posOS = input.positionOS.xyz + normalize(input.normalOS) * _HaloSize;
                VertexPositionInputs pos = GetVertexPositionInputs(posOS);
                o.positionCS = pos.positionCS;
                o.positionWS = pos.positionWS;
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                o.positionOS = input.positionOS.xyz;
                o.fogFactor = ComputeFogFactor(pos.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float facing = saturate(dot(N, V));
                float d = length(i.positionOS - _GlowCentre.xyz);
                float radial = saturate(1.0 - d / max(_GlowWideRadius, 0.001));
                half a = pow(facing, _HaloPower) * radial * radial * _HaloStrength * LanternPulse();
                half3 col = _HaloColor.rgb * a;
                col = MixFog(col, i.fogFactor) * 1.0;   // fog darkens the aura with distance like everything else
                return half4(col, 1);
            }
            ENDHLSL
        }

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
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Art/Environment/Shaders/CloudShadow.hlsl"
            #include "Assets/Art/Environment/Shaders/ToonShadow.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

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
                float3 positionOS : TEXCOORD4;
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
                o.positionOS = input.positionOS.xyz;
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                o.fogFactor = ComputeFogFactor(pos.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);

                Light light = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                half direct = ToonMainLightShadow(i.positionWS, _ShadowBlur) * EvaluateCloudShadow(i.positionWS);
                float ndl = saturate(dot(N, light.direction));
                float shade = ndl * direct + _AmbientShade;
                float lit = smoothstep(_Threshold, _Threshold + _Softness, shade);
                float facesLight = smoothstep(_Threshold, _Threshold + _Softness, shade - ndl * (direct - 1));
                float tone = lit + (facesLight - lit) * _ShadowFormLift;

                half3 base = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb;
                half3 color = lerp(_ShadowColor.rgb, _LitColor.rgb, tone) * base;
                color *= lerp(half3(1, 1, 1), light.color, _LightColorAmount);

                // Light from the sphere inside, spreading radially: falls off with the distance from the glow
                // centre (the sphere) to this point of the shell, optionally mixed with a view-facing term.
                // Rays: a cosine comb around the fruit's vertical axis, slowly spinning. Emission, so it also
                // survives the shadow side (scaled by _GlowInShadow).
                float facing = saturate(dot(N, V));
                float3 fromCentre = i.positionOS - _GlowCentre.xyz;
                float dist = length(fromCentre);
                float core = pow(saturate(1.0 - dist / max(_GlowRadius, 0.001)), _GlowPower);
                float wide = saturate(1.0 - dist / max(_GlowWideRadius, 0.001));
                wide *= wide;                                               // soft, long tail
                float rays = 1.0;
                if (_RayCount > 0.5)
                {
                    float ang = atan2(fromCentre.x, fromCentre.z) + _Time.y * _RaySpin * 6.2831853;
                    rays = lerp(1.0, pow(0.5 + 0.5 * cos(ang * _RayCount), _RaySharpness), _RayAmount);
                }
                half pulse = LanternPulse();
                float inShadow = lerp(_GlowInShadow, 1, lit);
                float gCore = lerp(core, core * facing, _GlowViewMix) * rays * _GlowStrength * pulse * inShadow;
                float gWide = wide * _GlowWide * pulse * inShadow;
                // core keeps the warm inner colour; the wide layer drifts to the outer tint away from the centre
                half3 wideCol = lerp(_GlowOuterColor.rgb, _GlowColor.rgb, core);
                color += _GlowColor.rgb * gCore + wideCol * gWide;

                // Edge line: a thin fresnel band darkened toward the line colour (replaces the hull outline).
                float fres = 1.0 - facing;
                float edgeLine = smoothstep(_RimLineMin, _RimLineMax, fres) * _RimLineStrength;
                color = lerp(color, _RimLineColor.rgb, edgeLine);

                // Iridescent rim: a soft emissive fresnel band whose colour slides from cyan to pink around the
                // fruit (by the screen-side direction of the normal and the height), like a soap-film edge.
                float iri = smoothstep(_IriMin, _IriMax, fres) * _IriStrength;
                float3 Vr = normalize(cross(float3(0, 1, 0), V) + 1e-4);
                float hue = 0.5 + 0.5 * sin((dot(N, Vr) * 1.6 + i.positionOS.y * 0.8) * 3.14159 * _IriBands);
                color += lerp(_IriColorA.rgb, _IriColorB.rgb, hue) * iri * pulse;

                // Translucent toward the centre so the glow sphere shows, solid at the silhouette.
                half alpha = lerp(_AlphaCentre, _AlphaEdge, pow(fres, _AlphaPower));
                alpha = max(alpha, edgeLine);

                color = MixFog(color, i.fogFactor);
                return half4(color, alpha);
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
    }
    FallBack Off
}
