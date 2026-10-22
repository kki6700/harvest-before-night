// SD cat eye, ported from Art/SDCat/scripts/sd_cat_eye_shader.py (node group 'SD Cat Eye').
// Procedural in eye-local space: uv0 = (x, y) / radius, uv1.x = z / radius (export_sd_cat_fbx.py), +z = gaze, +y = up.
// _Blink / _Happy are keyed per eye renderer in Unity animation clips (Material._Blink).
Shader "DSEWA/SDCatEye"
{
    Properties
    {
        _IrisTop ("Iris Top", Color) = (0.93, 0.81, 0.92, 1)
        _IrisBottom ("Iris Bottom", Color) = (1, 0.86, 0.98, 1)
        _Rim ("Rim", Color) = (0.48, 0.29, 0.19, 1)
        _Pupil ("Pupil", Color) = (0.25, 0.19, 0.29, 1)
        _IrisSize ("Iris Size", Float) = 0.84
        _PupilWidth ("Pupil Width", Float) = 0.46
        _PupilHeight ("Pupil Height", Float) = 0.66
        _HighlightStrength ("Highlight Strength", Float) = 1
        _LidColor ("Lid Color", Color) = (0.97, 0.95, 0.93, 1)
        _LineColor ("Line Color", Color) = (0.58, 0.51, 0.6, 1)
        _LineWidth ("Line Width", Float) = 0.1
        _Blink ("Blink", Range(0, 1)) = 0
        _Happy ("Happy", Range(0, 1)) = 0
        _EmissionMix ("Flat (Emission) Mix", Range(0, 1)) = 0.8
        _AmbientShade ("Ambient Shade", Range(0, 1)) = 0.08
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _IrisTop, _IrisBottom, _Rim, _Pupil, _LidColor, _LineColor;
            float _IrisSize, _PupilWidth, _PupilHeight, _HighlightStrength, _LineWidth, _Blink, _Happy;
            half _EmissionMix, _AmbientShade;
        CBUFFER_END
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

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                float2 uv1 : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 eye : TEXCOORD0;
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
                o.eye = float3(input.uv, input.uv1.x);
                o.fogFactor = ComputeFogFactor(pos.positionCS.z);
                return o;
            }

            // Blender Map Range (Smoothstep): 0 below a, 1 above b
            float SS(float x, float a, float b) { return smoothstep(a, b, x); }

            half4 frag(Varyings i) : SV_Target
            {
                float u = i.eye.x, v = i.eye.y, w = i.eye.z;
                float front = SS(w, 0.0, 0.25);
                float r = length(float2(u, v));
                float size = _IrisSize;

                float iris = (1 - SS(r, size - 0.012, size)) * front;
                float pupil = (1 - SS(length(float2(u / _PupilWidth, v / _PupilHeight)), 0.975, 1.0)) * front;
                float ring = SS(r, size - 0.09, size - 0.08);
                float band = SS(v, 0.26, 0.28);
                float3 irisCol = lerp(_IrisBottom.rgb, _IrisTop.rgb, band);
                irisCol = lerp(irisCol, _Rim.rgb, ring);
                float3 c = lerp(_Rim.rgb, irisCol, iris);
                c = lerp(c, _Pupil.rgb, pupil);

                float h1 = 1 - SS(length(float2(u + 0.22, v - 0.30)), 0.175, 0.185);
                float h2 = 1 - SS(length(float2(u - 0.24, v + 0.28)), 0.075, 0.085);
                float hl = max(h1, h2) * front;
                c = lerp(c, 1.0, hl);

                // painted expressions
                float halfW = _LineWidth * 0.5;
                float u2 = u * u;
                float edge = (1.0 - 1.30 * _Blink) - (_Blink * 0.18) * (1.0 - u2);
                float cover = SS(v, edge - 0.01, edge + 0.01) * front;
                float inEye = 1 - SS(r, size + 0.02, size + 0.04);
                float lash = (1 - SS(abs(v - edge), halfW - 0.008, halfW)) * inEye * front;
                c = lerp(c, _LidColor.rgb, cover);
                c = lerp(c, _LineColor.rgb, lash);
                float arc = (1.0 - u2 / 0.36) * 0.32 - 0.10;
                float arcW = halfW * 1.5;
                float arcLine = (1 - SS(abs(v - arc), arcW - 0.008, arcW)) * (1 - SS(abs(u), 0.58, 0.62)) * front;
                c = lerp(c, _LidColor.rgb, _Happy * front);
                c = lerp(c, _LineColor.rgb, arcLine * _Happy);
                hl *= (1 - cover) * (1 - _Happy);

                // 20 % diffuse form shading + 80 % flat emission (strength 1 + highlight)
                Light light = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                float diffuse = 0.764 * saturate(dot(normalize(i.normalWS), light.direction)) * light.shadowAttenuation + _AmbientShade;
                float3 color = c * lerp(diffuse, 1.0 + hl * _HighlightStrength, _EmissionMix);
                return half4(MixFog(color, i.fogFactor), 1);
            }
            ENDHLSL
        }

        UsePass "DSEWA/SDCatToon/SHADOWCASTER"
        UsePass "DSEWA/SDCatToon/DEPTHONLY"
        UsePass "DSEWA/SDCatToon/DEPTHNORMALS"
    }
}
