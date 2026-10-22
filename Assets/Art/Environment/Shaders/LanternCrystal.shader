// DSEWA/LanternCrystal: the glowing crystal shards of the hanging crystal lantern (pf_prop_lamp_stand / Lantern_Crystal,
// crystal material slot; the metal parts keep DSEWA/ToonSoft). A lamp, so it is mostly light, not lit:
//   - height gradient (object space): violet at the top -> cyan at the tip, mixed with the baked painted texture
//   - per-facet hue shift (flat facet normal) so the shards read as cut crystal
//   - inner light: facets facing the viewer glow brighter (light coming out of the crystal), edges stay deeper
//   - lamp life: slow breath + irregular candle-like flicker (two sines of unrelated speeds), per object
//   - occasional sparkle on single facets
//   - light toon shading so it still sits in the scene, ground fog, depth passes for forced depth priming + SSAO
// All defaults are my own starting values.
Shader "DSEWA/LanternCrystal"
{
    Properties
    {
        _BaseMap ("Painted Texture (optional)", 2D) = "white" {}
        _TextureMix ("Texture Mix", Range(0, 1)) = 0.35
        [Header(Colour)]
        _TopColor ("Top Color", Color) = (0.62, 0.38, 1, 1)
        _BottomColor ("Tip Color", Color) = (0.35, 0.95, 1, 1)
        _GradientRange ("Gradient Bottom / Top (object Y)", Vector) = (-1, -0.25, 0, 0)
        _FacetHue ("Hue Shift Per Facet", Range(0, 0.2)) = 0.06
        _Saturation ("Saturation", Range(0, 2)) = 1.15
        [Header(Inner Light)]
        [HDR] _GlowColor ("Glow Tint", Color) = (1.4, 1.3, 2.2, 1)
        _GlowStrength ("Glow Strength", Range(0, 4)) = 1.2
        _CorePower ("Facing Falloff (higher = tighter core)", Range(0.3, 6)) = 1.5
        _EdgeDepth ("Edge Depth (darker, deeper edges)", Range(0, 1)) = 0.35
        _ShadeAmount ("Scene Light Shading", Range(0, 1)) = 0.25
        [Header(Lamp Life)]
        _Breath ("Breath Min / Max", Vector) = (0.75, 1.15, 0, 0)
        _BreathPeriod ("Breath Period (s)", Range(0.5, 20)) = 5
        _Flicker ("Flicker Amount", Range(0, 0.6)) = 0.12
        _FlickerSpeed ("Flicker Speed", Range(0.5, 20)) = 7
        [Header(Sparkle)]
        [HDR] _SparkleColor ("Sparkle Color", Color) = (2.5, 2.5, 3, 1)
        _SparkleChance ("Sparkle Chance", Range(0, 0.3)) = 0.06
        _SparkleSpeed ("Sparkle Speed", Range(0.1, 5)) = 1.3
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half _TextureMix;
            half4 _TopColor, _BottomColor;
            float4 _GradientRange;
            half _FacetHue, _Saturation;
            half4 _GlowColor;
            half _GlowStrength, _CorePower, _EdgeDepth, _ShadeAmount;
            float4 _Breath;
            float _BreathPeriod, _Flicker, _FlickerSpeed;
            half4 _SparkleColor;
            half _SparkleChance, _SparkleSpeed;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Assets/Art/Environment/Shaders/GroundFog.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float heightOS : TEXCOORD3;
                half fogFactor : TEXCOORD4;
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
                o.heightOS = input.positionOS.y;
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                o.fogFactor = ComputeFogFactor(p.positionCS.z);
                return o;
            }

            float Hash13(float3 p) { return frac(sin(dot(p, float3(12.9898, 78.233, 37.719))) * 43758.5453); }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float3 smoothN = normalize(i.normalWS);
                float3 facetN = normalize(cross(ddy(i.positionWS), ddx(i.positionWS)));
                facetN *= sign(dot(facetN, smoothN) + 1e-5);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                half facing = saturate(dot(facetN, V));

                // colour: height gradient + some of the painted texture, hue shifted per facet
                half h = saturate((i.heightOS - _GradientRange.x) / max(_GradientRange.y - _GradientRange.x, 1e-3));
                half3 col = lerp(_BottomColor.rgb, _TopColor.rgb, h);
                col = lerp(col, SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb, _TextureMix);
                half3 hsv = RgbToHsv(col);
                hsv.x = frac(hsv.x + dot(facetN, float3(0.62, 0.7, -0.35)) * _FacetHue);
                hsv.y = saturate(hsv.y * _Saturation);
                col = HsvToRgb(hsv);

                // a little scene light so it is not a flat sticker
                Light light = GetMainLight();
                half lambert = saturate(dot(facetN, light.direction)) * 0.5 + 0.5;
                col *= lerp(1.0h, lambert, _ShadeAmount);

                // deeper edges, light pouring out of the facets that face us
                col *= lerp(1.0h - _EdgeDepth, 1.0h, facing);
                float3 objPos = GetObjectToWorldMatrix()._m03_m13_m23;
                float seed = Hash13(objPos);
                float t = _Time.y;
                float breath = lerp(_Breath.x, _Breath.y, 0.5 + 0.5 * sin((t / max(_BreathPeriod, 0.01) + seed) * TWO_PI));
                float flick = 1.0 + _Flicker * (0.6 * sin(t * _FlickerSpeed + seed * 17.0) + 0.4 * sin(t * _FlickerSpeed * 2.37 + seed * 5.0));
                half core = pow(facing, _CorePower);
                col += col * _GlowColor.rgb * core * _GlowStrength;
                col *= breath * flick;          // the whole crystal is the light: it dims and brightens as one

                // sparkle: a few facets flash now and then
                float cell = Hash13(round(facetN * 8.0) + objPos);
                float tick = floor(t * _SparkleSpeed + cell * 10.0);
                float on = step(1.0 - _SparkleChance, Hash13(float3(cell, tick, seed)));
                float fade = 1.0 - frac(t * _SparkleSpeed + cell * 10.0);
                col += _SparkleColor.rgb * on * fade * fade * facing;

                col = ApplyGroundFog(col, i.positionWS);
                col = MixFog(col, i.fogFactor);
                return half4(col, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On ColorMask R Cull Back
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            struct Attributes { float4 positionOS : POSITION; UNITY_VERTEX_INPUT_INSTANCE_ID };
            float4 vert(Attributes input) : SV_POSITION { UNITY_SETUP_INSTANCE_ID(input); return TransformObjectToHClip(input.positionOS.xyz); }
            half frag() : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }
            ZWrite On Cull Back
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT
            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; float3 normalWS : TEXCOORD0; };
            Varyings vert(Attributes input)
            {
                UNITY_SETUP_INSTANCE_ID(input);
                Varyings o;
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return o;
            }
            half4 frag(Varyings i) : SV_Target
            {
                float3 n = normalize(i.normalWS);
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
