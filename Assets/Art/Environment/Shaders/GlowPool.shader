// DSEWA/GlowPool: soft pool of light on the ground under a glowing crystal cluster (no real light: the scene keeps to
// 4-6 point lights). A flat quad lying on the ground adds a round, soft-edged glow (additive, depth-tested, so grass
// and the crystals in front still cover it), breathing gently like the crystals and fading with the scene's ground fog.
// UV (0..1) of the quad: centre = brightest. Night-only strength comes from DayNightBlend driving _Intensity.
// All defaults are my own starting values.
Shader "DSEWA/GlowPool"
{
    Properties
    {
        [HDR] _Color ("Glow Color", Color) = (0.4, 0.5, 1.2, 1)
        _Intensity ("Intensity", Range(0, 2)) = 0.35
        _Falloff ("Edge Softness (higher = tighter core)", Range(0.5, 6)) = 2.2
        _Wobble ("Edge Wobble", Range(0, 0.5)) = 0.12
        _PulsePeriod ("Pulse Period (s)", Range(0.2, 10)) = 4.5
        _PulseRange ("Pulse Min / Max", Vector) = (0.75, 1.1, 0, 0)
        _PulseCell ("Beat Shared Within (m, same as the crystals)", Float) = 5
        _RingStrength ("Ring Wave Per Beat", Range(0, 2)) = 0.6
        _RingWidth ("Ring Width (0-1 of radius)", Range(0.02, 0.5)) = 0.12
        _RingSpan ("Ring Travel Time (0-1 of the beat)", Range(0.1, 1)) = 0.7
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent-10" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True" }

        Pass
        {
            Name "GlowPool"
            Tags { "LightMode" = "UniversalForward" }
            Blend One One
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets/Art/Environment/Shaders/GroundFog.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _Color;
                half _Intensity, _Falloff, _Wobble;
                float _PulsePeriod;
                float4 _PulseRange;
                float _PulseCell;
                half _RingStrength, _RingWidth, _RingSpan;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; float3 positionWS : TEXCOORD1; UNITY_VERTEX_OUTPUT_STEREO };

            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.uv = input.uv;
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float2 p = i.uv * 2.0 - 1.0;
                float ang = atan2(p.y, p.x);
                float3 objPos = GetObjectToWorldMatrix()._m03_m13_m23;
                float seed = frac(sin(dot(objPos, float3(12.9898, 78.233, 37.719))) * 43758.5453);
                // slightly uneven edge so the pool does not read as a perfect disc
                float wobble = 1.0 + _Wobble * (sin(ang * 3.0 + seed * 6.28) * 0.6 + sin(ang * 5.0 - seed * 11.0) * 0.4);
                float r = length(p) / wobble;
                float glow = pow(saturate(1.0 - r), _Falloff);
                // same beat as the crystals above (DSEWA/ToonCrystal CrystalPulseCycle)
                float3 key = _PulseCell > 0.01 ? float3(floor(objPos.xz / _PulseCell), 0).xzy : objPos;
                float cycle = frac(_Time.y / max(_PulsePeriod, 0.01) + frac(sin(dot(key, float3(12.9898, 78.233, 37.719))) * 43758.5453));
                float pulse = lerp(_PulseRange.x, _PulseRange.y, 0.5 + 0.5 * sin(cycle * TWO_PI));
                // a ring of light spreads out from the middle each beat, fading as it widens
                float front = cycle / max(_RingSpan, 0.05);
                float ring = front < 1.0 ? exp(-pow((r - front) / max(_RingWidth, 0.01), 2.0)) * (1.0 - front) * saturate(1.0 - r) : 0.0;
                half3 c = _Color.rgb * (glow * pulse + ring * _RingStrength) * _Intensity;
                // additive: the ground fog fades the glow out (same amount as ApplyGroundFog uses) instead of tinting it
                half fogAmount = 0;
                if (_DSEWA_GroundFogColor.a > 0.5)
                {
                    float d = distance(i.positionWS, _WorldSpaceCameraPos);
                    float f = saturate((d - _DSEWA_GroundFog.x) / max(_DSEWA_GroundFog.y - _DSEWA_GroundFog.x, 1e-3));
                    fogAmount = f * f * (3 - 2 * f) * _DSEWA_GroundFog.z;
                }
                return half4(c * (1.0 - fogAmount), 0);
            }
            ENDHLSL
        }
    }
}
