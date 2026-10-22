// DSEWA/ToonPoolWater: flat toon water surface for the pool. Transparent; colour and opacity go from shallow to deep
// with the water thickness behind the pixel (scene depth minus surface depth), so the tiled floor and its caustics
// show through. A toon foam line where the water meets the walls, faint moving highlight lines from the same caustic
// mask (ToonCaustic.hlsl), lit by the main light + sky ambient like the puddles. No reflection / refraction / PBR.
// All values are my own starting values.
Shader "DSEWA/ToonPoolWater"
{
    Properties
    {
        [Header(Water body)]
        _ShallowColor ("Shallow Color", Color) = (0.36, 0.86, 0.9, 1)
        _DeepColor ("Deep Color", Color) = (0.07, 0.45, 0.62, 1)
        _DepthMax ("Depth For Full Deep Color (m)", Range(0.05, 5)) = 0.8
        _AlphaShallow ("Opacity Shallow", Range(0, 1)) = 0.25
        _AlphaDeep ("Opacity Deep", Range(0, 1)) = 0.7
        _ReceiveLight ("Receive Scene Light", Range(0, 1)) = 1
        [Header(Foam line at the walls)]
        _FoamColor ("Foam Color", Color) = (0.9, 1, 1, 1)
        _FoamWidth ("Foam Width (m of water thickness)", Range(0.001, 0.3)) = 0.06
        _FoamEmission ("Foam Self Glow", Range(0, 1)) = 0.3
        [Header(Surface highlight lines)]
        [NoScaleOffset] _CausticMap ("Caustic Mask (R)", 2D) = "black" {}
        _LineTiling ("Line Tiles Per Metre", Range(0.05, 3)) = 0.8
        _LineSpeed1 ("Set 1 Speed", Vector) = (0.04, 0.03, 0, 0)
        _LineSpeed2 ("Set 2 Speed", Vector) = (-0.035, 0.02, 0, 0)
        _LineGain ("Line Gain", Range(0.5, 5)) = 2.5
        _LineColor ("Line Color", Color) = (0.85, 1, 1, 1)
        _LineStrength ("Line Strength", Range(0, 1)) = 0.35
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent-40" "RenderPipeline" = "UniversalPipeline" }

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
            #pragma multi_compile_fog
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _ShallowColor, _DeepColor, _FoamColor, _LineColor;
                float _DepthMax, _FoamWidth, _LineTiling, _LineGain;
                half _AlphaShallow, _AlphaDeep, _ReceiveLight, _FoamEmission, _LineStrength;
                float4 _LineSpeed1, _LineSpeed2;
            CBUFFER_END
            TEXTURE2D(_CausticMap); SAMPLER(sampler_CausticMap);
            #include "Assets/Art/Environment/Shaders/ToonCaustic.hlsl"

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                half fogFactor : TEXCOORD1;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs p = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = p.positionCS;
                o.positionWS = p.positionWS;
                o.fogFactor = ComputeFogFactor(p.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float2 suv = GetNormalizedScreenSpaceUV(i.positionCS);
                float sceneEye = LinearEyeDepth(SampleSceneDepth(suv), _ZBufferParams);
                float surfEye = -TransformWorldToView(i.positionWS).z;
                float thick = max(0, sceneEye - surfEye);                 // water seen through, along the view ray

                half d = saturate(thick / _DepthMax);
                half3 sceneLight = lerp(half3(1, 1, 1), GetMainLight().color * saturate(GetMainLight().direction.y) + SampleSH(half3(0, 1, 0)), _ReceiveLight);
                half3 col = lerp(_ShallowColor.rgb, _DeepColor.rgb, d) * sceneLight;
                half alpha = lerp(_AlphaShallow, _AlphaDeep, d);

                // faint highlight lines drifting on the surface
                float l = DoubleOffsetCaustic(TEXTURE2D_ARGS(_CausticMap, sampler_CausticMap), i.positionWS.xz, _LineTiling,
                    _Time.y, _LineSpeed1.xy, _LineSpeed2.xy, 1.1, _LineGain);
                col = lerp(col, _LineColor.rgb * sceneLight, l * _LineStrength);
                alpha = max(alpha, l * _LineStrength);

                // toon foam line where the water is thinnest (against the walls)
                half foam = 1 - step(_FoamWidth, thick);
                col = lerp(col, _FoamColor.rgb * sceneLight + _FoamColor.rgb * _FoamEmission, foam);
                alpha = lerp(alpha, 0.95, foam);

                return half4(MixFog(col, i.fogFactor), alpha);
            }
            ENDHLSL
        }
    }
}
