// Toon wicker for woven props (basket LOD): the SDCat / ToonStem two-tone ramp (threshold / softness / ambient,
// cloud + toon cast shadow, 3-tone shadow form lift) + inverted-hull outline, driven by a tangent-space normal map
// and a stepped AO map from the Substance Designer Wicker_Weave graph. Ramp values are the shared research values;
// the AO step and relief numbers are my own (matched to the Blender Wicker_Toon preview, 2026-10-13).
Shader "DSEWA/ToonWicker"
{
    Properties
    {
        _BaseMap ("Base Color", 2D) = "white" {}
        _LitColor ("Lit Color", Color) = (0.80, 0.58, 0.32, 1)
        _ShadowColor ("Shadow Color", Color) = (0.46, 0.36, 0.25, 1)
        _Threshold ("Shadow Threshold", Range(-1, 1.5)) = 0.393
        _Softness ("Shadow Edge Width", Range(0.001, 0.3)) = 0.053
        _ShadowBlur ("Cast Shadow Smoothing (texels, 0 = URP)", Range(0, 4)) = 1.5
        _AmbientShade ("Ambient Shade", Range(0, 1)) = 0.105
        _ShadowFormLift ("Lit Side Lift In Shadow", Range(0, 1)) = 0.45
        _LightColorAmount ("Light Color Influence", Range(0, 1)) = 0
        [Header(Weave Maps)]
        [Normal][NoScaleOffset] _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Strength", Float) = 0.8
        [NoScaleOffset] _OcclusionMap ("AO Map", 2D) = "white" {}
        _AOThreshold ("AO Step (gaps below this go dark)", Range(0, 1)) = 0.45
        _AOSoftness ("AO Step Width", Range(0.001, 0.3)) = 0.05
        _AOColor ("Gap Color (multiply)", Color) = (0.35, 0.30, 0.25, 1)
        // Wind mask comes from vertex colour: R = 0 still -> 1 tip, G = phase (same bend as ToonFoliage)
        [Header(Wind Vertex Colour R Amount G Phase)]
        [Toggle] _WindEnable ("Wind", Float) = 0
        _WindDir ("Wind Direction (xz)", Vector) = (1, 0, 0.35, 0)
        _WindStrength ("Wind Strength (m)", Float) = 0.04
        _WindSpeed ("Wind Speed", Float) = 1.6
        _WindFreq ("Wind Wave Frequency", Float) = 0.35
        [Header(Relief (lit side detail, independent of cast shadow))]
        _ReliefAmount ("Relief Amount", Range(0, 1)) = 0.4
        _ReliefSteps ("Relief Steps", Range(1, 4)) = 3
        _NormalInRamp ("Weave Normal In Toon Ramp", Range(0, 1)) = 0.6
        [Header(Rim)]
        _RimColor ("Rim Color", Color) = (0.25, 0.22, 0.18, 1)
        _RimStrength ("Rim Strength", Range(0, 1)) = 0.5
        _RimMin ("Rim Start", Range(0, 1)) = 0.78
        _RimMax ("Rim End", Range(0, 1)) = 0.84
        _RimInShadow ("Rim In Shadow", Range(0, 1)) = 0.6
        [Header(Emission (mask R lights up, tinted by the base colour))]
        [NoScaleOffset] _EmissionMap ("Emission Mask", 2D) = "black" {}
        [HDR] _EmissionColor ("Emission Color", Color) = (0, 0, 0, 1)
        _EmissionPulse ("Emission Breath (0 = steady)", Range(0, 1)) = 0
        _EmissionPeriod ("Breath Period (s)", Range(0.5, 20)) = 5
        [Header(Outline)]
        _OutlineColor ("Outline Color", Color) = (0.22, 0.16, 0.10, 1)
        _OutlineWidth ("Outline Width (m)", Float) = 0.006
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _LitColor, _ShadowColor;
            half _Threshold, _Softness, _ShadowBlur, _AmbientShade, _ShadowFormLift, _LightColorAmount;
            half _BumpScale, _AOThreshold, _AOSoftness, _ReliefAmount, _ReliefSteps, _NormalInRamp;
            float4 _WindDir;
            float _WindEnable, _WindStrength, _WindSpeed, _WindFreq;
            half4 _AOColor;
            half4 _RimColor;
            half _RimStrength, _RimMin, _RimMax, _RimInShadow;
            half4 _EmissionColor;
            half _EmissionPulse, _EmissionPeriod;
            half4 _OutlineColor;
            float _OutlineWidth;
        CBUFFER_END

        // ToonFoliage's FoliageBend (research values), gated by _WindEnable: offset ∝ color.r², wind wave in world xz.
        float3 PropWindBend(float3 positionWS, float4 color)
        {
            if (_WindEnable < 0.5) return positionWS;
            float h = color.r * color.r;
            float2 dir = normalize(_WindDir.xz + 1e-5);
            float phase = _Time.y * _WindSpeed + color.g * 6.2832 + dot(positionWS.xz, dir) * _WindFreq;
            float2 offset = dir * (sin(phase) * 0.7 + sin(phase * 2.3 + 1.7) * 0.3) * _WindStrength * h;
            positionWS.xz += offset;
            return positionWS;
        }
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
            TEXTURE2D(_EmissionMap);
            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);
            TEXTURE2D(_OcclusionMap); SAMPLER(sampler_OcclusionMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
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
                half fogFactor : TEXCOORD3;
                float4 tangentWS : TEXCOORD4;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                VertexNormalInputs nrm = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                float3 positionWS = PropWindBend(TransformObjectToWorld(input.positionOS.xyz), input.color);
                o.positionCS = TransformWorldToHClip(positionWS);
                o.positionWS = positionWS;
                o.normalWS = nrm.normalWS;
                o.tangentWS = float4(nrm.tangentWS, input.tangentOS.w * GetOddNegativeScale());
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 Ng = normalize(i.normalWS);
                float3 bitangent = i.tangentWS.w * cross(Ng, i.tangentWS.xyz);
                half3 nTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.uv), _BumpScale);
                float3 N = normalize(TransformTangentToWorld(nTS, float3x3(i.tangentWS.xyz, bitangent, Ng)));
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);

                Light light = GetMainLight();
                half direct = ToonMainLightShadow(i.positionWS, _ShadowBlur) * EvaluateCloudShadow(i.positionWS);
                // Two-tone ramp on the smooth surface normal: the cast shadow stays one clean step
                float ndlG = saturate(dot(Ng, light.direction));
                float ndlN = saturate(dot(N, light.direction));
                // Weave normal pushed into the ramp input so the strands band on the lit side like the Blender preview
                float ndlR = lerp(ndlG, ndlN, _NormalInRamp);
                float shade = ndlR * direct + _AmbientShade;
                float lit = smoothstep(_Threshold, _Threshold + _Softness, shade);
                float facesLight = smoothstep(_Threshold, _Threshold + _Softness, shade - ndlR * (direct - 1));
                float tone = lit + (facesLight - lit) * _ShadowFormLift;

                half3 base = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb;
                half3 color = lerp(_ShadowColor.rgb, _LitColor.rgb, tone) * base;
                // Relief: N.L of the weave normal, quantised, multiplied everywhere so the strands keep their
                // up/down inside cast shadows instead of flattening into a cut-out.
                float relief = floor(ndlN * _ReliefSteps + 0.5) / _ReliefSteps;
                color *= 1.0 - _ReliefAmount * (1.0 - relief);
                // AO: one hard step so only the gaps between strands go dark
                half ao = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, i.uv).r;
                float gap = 1.0 - smoothstep(_AOThreshold - _AOSoftness, _AOThreshold + _AOSoftness, ao);
                color *= lerp(half3(1, 1, 1), _AOColor.rgb, gap);

                float facing = 1.0 - abs(dot(N, V));
                color += _RimColor.rgb * smoothstep(_RimMin, _RimMax, facing) * _RimStrength * lerp(_RimInShadow, 1, lit);
                color *= lerp(half3(1, 1, 1), light.color, _LightColorAmount);
                // emission: painted glass etc. glows in its own (base) colour, independent of light and shadow
                half emask = SAMPLE_TEXTURE2D(_EmissionMap, sampler_BaseMap, i.uv).r;
                half breath = 1.0 - _EmissionPulse * (0.5 - 0.5 * sin(_Time.y * TWO_PI / max(_EmissionPeriod, 0.01)));
                color += base * _EmissionColor.rgb * emask * breath;
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
                float4 color : COLOR;
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
                float3 positionWS = PropWindBend(TransformObjectToWorld(input.positionOS.xyz), input.color);
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

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float4 color : COLOR; UNITY_VERTEX_INPUT_INSTANCE_ID };

            float4 vert(Attributes input) : SV_POSITION
            {
                UNITY_SETUP_INSTANCE_ID(input);
                float3 positionWS = PropWindBend(TransformObjectToWorld(input.positionOS.xyz), input.color);
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

            struct Attributes { float4 positionOS : POSITION; float4 color : COLOR; UNITY_VERTEX_INPUT_INSTANCE_ID };

            float4 vert(Attributes input) : SV_POSITION
            {
                UNITY_SETUP_INSTANCE_ID(input);
                return TransformWorldToHClip(PropWindBend(TransformObjectToWorld(input.positionOS.xyz), input.color));
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

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float4 color : COLOR; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; float3 normalWS : TEXCOORD0; };

            Varyings vert(Attributes input)
            {
                UNITY_SETUP_INSTANCE_ID(input);
                Varyings o;
                o.positionCS = TransformWorldToHClip(PropWindBend(TransformObjectToWorld(input.positionOS.xyz), input.color));
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
