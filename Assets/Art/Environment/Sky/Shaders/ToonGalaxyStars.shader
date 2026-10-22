// Star knots over the big galaxy (SkyGalaxyStars): a baked mesh of camera-facing quads, one per star, laid out in
// the galaxy map's own coordinates (POSITION.xy in -1..1, placed on the spiral arms). The vertex shader maps them
// onto the sky exactly like ToonSky's GalaxySprite (roll, tilt, slow spin), so they ride on the painted spiral.
// Crisp toon dots, a 4-point glint on the brightest, each twinkling on its own. Additive, behind the clouds.
Shader "DSEWA/ToonGalaxyStars"
{
    Properties
    {
        _CoreColor ("Core Colour", Color) = (0.85, 0.72, 0.95, 1)
        _EdgeColor ("Edge Colour", Color) = (0.4, 0.45, 0.9, 1)
        _Brightness ("Brightness", Range(0, 4)) = 1.2
        _Twinkle ("Twinkle", Range(0, 1)) = 0.6
        _TwinkleSpeed ("Twinkle Speed (rad/s)", Vector) = (1, 4, 0, 0)
        _Glint ("Glint Arms (brightest stars)", Range(0, 1)) = 0.6
        [HideInInspector] _GalDir ("Galaxy Direction", Vector) = (0, 0, 1, 0)
        [HideInInspector] _GalRight ("Galaxy Right", Vector) = (1, 0, 0, 0)
        [HideInInspector] _GalUp ("Galaxy Up", Vector) = (0, 1, 0, 0)
        [HideInInspector] _GalShape ("Size (rad), Roll, Tilt, Spin (rad)", Vector) = (0.2, 0, 0.5, 0)
        [HideInInspector] _GalDist ("Distance, Shrink, Fade, -", Vector) = (6000, 1, 1, 0)
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline" "Queue" = "Transparent-100" }

        Pass
        {
            Name "GalaxyStars"
            Tags { "LightMode" = "UniversalForward" }
            Blend One One
            ZWrite Off Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _CoreColor, _EdgeColor;
                half _Brightness, _Twinkle, _Glint;
                float4 _TwinkleSpeed;
                float4 _GalDir, _GalRight, _GalUp, _GalShape, _GalDist;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;     // xy = galaxy map coords (-1..1)
                float2 corner : TEXCOORD0;        // quad corner (-1..1)
                float4 data : TEXCOORD1;          // size (rad), hash, brightness, core closeness (1 centre .. 0 edge)
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 corner : TEXCOORD0;
                float4 data : TEXCOORD1;
            };

            Varyings vert(Attributes i)
            {
                Varyings o;
                float2 t = i.positionOS.xy;
                // inverse of ToonSky's GalaxySprite mapping: undo the spin, re-apply the tilt squash, undo the roll
                float sa = _GalShape.w, cs = cos(sa), ss = sin(sa);
                float2 qt = float2(cs * t.x + ss * t.y, -ss * t.x + cs * t.y);
                float2 qr = float2(qt.x, qt.y * max(_GalShape.z, 0.05));
                float c = cos(_GalShape.y), s = sin(_GalShape.y);
                float2 q = float2(c * qr.x - s * qr.y, s * qr.x + c * qr.y);
                float3 dir = normalize(_GalDir.xyz + (_GalRight.xyz * q.x + _GalUp.xyz * q.y) * _GalShape.x);
                // camera-facing quad, size as an angle
                float3 camR = UNITY_MATRIX_V[0].xyz, camU = UNITY_MATRIX_V[1].xyz;
                float3 eye = _WorldSpaceCameraPos;
                float d = _GalDist.x;
                float3 ws = eye + dir * d + (camR * i.corner.x + camU * i.corner.y) * (d * i.data.x);
                o.positionCS = TransformWorldToHClip(eye + (ws - eye) * _GalDist.y);
                o.corner = i.corner;
                o.data = i.data;
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float r = length(i.corner);
                float fw = fwidth(r) + 1e-3;
                float dotA = 1 - smoothstep(0.32 - fw, 0.32 + fw, r);              // crisp toon dot
                float halo = exp(-r * r * 6) * 0.25;
                // glint: thin cross on the brightest knots
                float th = 0.06 + fw;
                float2 a = abs(i.corner);
                float cross = max((1 - smoothstep(0, 1, a.x)) * (1 - smoothstep(th * 0.5, th, a.y)),
                                  (1 - smoothstep(0, 1, a.y)) * (1 - smoothstep(th * 0.5, th, a.x)));
                float glint = cross * _Glint * smoothstep(0.75, 1, i.data.z);
                // each knot twinkles on its own speed / phase
                float h = i.data.y;
                float sp = lerp(_TwinkleSpeed.x, _TwinkleSpeed.y, frac(h * 7.31));
                float tw = 1 - _Twinkle * (0.5 + 0.5 * sin(_Time.y * sp + h * 43.7));
                half3 col = lerp(_EdgeColor.rgb, _CoreColor.rgb, i.data.w);
                float v = (dotA + halo + glint) * i.data.z * tw * _Brightness * _GalDist.z;
                return half4(col * v, 0);
            }
            ENDHLSL
        }
    }
}
