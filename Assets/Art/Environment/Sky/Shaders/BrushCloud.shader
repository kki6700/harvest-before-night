// Brush-stamp cloud (BrushCloud component builds the stamps). Every stamp is a camera-facing quad cut out by a brush
// alpha; it is lit with the cloud's rounded normal (vertex normal), so all dabs together read as one toon volume and
// the dabs only show along the outline and the light/shadow boundary (each dab nudges the boundary a little).
// Colours: CloudSunLight globals like DSEWA/ToonCloudMesh (warm towards the sun's azimuth, cool on the far side,
// so the day/night slider drives them), silver lining towards the sun, horizon haze.
// Transparent per cloud (depth pass + one blended colour pass), so the sky shows through evenly like on the cards.
Shader "DSEWA/BrushCloud"
{
    Properties
    {
        _BrushMap ("Brush Alpha", 2D) = "white" {}
        _Cutoff ("Brush Cutoff", Range(0.01, 0.99)) = 0.45
        _Round ("Round Dabs (0 brush texture, 1 clean circles)", Range(0, 1)) = 0

        [Header(Shading)]
        _Threshold ("Shade Threshold (half-Lambert)", Range(0, 1)) = 0.5
        _Softness ("Shade Edge Width", Range(0.001, 0.3)) = 0.02
        _StrokeJitter ("Per-Dab Light Jitter (brushy shadow edge)", Range(0, 0.4)) = 0.12
        _StrokeShade ("Dab Edge Darken (brush texture inside)", Range(0, 0.5)) = 0.12
        _BottomShade ("Flat Bottom Shade", Range(0, 1)) = 0.35

        _MidThreshold ("Mid Step (third tone, lit above this)", Range(0, 1)) = 0.62
        _MidMix ("Mid Tone (shadow .. lit)", Range(0, 1)) = 0.5

        [Header(Colours (used when CloudSunLight does not publish globals, or Use Material Colours))]
        [Toggle] _UseMatColors ("Use Material Colours (ignore CloudSunLight)", Float) = 0
        _LitColor ("Lit", Color) = (1, 1, 1, 1)
        _MidColor ("Mid", Color) = (0.8, 0.8, 0.92, 1)
        _ShadowColor ("Shadow", Color) = (0.62, 0.66, 0.86, 1)

        [Header(Painted Texture (same painting as the cloud cards))]
        _PaintMap ("Painting (cards' colour map)", 2D) = "gray" {}
        _PaintAmount ("Painted Mottling (moves the tone like the cards' gradient map)", Range(0, 1)) = 0
        _PaintScale ("Painting Patch Size per Dab", Range(0.05, 1)) = 0.3
        _PaintMin ("Paint Luminance Min (cards' Shade Min)", Range(0, 1)) = 0.66
        _PaintMax ("Paint Luminance Max (cards' Shade Max)", Range(0, 1)) = 0.96

        [Header(Silver Lining)]
        _RimColor ("Rim Colour", Color) = (1, 1, 1, 1)
        _RimWidth ("Rim Width", Range(0, 1)) = 0.3
        _SilverAmount ("Silver Lining (towards the sun)", Range(0, 2)) = 1
        _SilverFocus ("Silver Lining Focus", Range(1, 64)) = 6
        _MinLight ("Min Light (keeps clouds readable under a dim moon)", Range(0, 1)) = 0.6
        _MaxBright ("Max Brightness (caps the sun intensity factor)", Range(0.5, 2)) = 1.05

        [Header(Haze)]
        _HazeAmount ("Horizon Haze Amount", Range(0, 1)) = 0.15
        _Opacity ("Opacity (cards use 0.7: the sky colour shows through)", Range(0, 1)) = 1
        _Saturation ("Saturation (the mid tone mixes warm lit and cool shadow and greys out)", Range(0, 2)) = 1
        _HazeHeight ("Haze Height (view elevation sin)", Range(0.01, 0.6)) = 0.15
    }

    SubShader
    {
        // Transparent like the cloud cards (their Opacity 0.7 lets the sky colour show through): a depth pass keeps
        // only the front-most dab, then the colour pass blends that dab once, so overlapping dabs never stack darker.
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True" }

            HLSLINCLUDE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BrushMap); SAMPLER(sampler_BrushMap);
            TEXTURE2D(_PaintMap); SAMPLER(sampler_PaintMap);
            CBUFFER_START(UnityPerMaterial)
                float4 _BrushMap_ST;
                half _Cutoff, _Round, _Threshold, _Softness, _StrokeJitter, _StrokeShade, _BottomShade;
                half _MidThreshold, _MidMix, _UseMatColors;
                half _PaintAmount, _PaintScale, _PaintMin, _PaintMax;
                half4 _LitColor, _MidColor, _ShadowColor, _RimColor;
                half _RimWidth, _SilverAmount, _SilverFocus, _MinLight, _MaxBright, _HazeAmount, _HazeHeight;
                half _Opacity, _Saturation;
            CBUFFER_END

            // CloudSunLight globals: rgb colour, a = brightness (lit) ; tint rgb + intensity factor ; (side falloff, set, 0, 0)
            float4 _DSEWA_CloudSunLit, _DSEWA_CloudSunShadow, _DSEWA_CloudFarLit, _DSEWA_CloudFarShadow;
            float4 _DSEWA_CloudTint, _DSEWA_CloudParams, _DSEWA_CloudHaze;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 uv0 : TEXCOORD0;   // corner xy (-1..1), size (object units), rotation (radians)
                float4 uv1 : TEXCOORD1;   // random, random, stretch (width / height, streaks)
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float2 uv : TEXCOORD2;
                float rand : TEXCOORD3;
                float rand2 : TEXCOORD4;
            };

            Varyings vert(Attributes input)
            {
                Varyings o;
                float3 centre = TransformObjectToWorld(input.positionOS.xyz);
                float scale = length(float3(UNITY_MATRIX_M._m00, UNITY_MATRIX_M._m10, UNITY_MATRIX_M._m20));
                float s, c;
                sincos(input.uv0.w, s, c);
                float2 q = float2(input.uv0.x * max(input.uv1.z, 1), input.uv0.y);   // streaks are stretched sideways
                float2 k = float2(c * q.x - s * q.y, s * q.x + c * q.y);
                float3 right = UNITY_MATRIX_V[0].xyz, up = UNITY_MATRIX_V[1].xyz;
                float3 ws = centre + (k.x * right + k.y * up) * input.uv0.z * scale;
                o.positionWS = ws;
                o.positionCS = TransformWorldToHClip(ws);
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                o.uv = input.uv0.xy * 0.5 + 0.5;
                o.rand = input.uv1.x;
                o.rand2 = input.uv1.y;
                return o;
            }

            half BrushShape(float2 uv)
            {
                half brush = SAMPLE_TEXTURE2D(_BrushMap, sampler_BrushMap, uv).r;
                half circle = saturate(1 - length(uv * 2 - 1));                  // clean round dab: 1 centre, 0 rim
                return lerp(brush, circle, _Round);
            }

            half fragDepth(Varyings i) : SV_Target
            {
                clip(BrushShape(i.uv) - _Cutoff);
                return 0;
            }

            half4 frag(Varyings i) : SV_Target
            {
                half brush = BrushShape(i.uv);
                clip(brush - _Cutoff);

                Light sun = GetMainLight();
                float3 L = sun.direction;
                float3 V = normalize(_WorldSpaceCameraPos - i.positionWS);
                float3 viewDir = -V;
                float3 N = normalize(i.normalWS);

                float ndl = dot(N, L) * 0.5 + 0.5;
                ndl += (i.rand - 0.5) * 2 * _StrokeJitter;                 // each dab moves the boundary a little
                ndl -= saturate(-N.y) * _BottomShade * 0.5;                // darker belly
                float w = max(fwidth(ndl), _Softness);
                float lit = smoothstep(_Threshold - w, _Threshold + w, ndl);
                float lit2 = smoothstep(_MidThreshold - w, _MidThreshold + w, ndl);   // third tone
                // painted mottling: each dab shows its own patch of the cards' painting, read through the cards' own
                // luminance range, and nudges the tone up / down - the same brush texture as the cards inside the toon steps
                float2 puv = float2(i.rand, 0.24 + 0.45 * i.rand2) + (i.uv - 0.5) * _PaintScale;
                half3 paint = SAMPLE_TEXTURE2D(_PaintMap, sampler_PaintMap, puv).rgb;
                half paintTone = smoothstep(_PaintMin, _PaintMax, dot(paint, half3(0.3, 0.59, 0.11)));
                float tone = (lit + lit2) * 0.5;                                     // 0 shadow, 0.5 mid, 1 lit
                tone = saturate(tone + (paintTone - 0.5) * _PaintAmount);

                bool hasGlobals = _DSEWA_CloudParams.y > 0.5 && _UseMatColors < 0.5;
                float2 sunFlat = normalize(L.xz + 1e-5);
                float side = pow(saturate(dot(normalize(viewDir.xz + 1e-5), sunFlat) * 0.5 + 0.5), hasGlobals ? _DSEWA_CloudParams.x : 2);
                half3 litCol = hasGlobals ? lerp(_DSEWA_CloudFarLit.rgb, _DSEWA_CloudSunLit.rgb, side) : _LitColor.rgb;
                half3 shadowCol = hasGlobals ? lerp(_DSEWA_CloudFarShadow.rgb, _DSEWA_CloudSunShadow.rgb, side) : _ShadowColor.rgb;
                half bright = hasGlobals ? lerp(_DSEWA_CloudFarLit.a, _DSEWA_CloudSunLit.a, side) * max(_DSEWA_CloudTint.a, _MinLight) : 1;
                bright = min(bright, _MaxBright);                          // a strong noon sun must not wash the cloud out
                half3 tint = hasGlobals ? _DSEWA_CloudTint.rgb : half3(1, 1, 1);
                half3 midCol = hasGlobals ? lerp(shadowCol, litCol, _MidMix) : _MidColor.rgb;
                half3 col = (tone < 0.5 ? lerp(shadowCol, midCol, tone * 2) : lerp(midCol, litCol, tone * 2 - 1)) * tint * bright;
                // brush texture inside the dab: its thin outer part a touch darker, like paint thinning out
                col *= 1 - _StrokeShade * (1 - smoothstep(_Cutoff, 1, brush));

                // silver lining: dabs on the cloud's edge (normal turned away from the camera), towards the sun
                float fres = 1 - saturate(dot(N, V));
                float towardSun = pow(saturate(dot(viewDir, L)), _SilverFocus);
                float rimMask = fres - (1 - _RimWidth * (1 + towardSun));
                float rw = max(fwidth(rimMask), 0.01);
                float rim = smoothstep(-rw, rw, rimMask);
                // rim colour starts from the time of day's lit colour (a white rim turned whole clouds grey at dawn / night)
                half3 rimCol = lerp(litCol, _RimColor.rgb, 0.35) * 1.15 * tint * bright;
                col = lerp(col, rimCol, saturate(rim * towardSun * _SilverAmount));

                float haze = (1 - smoothstep(0, _HazeHeight, viewDir.y)) * _HazeAmount;
                half3 hazeCol = _DSEWA_CloudHaze.a > 0.5 ? _DSEWA_CloudHaze.rgb : col;
                col = lerp(col, hazeCol, haze);
                half lum = dot(col, half3(0.3, 0.59, 0.11));
                col = max(lerp(lum.xxx, col, _Saturation), 0);
                return half4(col, _Opacity);
            }
            ENDHLSL

        Pass
        {
            Name "BrushDepth"
            Tags { "LightMode" = "SRPDefaultUnlit" }
            Cull Off ZWrite On ColorMask 0
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment fragDepth
            ENDHLSL
        }

        Pass
        {
            Name "ForwardUnlit"
            Tags { "LightMode" = "UniversalForward" }
            Cull Off ZWrite Off ZTest LEqual
            Blend SrcAlpha OneMinusSrcAlpha
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            ENDHLSL
        }
    }
}
