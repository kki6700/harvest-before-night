// Ring of the 3D toon planet (SkyRingedPlanet builds a flat annulus mesh in the planet's object space, y = 0,
// radii in planet radii, drawn with scale = planet radius). Density across the ring from an optional authored map
// (else flat toon gaps), turning clumps along it, darker when we see its unlit face, and the planet's shadow
// (ray from the ring towards the light hits the unit sphere). Transparent, depth-tested against the planet body.
Shader "DSEWA/ToonPlanetRing"
{
    Properties
    {
        _RingColor ("Ring Colour", Color) = (0.92, 0.86, 1, 1)
        _ShadowColor ("Ring in Shadow", Color) = (0.25, 0.2, 0.45, 1)
        _Opacity ("Opacity", Range(0, 1)) = 0.75
        _RingInnerOuter ("Inner, Outer (planet radii)", Vector) = (1.35, 2.1, 0, 0)
        [NoScaleOffset] _RingMap ("Ring Map (R density, G brightness across the ring; optional)", 2D) = "white" {}
        _UseRingMap ("Use Ring Map", Range(0, 1)) = 0
        _Steps ("Density Toon Steps (0 smooth)", Range(0, 6)) = 3
        _RingLevels ("Map Levels (in black, in white)", Vector) = (0, 1, 0, 0)
        _BackFace ("Unlit Face Brightness", Range(0, 1)) = 0.45
        _Clumps ("Turning Clumps", Range(0, 1)) = 0.55
        _HazeColor ("Haze Colour (sky behind)", Color) = (0.2, 0.2, 0.45, 1)
        _Haze ("Haze Amount", Range(0, 1)) = 0.1
        [HideInInspector] _CameraShrink ("Camera Shrink", Float) = 1
        [HideInInspector] _Fade ("Fade", Float) = 1
        [HideInInspector] _RingTurn ("Ring Turn (rad)", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline" "Queue" = "Transparent-99" }

        Pass
        {
            Name "Ring"
            Tags { "LightMode" = "UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            Cull Off ZWrite Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_RingMap); SAMPLER(sampler_RingMap);
            CBUFFER_START(UnityPerMaterial)
                half4 _RingColor, _ShadowColor, _HazeColor;
                half _Opacity, _UseRingMap, _Steps, _BackFace, _Clumps, _Haze;
                float4 _RingInnerOuter, _RingLevels;
                float _CameraShrink, _Fade, _RingTurn;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionOS : TEXCOORD0;
                float3 viewWS : TEXCOORD1;
            };

            Varyings vert(Attributes input)
            {
                Varyings o;
                float3 ws = TransformObjectToWorld(input.positionOS.xyz);
                float3 eye = _WorldSpaceCameraPos;
                o.positionCS = TransformWorldToHClip(eye + (ws - eye) * _CameraShrink);
                o.positionOS = input.positionOS.xyz;
                o.viewWS = normalize(eye - ws);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 p = i.positionOS;                                             // planet radii
                float r = length(p.xz);
                float u = (r - _RingInnerOuter.x) / max(_RingInnerOuter.y - _RingInnerOuter.x, 1e-3);
                float uw = fwidth(u) * 1.5;
                float edge = smoothstep(-uw, uw, u) * (1 - smoothstep(1 - uw, 1 + uw, u));
                half2 m = SAMPLE_TEXTURE2D(_RingMap, sampler_RingMap, float2(saturate(u), 0.5)).rg;
                // authored density, re-levelled (the map is dark overall: lift it so the ring reads as a solid band)
                float mapD = saturate((m.r - _RingLevels.x) / max(_RingLevels.y - _RingLevels.x, 1e-3));
                float dens = lerp(0.75 + 0.25 * step(0.5, frac(r * 6)), mapD, _UseRingMap);
                if (_Steps > 0) dens = floor(dens * _Steps + 0.5) / _Steps;
                // clumps travel round the ring (the mesh is symmetric, so the turn is an angle offset)
                float th = atan2(p.z, p.x);
                float clump = sin(th * 4 - _RingTurn + r * 5) + 0.5 * sin(th * 9 - _RingTurn * 1.3 - r * 3);
                float cw = fwidth(clump) + 0.05;
                dens *= lerp(1, lerp(1, 0.45, smoothstep(0.35 - cw, 0.35 + cw, clump)), _Clumps);

                // lighting: which face is lit, which face do we see; the planet's shadow across the ring
                float3 Nw = normalize(mul((float3x3)unity_ObjectToWorld, float3(0, 1, 0)));
                float3 L = normalize(_MainLightPosition.xyz);
                float sameSide = step(0, dot(Nw, L) * dot(Nw, normalize(i.viewWS)));
                float3 Lo = normalize(mul((float3x3)unity_WorldToObject, L));
                float b = dot(p, Lo), c = dot(p, p) - 1;
                float disc = b * b - c;
                float inShadow = step(0, disc) * step(b, 0);                         // the sphere lies towards the light
                half3 col = _RingColor.rgb * lerp(_BackFace, 1, sameSide) * lerp(half3(1, 1, 1), m.g * 0.4 + 0.8, _UseRingMap);
                col = lerp(col, _ShadowColor.rgb, inShadow);
                col = lerp(col, _HazeColor.rgb, _Haze);
                return half4(col, dens * edge * _Opacity * _Fade);
            }
            ENDHLSL
        }
    }
}
