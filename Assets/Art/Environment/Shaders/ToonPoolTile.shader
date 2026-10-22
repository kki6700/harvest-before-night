// DSEWA/ToonPoolTile: pool floor and walls. Tile mask from Designer (Art/Materials/Pool/PoolTile.sbs: Tile generator
// grayscale, 8 x 8 square tiles, grout = black, per-tile luminance variation) coloured here, mapped in world space
// (triplanar) so cubes / quads of any size keep square tiles. Lit like the ground (main light step + sky ambient,
// receives main light shadows). Below the water level the caustic mask is projected on top (ToonCaustic.hlsl,
// double offset + min), fading with depth. All colours / sizes / speeds are my own starting values.
Shader "DSEWA/ToonPoolTile"
{
    Properties
    {
        [Header(Tiles)]
        [NoScaleOffset] _TileMap ("Tile Mask (R, grout black)", 2D) = "white" {}
        _TileWorldSize ("Texture Size In Metres (8 tiles)", Float) = 1.6
        _TileColor ("Tile Color", Color) = (0.78, 0.94, 0.95, 1)
        _GroutColor ("Grout Color", Color) = (0.24, 0.52, 0.6, 1)
        _TileVariation ("Per-Tile Brightness Variation", Range(0, 1)) = 0.6
        [Header(Toon light)]
        _LightStep ("Light Step Threshold", Range(0, 1)) = 0.15
        _LightSoftness ("Light Step Softness", Range(0.001, 0.5)) = 0.08
        _ShadowStrength ("Shadow Darkness", Range(0, 1)) = 0.55
        [Header(Caustics under water)]
        [NoScaleOffset] _CausticMap ("Caustic Mask (R)", 2D) = "black" {}
        _WaterLevel ("Water Level (world Y)", Float) = 0.45
        _CausticBox ("Water Area XZ (min x, min z, max x, max z)", Vector) = (-1000, -1000, 1000, 1000)
        _CausticTiling ("Caustic Tiles Per Metre", Range(0.05, 3)) = 0.5
        _CausticSpeed1 ("Set 1 Speed", Vector) = (0.05, 0.02, 0, 0)
        _CausticSpeed2 ("Set 2 Speed", Vector) = (-0.03, 0.04, 0, 0)
        _CausticTiling2 ("Set 2 Tiling Multiplier", Range(0.5, 2)) = 1.1
        _CausticGain ("Caustic Gain", Range(0.5, 5)) = 3
        _CausticColor ("Caustic Color", Color) = (0.75, 1, 1, 1)
        _CausticStrength ("Caustic Strength", Range(0, 3)) = 1
        _CausticDepthFade ("Caustic Fade Depth (m)", Range(0.05, 5)) = 1
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "Queue" = "Geometry" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _TileWorldSize;
                half4 _TileColor, _GroutColor;
                half _TileVariation, _LightStep, _LightSoftness, _ShadowStrength;
                float _WaterLevel, _CausticTiling, _CausticTiling2, _CausticGain, _CausticDepthFade;
                float4 _CausticSpeed1, _CausticSpeed2, _CausticBox;
                half4 _CausticColor;
                half _CausticStrength;
            CBUFFER_END
            TEXTURE2D(_TileMap); SAMPLER(sampler_TileMap);
            TEXTURE2D(_CausticMap); SAMPLER(sampler_CausticMap);
            #include "Assets/Art/Environment/Shaders/ToonCaustic.hlsl"

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                half fogFactor : TEXCOORD2;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs p = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = p.positionCS;
                o.positionWS = p.positionWS;
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.fogFactor = ComputeFogFactor(p.positionCS.z);
                return o;
            }

            half TileMask(float3 pw, float3 n)
            {
                float3 w = pow(abs(n), 4); w /= (w.x + w.y + w.z);
                float s = 1.0 / _TileWorldSize;
                half ty = SAMPLE_TEXTURE2D(_TileMap, sampler_TileMap, pw.xz * s).r;
                half tx = SAMPLE_TEXTURE2D(_TileMap, sampler_TileMap, pw.zy * s).r;
                half tz = SAMPLE_TEXTURE2D(_TileMap, sampler_TileMap, pw.xy * s).r;
                return tx * w.x + ty * w.y + tz * w.z;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                half m = TileMask(i.positionWS, N);
                // grout where the mask is near black, tiles keep a little of their per-tile grey as variation
                half isTile = smoothstep(0.15, 0.3, m);
                half3 tileCol = _TileColor.rgb * lerp(1, m, _TileVariation);
                half3 albedo = lerp(_GroutColor.rgb, tileCol, isTile);

                Light light = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                half shade = saturate(dot(N, light.direction)) * light.shadowAttenuation;
                half lit = smoothstep(_LightStep, _LightStep + _LightSoftness, shade);
                half3 lightCol = light.color * lerp(1 - _ShadowStrength, 1, lit) + SampleSH(N);
                half3 col = albedo * lightCol;

                // caustics only below the water surface, strongest just under it
                float depth = _WaterLevel - i.positionWS.y;
                // inside the water area only (a few mm of slack so the inner wall faces on the border count)
                float2 pxz = i.positionWS.xz;
                half inside = step(_CausticBox.x - 0.005, pxz.x) * step(pxz.x, _CausticBox.z + 0.005)
                            * step(_CausticBox.y - 0.005, pxz.y) * step(pxz.y, _CausticBox.w + 0.005);
                half under = step(0, depth) * saturate(1 - depth / _CausticDepthFade * 0.5) * inside;
                float c = TriplanarCaustic(TEXTURE2D_ARGS(_CausticMap, sampler_CausticMap), i.positionWS, N,
                    _CausticTiling, _Time.y, _CausticSpeed1.xy, _CausticSpeed2.xy, _CausticTiling2, _CausticGain);
                col += _CausticColor.rgb * c * _CausticStrength * under * (light.color * lit + SampleSH(N) + 0.15);

                return half4(MixFog(col, i.fogFactor), 1);
            }
            ENDHLSL
        }

        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
        UsePass "Universal Render Pipeline/Lit/DepthOnly"
        UsePass "Universal Render Pipeline/Lit/DepthNormals"
    }
}
