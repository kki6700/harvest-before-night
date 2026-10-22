// DSEWA/ToonAlienEye: big dark alien eye drawn procedurally on the eyeball cap (Cunsumer Eye.L / Eye.R).
// Eye mesh object space (as imported): +Z = gaze, +Y = up, sphere centre at the origin, radius 0.09 m.
// The look follows Desktop/Ref purple alien (2026-10-15): no white, a dark indigo iris filling the eye height,
// a darker pupil core, violet ring at the iris edge, lilac beyond it, upper-lid shade, a soft violet bounce at the
// bottom and two sticker highlights up/right of centre on screen (screen right = object -X, the character faces +Z).
// The renderer uses forced depth priming: every opaque pass needs DepthOnly + DepthNormals or it fails the
// depth-equal test and disappears. Colours sampled from the reference; sizes are fractions of the iris radius measured on it. Mostly unlit like
// DSEWA/SDCatEye (_EmissionMix); _Tint is driven by DayNightBlend so the eyes darken with the scene at night.
Shader "DSEWA/ToonAlienEye"
{
    Properties
    {
        _IrisColor ("Iris", Color) = (0.21, 0.22, 0.31, 1)
        _PupilColor ("Pupil", Color) = (0.11, 0.10, 0.19, 1)
        _RingColor ("Iris Ring", Color) = (0.51, 0.38, 0.67, 1)
        _OuterColor ("Outside Iris (lilac)", Color) = (0.62, 0.52, 0.71, 1)
        _BounceColor ("Lower Bounce", Color) = (0.36, 0.30, 0.52, 1)
        _HighlightColor ("Highlight", Color) = (1, 1, 1, 1)
        _IrisRadius ("Iris Radius (m, on the cap)", Float) = 0.022
        _PupilSize ("Pupil Size (x iris)", Range(0, 1)) = 0.55
        _RingWidth ("Ring Width (x iris)", Range(0, 0.5)) = 0.14
        _LidShade ("Upper Lid Shade", Range(0, 1)) = 0.35
        _LidShadeStart ("Lid Shade Start (x iris, up)", Range(-1, 1)) = 0.25
        _BounceAmount ("Lower Bounce", Range(0, 1)) = 0.45
        _HL1 ("Big Highlight (x, y, radius) x iris", Vector) = (-0.25, 0.30, 0.22, 0)
        _HL2 ("Small Highlight (x, y, radius) x iris", Vector) = (-0.62, -0.05, 0.10, 0)
        _EdgeAA ("Edge Softness (x iris)", Range(0.001, 0.1)) = 0.03
        _Tint ("Time Of Day Tint", Color) = (1, 1, 1, 1)
        _HighlightTint ("Highlight Takes Tint", Range(0, 1)) = 0.35
        _EmissionMix ("Flat (Unlit) Mix", Range(0, 1)) = 0.85
        _AmbientShade ("Ambient Shade", Range(0, 1)) = 0.105
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _IrisColor, _PupilColor, _RingColor, _OuterColor, _BounceColor, _HighlightColor, _Tint;
            float _IrisRadius, _PupilSize, _RingWidth, _LidShade, _LidShadeStart, _BounceAmount, _EdgeAA;
            float4 _HL1, _HL2;
            half _HighlightTint, _EmissionMix, _AmbientShade;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionOS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                half fogFactor : TEXCOORD2;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                o.positionCS = pos.positionCS;
                o.positionOS = input.positionOS.xyz;
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                o.fogFactor = ComputeFogFactor(pos.positionCS.z);
                return o;
            }

            // 1 inside a disc of radius r around c (in iris units), anti-aliased over aa
            float Disc(float2 p, float2 c, float r, float aa)
            {
                return 1.0 - smoothstep(r - aa, r + aa, length(p - c));
            }

            half4 frag(Varyings i) : SV_Target
            {
                float2 p = i.positionOS.xy / _IrisRadius;     // eye plane in iris units: x = object X, y = up
                float d = length(p);
                float aa = _EdgeAA;

                // outside -> ring -> iris -> pupil
                float inIris = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, d);
                float ring = smoothstep(1.0 - _RingWidth - aa, 1.0 - _RingWidth + aa, d) * inIris;
                float pupil = Disc(p, float2(0, 0), _PupilSize, aa * 3);   // soft core, like the reference
                half3 iris = lerp(_IrisColor.rgb, _PupilColor.rgb, pupil);
                // lower bounce: violet crescent in the lower half of the iris
                float bounce = saturate(-p.y - 0.15) * smoothstep(0.35, 0.95, d) * _BounceAmount;
                iris = lerp(iris, _BounceColor.rgb, bounce);
                iris = lerp(iris, _RingColor.rgb, ring);
                half3 color = lerp(_OuterColor.rgb, iris, inIris);

                // upper lid shade (the lid's shadow on the top of the eye)
                float lid = smoothstep(_LidShadeStart, _LidShadeStart + 0.45, p.y) * _LidShade;
                color *= 1.0 - lid;

                // lighting: mostly flat; a little N.L keeps the ball round
                Light light = GetMainLight();
                half ndl = saturate(dot(normalize(i.normalWS), light.direction)) * 0.5 + 0.5;
                half lit = lerp(saturate(ndl + _AmbientShade), 1.0, _EmissionMix);
                color *= lit * _Tint.rgb;

                // sticker highlights on top, only partly tinted at night
                float hl = max(Disc(p, _HL1.xy, _HL1.z, aa), Disc(p, _HL2.xy, _HL2.z, aa)) * inIris;
                half3 hlColor = _HighlightColor.rgb * lerp(half3(1, 1, 1), _Tint.rgb, _HighlightTint);
                color = lerp(color, hlColor, hl);

                color = MixFog(color, i.fogFactor);
                return half4(color, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On
            ColorMask R

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            struct Attributes { float4 positionOS : POSITION; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; };
            Varyings vert(Attributes input)
            {
                Varyings o; UNITY_SETUP_INSTANCE_ID(input);
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return o;
            }
            half frag(Varyings i) : SV_Target { return 0; }
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
