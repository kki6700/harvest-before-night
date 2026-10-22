// Toon cloud meshes (clouds modelled in Blender, rendered as solid toon geometry).
// Same colour rules as the painted cards / volumetric clouds: two-tone toon shade, warm towards the sun's azimuth and
// cool on the far side (colours from CloudSunLight's globals, so the day/night slider drives them too), a silver-lining
// band towards the sun, a pale rim and horizon haze.
// Distance: clouds are authored at real scale (km away). The vertex stage shrinks every vertex towards the camera by
// _CameraShrink -> identical on screen (a uniform scale about the eye), but inside the far clip plane and still
// correctly depth sorted against each other. Terrain closer than the shrunk distance would occlude them, so keep
// the shrunk distance (cloud distance x shrink) beyond the ground area that can rise above the horizon.
Shader "DSEWA/ToonCloudMesh"
{
    Properties
    {
        [Header(Shading)]
        _Threshold ("Shade Threshold (half-Lambert)", Range(0, 1)) = 0.5
        _Softness ("Shade Edge Width", Range(0.001, 0.3)) = 0.03
        _Spherize ("Spherize Normals (round shading per object)", Range(0, 1)) = 0.35
        _ShadeNoiseScale ("Shade Lobes Scale (1/m)", Float) = 0.004
        _ShadeNoiseAmount ("Shade Lobes Amount", Range(0, 0.5)) = 0.12
        _BottomShade ("Flat Bottom Shade (underside darker)", Range(0, 1)) = 0.35

        [Header(Colours (used when CloudSunLight does not publish globals))]
        _LitColor ("Lit", Color) = (1, 1, 1, 1)
        _ShadowColor ("Shadow", Color) = (0.62, 0.66, 0.86, 1)

        [Header(Rim and Silver Lining)]
        _RimColor ("Rim Colour", Color) = (1, 1, 1, 1)
        _RimWidth ("Rim Width", Range(0, 1)) = 0.22
        _RimAmount ("Rim Amount (all around)", Range(0, 1)) = 0.35
        _SilverAmount ("Silver Lining (towards the sun)", Range(0, 2)) = 1
        _SilverFocus ("Silver Lining Focus", Range(1, 64)) = 6
        _MinLight ("Min Light (keeps clouds readable under a dim moon)", Range(0, 1)) = 0.6

        [Header(Haze)]
        _HazeAmount ("Horizon Haze Amount", Range(0, 1)) = 0.6
        _HazeHeight ("Haze Height (view elevation sin)", Range(0.01, 0.6)) = 0.18

        [Header(Distance)]
        _CameraShrink ("Camera Shrink (fit inside the far plane)", Range(0.01, 1)) = 0.2
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry+10" }

        Pass
        {
            Name "ForwardUnlit"
            Tags { "LightMode" = "UniversalForward" }
            Cull Back ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half _Threshold, _Softness, _Spherize, _ShadeNoiseAmount, _BottomShade;
                float _ShadeNoiseScale;
                half4 _LitColor, _ShadowColor, _RimColor;
                half _RimWidth, _RimAmount, _SilverAmount, _SilverFocus, _MinLight;
                half _HazeAmount, _HazeHeight;
                float _CameraShrink;
            CBUFFER_END

            // CloudSunLight globals: rgb colour, a = brightness (lit) ; tint rgb + intensity factor ; (side falloff, set, 0, 0)
            float4 _DSEWA_CloudSunLit, _DSEWA_CloudSunShadow, _DSEWA_CloudFarLit, _DSEWA_CloudFarShadow;
            float4 _DSEWA_CloudTint, _DSEWA_CloudParams, _DSEWA_CloudHaze;   // haze rgb = sky horizon colour

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;   // real (unshrunk) world position
                float3 normalWS : TEXCOORD1;
                float3 centreWS : TEXCOORD2;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                float3 ws = TransformObjectToWorld(input.positionOS.xyz);
                float3 centre = TransformObjectToWorld(float3(0, 0, 0));
                float3 eye = _WorldSpaceCameraPos;
                o.positionWS = ws;
                o.centreWS = centre;
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                o.positionCS = TransformWorldToHClip(eye + (ws - eye) * _CameraShrink);
                return o;
            }

            float Hash31(float3 p) { p = frac(p * 0.1031); p += dot(p, p.zyx + 31.32); return frac((p.x + p.y) * p.z); }
            float ValueNoise3(float3 p)
            {
                float3 i = floor(p), f = frac(p);
                f = f * f * (3 - 2 * f);
                float a = lerp(Hash31(i), Hash31(i + float3(1, 0, 0)), f.x);
                float b = lerp(Hash31(i + float3(0, 1, 0)), Hash31(i + float3(1, 1, 0)), f.x);
                float c = lerp(Hash31(i + float3(0, 0, 1)), Hash31(i + float3(1, 0, 1)), f.x);
                float d = lerp(Hash31(i + float3(0, 1, 1)), Hash31(i + float3(1, 1, 1)), f.x);
                return lerp(lerp(a, b, f.y), lerp(c, d, f.y), f.z);
            }

            half4 frag(Varyings i) : SV_Target
            {
                Light sun = GetMainLight();
                float3 L = sun.direction;
                float3 V = normalize(_WorldSpaceCameraPos - i.positionWS);
                float3 viewDir = -V;
                // round, readable shade: blend the mesh normal towards the direction from the object centre
                float3 N = normalize(lerp(normalize(i.normalWS), normalize(i.positionWS - i.centreWS), _Spherize));

                float ndl = dot(N, L) * 0.5 + 0.5;
                ndl += (ValueNoise3(i.positionWS * _ShadeNoiseScale) - 0.5) * 2 * _ShadeNoiseAmount;   // lobed boundary
                ndl -= saturate(-N.y) * _BottomShade * 0.5;                                          // darker belly
                float w = max(fwidth(ndl), _Softness);
                float lit = smoothstep(_Threshold - w, _Threshold + w, ndl);

                // colours by side of the sky (same rule as CloudSunLight / the volumetric layer)
                bool hasGlobals = _DSEWA_CloudParams.y > 0.5;
                float2 sunFlat = normalize(L.xz + 1e-5);
                float side = pow(saturate(dot(normalize(viewDir.xz + 1e-5), sunFlat) * 0.5 + 0.5), hasGlobals ? _DSEWA_CloudParams.x : 2);
                half3 litCol = hasGlobals ? lerp(_DSEWA_CloudFarLit.rgb, _DSEWA_CloudSunLit.rgb, side) : _LitColor.rgb;
                half3 shadowCol = hasGlobals ? lerp(_DSEWA_CloudFarShadow.rgb, _DSEWA_CloudSunShadow.rgb, side) : _ShadowColor.rgb;
                half bright = hasGlobals ? lerp(_DSEWA_CloudFarLit.a, _DSEWA_CloudSunLit.a, side) * max(_DSEWA_CloudTint.a, _MinLight) : 1;
                half3 tint = hasGlobals ? _DSEWA_CloudTint.rgb : half3(1, 1, 1);
                half3 col = lerp(shadowCol, litCol, lit) * tint * bright;

                // rim: pale outline all around, wider and brighter towards the sun / moon (silver lining), cut as a
                // toon band; applied after the light scale so a dim moon still leaves a glowing edge
                float fres = 1 - saturate(dot(N, V));
                float towardSun = pow(saturate(dot(viewDir, L)), _SilverFocus);
                float rimMask = fres - (1 - _RimWidth * (1 + towardSun));
                float rw = max(fwidth(rimMask), 0.01);
                float rim = smoothstep(-rw, rw, rimMask);
                col = lerp(col, _RimColor.rgb * tint, saturate(rim * (_RimAmount + towardSun * _SilverAmount)));

                // horizon haze: low clouds melt into the sky's horizon colour
                float haze = (1 - smoothstep(0, _HazeHeight, viewDir.y)) * _HazeAmount;
                half3 hazeCol = _DSEWA_CloudHaze.a > 0.5 ? _DSEWA_CloudHaze.rgb : col;
                col = lerp(col, hazeCol, haze);
                return half4(col, 1);
            }
            ENDHLSL
        }

        // depth for the depth prepass / SSAO-free URP setups, with the same camera shrink
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            CBUFFER_START(UnityPerMaterial)
                half _Threshold, _Softness, _Spherize, _ShadeNoiseAmount, _BottomShade;
                float _ShadeNoiseScale;
                half4 _LitColor, _ShadowColor, _RimColor;
                half _RimWidth, _RimAmount, _SilverAmount, _SilverFocus, _MinLight;
                half _HazeAmount, _HazeHeight;
                float _CameraShrink;
            CBUFFER_END
            struct Attributes { float4 positionOS : POSITION; UNITY_VERTEX_INPUT_INSTANCE_ID };
            float4 vert(Attributes input) : SV_POSITION
            {
                UNITY_SETUP_INSTANCE_ID(input);
                float3 ws = TransformObjectToWorld(input.positionOS.xyz);
                return TransformWorldToHClip(_WorldSpaceCameraPos + (ws - _WorldSpaceCameraPos) * _CameraShrink);
            }
            half frag() : SV_Target { return 0; }
            ENDHLSL
        }
    }
}
