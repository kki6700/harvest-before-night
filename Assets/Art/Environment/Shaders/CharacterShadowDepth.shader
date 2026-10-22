// Character-only shadow map (Wuthering Waves style split: characters get their own high-res shadow, the scene keeps
// the cascades). Drawn by CharacterShadow.cs with DrawRenderer: writes the distance along the light into an RFloat
// target with Min blending, so no depth buffer / reversed-Z conventions are involved.
// Light space and the map rect come from globals set by CharacterShadow.cs (see ToonShadow.hlsl for the reader).
Shader "Hidden/DSEWA/CharacterShadowDepth"
{
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        Pass
        {
            Cull Off ZWrite Off ZTest Always
            BlendOp Min
            Blend One One

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float4x4 _DSEWA_CharShadowView;   // world -> light space (+z along the light)
            float4 _DSEWA_CharShadowRect;      // light-space (minX, minY, 1/sizeX, 1/sizeY)

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings { float4 positionCS : SV_POSITION; float depth : TEXCOORD0; };

            Varyings vert(Attributes input)
            {
                Varyings o;
                float3 lv = mul(_DSEWA_CharShadowView, float4(TransformObjectToWorld(input.positionOS.xyz), 1)).xyz;
                float2 uv = (lv.xy - _DSEWA_CharShadowRect.xy) * _DSEWA_CharShadowRect.zw;
                float2 ndc = uv * 2 - 1;
            #if UNITY_UV_STARTS_AT_TOP
                ndc.y = -ndc.y;   // keep texel (u, v) = the uv the receivers compute
            #endif
                o.positionCS = float4(ndc, 0.5, 1);
                o.depth = lv.z;
                return o;
            }

            float frag(Varyings i) : SV_Target { return i.depth; }
            ENDHLSL
        }
    }
}
