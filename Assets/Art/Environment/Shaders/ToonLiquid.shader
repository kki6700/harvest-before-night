// DSEWA/ToonLiquid: glowing liquid inside a glass container (fertilizer bottle), toon style.
// The liquid mesh is a closed inner volume; everything above the fill plane is clipped away. Back faces that remain are
// drawn as the flat liquid surface seen from above (the classic "back face = surface" trick), so no cap mesh is needed.
// The fill plane stays level in world space; LiquidWobble.cs tilts it (_WobbleX / _WobbleZ) when the bottle is moved.
// Opaque with clip (AlphaTest queue), so the transparent glass (DSEWA/ToonCrystal, Transparent queue) always draws after
// it and there is no transparent-on-transparent sorting problem.
// The PC renderer forces depth priming and SSAO uses the DepthNormals prepass: an opaque shader is only drawn where its
// DepthNormals / DepthOnly pass wrote depth, so both must clip exactly like ForwardLit (with the instance id set up,
// the GPU Resident Drawer is on). Without them the liquid simply does not appear.
// All defaults are my own starting values.
Shader "DSEWA/ToonLiquid"
{
    Properties
    {
        _Fill ("Fill (0 = empty, 1 = full)", Range(0, 1)) = 0.75
        [Header(Colour)]
        _DeepColor ("Deep Color (bottom)", Color) = (0.05, 0.42, 0.55, 1)
        _ShallowColor ("Shallow Color (near the surface)", Color) = (0.3, 0.82, 0.86, 1)
        _SurfaceColor ("Surface Color (top, seen from above)", Color) = (0.55, 0.95, 0.95, 1)
        _ShadowTint ("Shadow Tint", Color) = (0.55, 0.6, 0.9, 1)
        _Threshold ("Shadow Threshold", Range(-1, 1)) = 0.1
        _Softness ("Shadow Edge Width", Range(0.001, 0.5)) = 0.15
        [Header(Glow)]
        [HDR] _GlowColor ("Glow Color", Color) = (0.3, 1.4, 1.5, 1)
        _GlowStrength ("Glow Strength", Range(0, 3)) = 0.6
        _SurfaceGlow ("Extra Glow On The Surface", Range(0, 3)) = 0.8
        _RimStrength ("Rim (edge against the glass)", Range(0, 2)) = 0.5
        _RimPower ("Rim Falloff", Range(0.5, 8)) = 3
        _FoamWidth ("Surface Edge Line Width (m)", Range(0, 0.03)) = 0.006
        [HDR] _FoamColor ("Surface Edge Line Color", Color) = (0.8, 1.6, 1.6, 1)
        [Header(Wobble (set by LiquidWobble.cs))]
        _WobbleX ("Wobble X (surface slope)", Range(-1, 1)) = 0
        _WobbleZ ("Wobble Z (surface slope)", Range(-1, 1)) = 0
        [HideInInspector] _LiquidBox ("Liquid Box (set by script)", Vector) = (0, 0, 0, 0)
    }

    SubShader
    {
        Tags { "RenderType" = "TransparentCutout" "Queue" = "AlphaTest" "RenderPipeline" = "UniversalPipeline" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float _Fill;
            half4 _DeepColor, _ShallowColor, _SurfaceColor, _ShadowTint;
            half _Threshold, _Softness;
            half4 _GlowColor;
            half _GlowStrength, _SurfaceGlow, _RimStrength, _RimPower, _FoamWidth;
            half4 _FoamColor;
            float _WobbleX, _WobbleZ;
            float4 _LiquidBox;   // set by LiquidWobble.cs: centre x, centre z, bottom y, top y (world)
        CBUFFER_END

        // liquid's world extent, written every frame by LiquidWobble.cs (the shader needs that script on the renderer)
        void LiquidExtent(out float2 centreXZ, out float bottom, out float top)
        {
            centreXZ = _LiquidBox.xy; bottom = _LiquidBox.z; top = _LiquidBox.w;
        }

        // world height of the fill plane at this point (level, tilted by the wobble around the liquid's centre)
        float SurfaceHeight(float3 positionWS)
        {
            float2 c; float bottom, top;
            LiquidExtent(c, bottom, top);
            float level = lerp(bottom, top, saturate(_Fill));
            return level + (positionWS.x - c.x) * _WobbleX + (positionWS.z - c.y) * _WobbleZ;
        }
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            Cull Off
            ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile_fog
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Assets/Art/Environment/Shaders/GroundFog.hlsl"

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                half fogFactor : TEXCOORD2;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                VertexPositionInputs p = GetVertexPositionInputs(input.positionOS.xyz);
                o.positionCS = p.positionCS;
                o.positionWS = p.positionWS;
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                o.fogFactor = ComputeFogFactor(p.positionCS.z);
                return o;
            }

            half4 frag(Varyings i, bool frontFace : SV_IsFrontFace) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float surface = SurfaceHeight(i.positionWS);
                float below = surface - i.positionWS.y;          // metres under the fill plane
                clip(below);

                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                Light light = GetMainLight();
                half3 color;
                if (frontFace)
                {
                    float3 N = normalize(i.normalWS);
                    float2 c; float bottom, top;
                    LiquidExtent(c, bottom, top);
                    float span = max(top - bottom, 1e-3);
                    half depth01 = saturate(below / max(span * saturate(_Fill), 1e-3));   // 0 at the surface, 1 at the bottom
                    half3 body = lerp(_ShallowColor.rgb, _DeepColor.rgb, depth01);
                    half lit = smoothstep(_Threshold, _Threshold + _Softness, dot(N, light.direction));
                    color = body * lerp(_ShadowTint.rgb, half3(1, 1, 1), lit);
                    color += _GlowColor.rgb * _GlowStrength * (1.0 - depth01 * 0.6);
                    color += _GlowColor.rgb * pow(1.0 - saturate(dot(N, V)), _RimPower) * _RimStrength;
                    // thin bright line where the side meets the surface (meniscus)
                    color = lerp(color, _FoamColor.rgb, step(below, _FoamWidth));
                }
                else
                {
                    // inside of the volume seen from above = the liquid surface
                    color = _SurfaceColor.rgb + _GlowColor.rgb * _SurfaceGlow;
                }
                color = ApplyGroundFog(color, i.positionWS);
                color = MixFog(color, i.fogFactor);
                return half4(color, 1);
            }
            ENDHLSL
        }


        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On ColorMask R Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            struct Attributes { float4 positionOS : POSITION; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; float3 positionWS : TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, o);
                VertexPositionInputs p = GetVertexPositionInputs(input.positionOS.xyz);   // same maths as ForwardLit
                o.positionWS = p.positionWS;
                o.positionCS = p.positionCS;
                return o;
            }
            half frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                clip(SurfaceHeight(i.positionWS) - i.positionWS.y);
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }
            ZWrite On Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT
            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; float3 positionWS : TEXCOORD0; float3 normalWS : TEXCOORD1; UNITY_VERTEX_INPUT_INSTANCE_ID };
            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, o);
                VertexPositionInputs p = GetVertexPositionInputs(input.positionOS.xyz);
                o.positionWS = p.positionWS;
                o.positionCS = p.positionCS;
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return o;
            }
            half4 frag(Varyings i, bool frontFace : SV_IsFrontFace) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                clip(SurfaceHeight(i.positionWS) - i.positionWS.y);
                float3 n = frontFace ? normalize(i.normalWS) : float3(0, 1, 0);   // back faces = the level surface
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
