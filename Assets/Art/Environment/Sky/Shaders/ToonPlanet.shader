// 3D toon planet body (and its moons) drawn in the sky by SkyRingedPlanet.
// Three toon steps against the main light, latitude bands in object space (the object spins about its local Y),
// limb darkening, a thin lit-side rim and the ring's shadow (ray from the surface to the light through the ring plane).
// Drawn in the transparent queue (after the skybox, before the clouds) with ZWrite, so the ring and moons sort by
// depth against it and the night fade can blend it into the sky. Like ToonMoon it is shrunk towards the camera
// (_CameraShrink) to stay inside the far plane.
Shader "DSEWA/ToonPlanet"
{
    Properties
    {
        _LitColor ("Lit", Color) = (0.82, 0.77, 0.99, 1)
        _ShadowColor ("Shadow", Color) = (0.2, 0.15, 0.41, 1)
        _BandColor ("Band Tint (multiply)", Color) = (0.52, 0.43, 0.83, 1)
        _RimColor ("Lit-side Rim", Color) = (0.8, 0.75, 1, 1)
        _MidStep ("Mid Step Amount (3rd toon step)", Range(0, 1)) = 1
        _Bands ("Band Count (procedural)", Float) = 7
        _BandAmount ("Band Amount", Range(0, 1)) = 0.2
        [NoScaleOffset] _BandMap ("Band Map (T_Planet_Maps: B latitude bands, A turbulence; optional)", 2D) = "black" {}
        _UseBandMap ("Use Band Map", Range(0, 1)) = 0
        _BandSteps ("Band Toon Steps (0 smooth)", Range(0, 6)) = 3
        _BandMapBoost ("Band Map Strength (x Band Amount)", Range(0, 5)) = 1
        _Limb ("Limb Darkening", Range(0, 1)) = 0.6
        _RimWidth ("Rim Width", Range(0, 0.5)) = 0.12
        _HazeColor ("Haze Colour (sky behind)", Color) = (0.2, 0.2, 0.45, 1)
        _Haze ("Haze Amount", Range(0, 1)) = 0.1
        [Header(Ring shadow)]
        _RingShadow ("Ring Shadow Strength", Range(0, 1)) = 0.7
        _RingInnerOuter ("Ring Inner, Outer (planet radii)", Vector) = (1.35, 2.1, 0, 0)
        [NoScaleOffset] _RingMap ("Ring Map (R density across the ring; optional)", 2D) = "white" {}
        _UseRingMap ("Use Ring Map", Range(0, 1)) = 0
        _RingLevels ("Ring Map Levels (in black, in white; match the ring material)", Vector) = (0, 1, 0, 0)
        [HideInInspector] _CameraShrink ("Camera Shrink (set by SkyRingedPlanet)", Float) = 1
        [HideInInspector] _Fade ("Fade (set by SkyRingedPlanet)", Float) = 1
        [HideInInspector] _Spin ("Band Spin (rad, set by SkyRingedPlanet)", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline" "Queue" = "Transparent-100" }

        Pass
        {
            Name "Planet"
            Tags { "LightMode" = "UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            Cull Back ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BandMap); SAMPLER(sampler_BandMap);
            TEXTURE2D(_RingMap); SAMPLER(sampler_RingMap);
            CBUFFER_START(UnityPerMaterial)
                half4 _LitColor, _ShadowColor, _BandColor, _RimColor, _HazeColor;
                half _MidStep, _Bands, _BandAmount, _UseBandMap, _BandSteps, _BandMapBoost, _Limb, _RimWidth, _Haze;
                half _RingShadow, _UseRingMap;
                float4 _RingInnerOuter, _RingLevels;
                float _CameraShrink, _Fade, _Spin;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS : TEXCOORD0;
                float3 positionOS : TEXCOORD1;
                float3 viewWS : TEXCOORD2;
            };

            Varyings vert(Attributes input)
            {
                Varyings o;
                float3 ws = TransformObjectToWorld(input.positionOS.xyz);
                float3 eye = _WorldSpaceCameraPos;
                o.positionCS = TransformWorldToHClip(eye + (ws - eye) * _CameraShrink);
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                o.positionOS = input.positionOS.xyz;
                o.viewWS = normalize(eye - ws);
                return o;
            }

            // ring density at a radius (planet radii): optional authored map, else two flat toon gaps
            float RingDensity(float r)
            {
                float u = (r - _RingInnerOuter.x) / max(_RingInnerOuter.y - _RingInnerOuter.x, 1e-3);
                if (u <= 0 || u >= 1) return 0;
                float proc = 0.75 + 0.25 * step(0.5, frac(r * 6));
                float map = saturate((SAMPLE_TEXTURE2D_LOD(_RingMap, sampler_RingMap, float2(u, 0.5), 0).r - _RingLevels.x) / max(_RingLevels.y - _RingLevels.x, 1e-3));
                return lerp(proc, map, _UseRingMap);
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                float3 V = normalize(i.viewWS);
                float3 L = normalize(_MainLightPosition.xyz);
                float ndl = dot(N, L);
                float w = fwidth(ndl) + 0.02;
                float3 p = normalize(i.positionOS);                                  // unit sphere, object space

                // ring shadow: from the surface towards the light, where does the ray cross the ring plane (y = 0)?
                float3 Lo = normalize(mul((float3x3)unity_WorldToObject, L));
                float shade = 1;
                if (abs(Lo.y) > 1e-3)
                {
                    float t = -p.y / Lo.y;
                    float3 hit = p + Lo * t;
                    float dens = RingDensity(length(hit.xz));
                    shade = 1 - step(0, t) * dens * _RingShadow;
                }

                float lit = smoothstep(-0.05 - w, -0.05 + w, ndl) * shade;
                half3 col = lerp(_ShadowColor.rgb, _LitColor.rgb, lit);
                float lit2 = smoothstep(0.35 - w, 0.35 + w, ndl) * shade;
                col = lerp(col, lerp(lerp(_ShadowColor.rgb, _LitColor.rgb, 0.55), _LitColor.rgb, lit2), lit * _MidStep);

                // latitude bands (object Y is the spin axis; the object itself turns, _Spin drifts the band waves)
                float lat = p.y;
                float lon = atan2(p.z, p.x) + _Spin;
                float bProc = step(0.35, sin((lat + 0.05 * sin(lon * 3 + lat * 5) + 0.025 * sin(lon * 7 - lat * 11)) * _Bands * 3.14159));
                // T_Planet_Maps: B = latitude bands (wavy), A = turbulence; R / G belong to the ring
                half2 bm = SAMPLE_TEXTURE2D_LOD(_BandMap, sampler_BandMap, float2(lon * 0.15915494, lat * 0.5 + 0.5), 0).ba;
                float bMap = saturate(bm.x + (bm.y - 0.5) * 0.15);
                if (_BandSteps > 0) bMap = floor(bMap * _BandSteps + 0.5) / _BandSteps;
                float band = lerp(bProc, bMap, _UseBandMap);
                col = lerp(col, col * _BandColor.rgb * 1.3, saturate(band * _BandAmount * lerp(1, _BandMapBoost, _UseBandMap)));

                // limb darkening + thin lit-side rim (reads as a ball)
                float fres = 1 - saturate(dot(N, V));
                col *= 1 - _Limb * pow(fres, 3) * 0.5;
                float rw = fwidth(fres) + 0.01;
                col = lerp(col, _RimColor.rgb, smoothstep(1 - _RimWidth - rw, 1 - _RimWidth + rw, fres) * lit * 0.6);
                col = lerp(col, _HazeColor.rgb, _Haze);
                return half4(col, _Fade);
            }
            ENDHLSL
        }
    }
}
