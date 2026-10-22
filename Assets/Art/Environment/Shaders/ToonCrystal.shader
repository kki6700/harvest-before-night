// DSEWA/ToonCrystal: faceted glowing crystals for the alien farm.
// Same two-tone toon ramp, cast/cloud shadow and rim as the other DSEWA toon shaders (so DayNightBlend can drive
// _LitColor/_ShadowColor/_RimColor per time of day). Ported from the Blender preview material in
// Art/Environment/scripts/crystal_shards.py (2026-10-16), forward code in ToonCrystalForward.hlsl:
//   Gradient - lit colour fades to Tip Color toward the top of the renderer bounds (shadow side too, darker).
//   Facets   - small hue shift per facet (flat normal) + saturation, so neighbouring facets differ.
//   Sheen    - rainbow tint on grazing facets (thin-film look).
//   MatCap   - sphere image by view-space normal; facet borders flip in brightness (Unity-only extra).
//   Glow     - core (facing the camera) + cut faces (vertex colour G) + edges (vertex colour R), HDR for Bloom,
//              breathing in and out on a per-object phase (Pulse).
//   Gloss    - sky/probe reflection + sharp main-light highlight, Fresnel-weighted, tinted to the tip colour.
//   Glass    - transparent: alpha from Fresnel (see-through face-on, solid at the edges). Back faces are drawn first
//              (SRPDefaultUnlit pass, Cull Front) so the far facets show through like the inside of a gem.
// Flat Shading uses screen-space derivatives for one normal per facet. All defaults are my own starting values.
Shader "DSEWA/ToonCrystal"
{
    Properties
    {
        _BaseMap ("Base Color", 2D) = "white" {}
        [ToggleUI] _BoxMap ("Box Map Base Color (object-space triplanar, ignores UVs)", Float) = 0
        _BoxMapScale ("Box Map Tiles Per Metre", Range(0.1, 8)) = 1.5
        _LitColor ("Lit Color", Color) = (0.36, 0.8, 0.95, 1)
        _ShadowColor ("Shadow Color", Color) = (0.22, 0.24, 0.62, 1)
        _Threshold ("Shadow Threshold", Range(-1, 1.5)) = 0.35
        _Softness ("Shadow Edge Width", Range(0.001, 0.3)) = 0.04
        _ShadowBlur ("Cast Shadow Smoothing (texels, 0 = URP)", Range(0, 4)) = 1.5
        _AmbientShade ("Ambient Shade", Range(0, 1)) = 0.1
        [ToggleUI] _ReceiveShadows ("Receive Shadows (cast + cloud)", Float) = 0
        [ToggleUI] _FlatShading ("Flat Shading (one normal per facet)", Float) = 1
        [Header(Gradient and Facet Colour)]
        _TipColor ("Tip Color (lit colour toward the top)", Color) = (0.6, 0.55, 1, 1)
        _TipShadow ("Tip Colour In Shadow", Range(0, 1)) = 0.35
        _GradientRange ("Gradient Start / End (0-1 of height)", Vector) = (0, 0.85, 0, 0)
        _HueShift ("Hue Shift Per Facet", Range(0, 0.3)) = 0.11
        _Saturation ("Saturation", Range(0, 2)) = 1.25
        [Header(Brush Strokes)]
        [NoScaleOffset] _BrushTex ("Brush Stroke Texture (R, 0.5 = neutral)", 2D) = "gray" {}
        _BrushTiling ("Strokes Per Metre", Range(0.1, 8)) = 1.6
        _BrushValue ("Brightness Variation", Range(0, 0.6)) = 0
        _BrushEdge ("Shadow Edge Breakup", Range(0, 0.6)) = 0
        _BrushHue ("Hue Variation", Range(0, 0.1)) = 0
        [Header(Rainbow Sheen (grazing facets))]
        _SheenStrength ("Sheen Strength", Range(0, 2)) = 0.4
        _SheenPower ("Sheen Falloff", Range(0.5, 4)) = 1.3
        _Sheen0 ("Sheen 1", Color) = (1, 0.2, 0.8, 1)
        _Sheen1 ("Sheen 2", Color) = (0.2, 0.6, 1, 1)
        _Sheen2 ("Sheen 3", Color) = (0.2, 1, 0.7, 1)
        _Sheen3 ("Sheen 4", Color) = (1, 0.85, 0.3, 1)
        [Header(MatCap)]
        [NoScaleOffset] _MatCap ("MatCap (sphere image)", 2D) = "black" {}
        _MatCapColor ("MatCap Tint", Color) = (1, 1, 1, 1)
        _MatCapStrength ("MatCap Strength", Range(0, 2)) = 0.5
        _MatCapInShadow ("MatCap In Shadow", Range(0, 1)) = 0.5
        [Header(Edge Glow (vertex colour R))]
        [ToggleUI] _EdgeFromVertexColor ("Use Vertex Colour R As Edge Mask", Float) = 0
        [HDR] _EdgeColor ("Edge Color", Color) = (0.6, 2.4, 2.2, 1)
        _EdgeStrength ("Edge Strength", Range(0, 2)) = 1
        [Header(Cut Face Glow (vertex colour G, crystal_shards.py marks fracture faces))]
        [ToggleUI] _CutFromVertexColor ("Use Vertex Colour G As Cut Mask", Float) = 0
        [HDR] _CutColor ("Cut Color", Color) = (1.2, 2.0, 2.4, 1)
        _CutStrength ("Cut Strength", Range(0, 2)) = 0.6
        [Header(Core Glow)]
        [HDR] _CoreColor ("Core Color", Color) = (0.25, 0.9, 1.0, 1)
        _CorePower ("Core Falloff", Range(0.5, 8)) = 2.5
        _CoreStrength ("Core Strength", Range(0, 2)) = 0.3
        [Header(Texture Glow (bright parts of the Base Color glow))]
        _TexGlowStrength ("Texture Glow Strength (0 = off)", Range(0, 4)) = 0
        _TexGlowThreshold ("Brightness Where Glow Starts", Range(0, 1)) = 0.55
        _TexGlowSoftness ("Glow Edge Softness", Range(0.01, 0.5)) = 0.15
        [HDR] _TexGlowTint ("Texture Glow Tint", Color) = (1, 1, 1, 1)
        _TexGlowPulse ("Texture Glow Min / Max Over The Beat (1, 1 = steady)", Vector) = (1, 1, 0, 0)
        [Header(Glow Pulse)]
        _PulsePeriod ("Pulse Period (s)", Range(0.2, 10)) = 3.2
        _PulseBase ("Whole Glow Min / Max", Vector) = (0.85, 1.15, 0, 0)
        _PulseGlow ("Core + Cut + Edge Min / Max", Vector) = (0.45, 1.6, 0, 0)
        _PulseCell ("Beat Shared Within (m, 0 = per crystal)", Float) = 5
        [Header(Radial Glow (lantern fruit style))]
        _RadialMix ("Core: Facing (0) / From The Foot (1)", Range(0, 1)) = 0.7
        _RadialPower ("Radial Falloff", Range(0.5, 6)) = 1.6
        _WaveStrength ("Wave Per Beat", Range(0, 2)) = 0.5
        _WaveWidth ("Wave Width (0-1 of height)", Range(0.02, 0.6)) = 0.18
        _WaveSpan ("Wave Travel Time (0-1 of the beat)", Range(0.1, 1)) = 0.6
        [Header(Gloss and Reflection)]
        _GlossRoughness ("Gloss Roughness", Range(0.01, 1)) = 0.12
        _GlossFacing ("Reflection Face-on", Range(0, 1)) = 0.08
        _GlossGrazing ("Reflection At Grazing", Range(0, 2)) = 0.6
        _GlossTint ("Reflection Tint To Tip Colour", Range(0, 1)) = 0.35
        _SpecStrength ("Light Highlight", Range(0, 2)) = 0.6
        [Header(Glass)]
        _OpacityFacing ("Opacity Face-on", Range(0, 1)) = 0.6
        _OpacityGrazing ("Opacity At Edges", Range(0, 1)) = 0.95
        _BackFaceOpacity ("Back Faces (inside of the gem)", Range(0, 1)) = 1
        // render state, set by script for the opaque cel look (queue 2000, ZWrite On, Blend One Zero, back-face pass off)
        [HideInInspector] _SrcBlend ("Src Blend", Float) = 5
        [HideInInspector] _DstBlend ("Dst Blend", Float) = 10
        [HideInInspector] _ZWrite ("ZWrite", Float) = 0
        [Header(Rim)]
        _RimColor ("Rim Color", Color) = (1, 1, 1, 1)
        _RimStrength ("Rim Strength", Range(0, 1)) = 0.12
        _RimMin ("Rim Start", Range(0, 1)) = 0.86
        _RimMax ("Rim End", Range(0, 1)) = 0.9
        _LightColorAmount ("Light Color Influence", Range(0, 1)) = 0
        [Header(Outline)]
        _OutlineColor ("Outline Color", Color) = (0.2, 0.25, 0.5, 1)
        _OutlineWidth ("Outline Width (m at the model's own size, 0 = off)", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline" "Queue" = "Transparent" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            float _BoxMap, _BoxMapScale;
            half4 _LitColor, _ShadowColor;
            half _Threshold, _Softness, _ShadowBlur, _AmbientShade, _FlatShading, _ReceiveShadows;
            half4 _TipColor;
            half _TipShadow;
            float4 _GradientRange;
            half _HueShift, _Saturation;
            float _BrushTiling;
            half _BrushValue, _BrushEdge, _BrushHue;
            half _SheenStrength, _SheenPower;
            half4 _Sheen0, _Sheen1, _Sheen2, _Sheen3;
            half4 _MatCapColor;
            half _MatCapStrength, _MatCapInShadow;
            half _EdgeFromVertexColor;
            half4 _EdgeColor;
            half _EdgeStrength;
            half _CutFromVertexColor;
            half4 _CutColor;
            half _CutStrength;
            half4 _CoreColor;
            half _CorePower, _CoreStrength;
            half _TexGlowStrength, _TexGlowThreshold, _TexGlowSoftness;
            half4 _TexGlowTint;
            float4 _TexGlowPulse;
            float _PulsePeriod;
            float4 _PulseBase, _PulseGlow;
            float _PulseCell;
            half _RadialMix, _RadialPower, _WaveStrength, _WaveWidth, _WaveSpan;
            half _GlossRoughness, _GlossFacing, _GlossGrazing, _GlossTint, _SpecStrength;
            half _OpacityFacing, _OpacityGrazing, _BackFaceOpacity;
            half4 _RimColor;
            half _RimStrength, _RimMin, _RimMax, _LightColorAmount;
            half4 _OutlineColor;
            float _OutlineWidth;
        CBUFFER_END
                // outline width is in metres at the model's own size: a prefab scaled to 0.18 gets a 0.18x line
        // (geometric mean of the object scale, so non-uniform boxes do not blow up)
        float OutlineObjectScale()
        {
            float3x3 m = (float3x3)GetObjectToWorldMatrix();
            return pow(abs(determinant(m)), 1.0 / 3.0);
        }
        ENDHLSL

        // back faces first (URP draws SRPDefaultUnlit before UniversalForward for the same object)
        Pass
        {
            Name "BackFaces"
            Tags { "LightMode" = "SRPDefaultUnlit" }
            Cull Front ZWrite Off
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex CrystalVert
            #pragma fragment CrystalFrag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #define TOON_CRYSTAL_BACKFACE
            #include "Assets/Art/Environment/Shaders/ToonCrystalForward.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }
            Cull Back ZWrite [_ZWrite]
            Blend [_SrcBlend] [_DstBlend]

            HLSLPROGRAM
            #pragma vertex CrystalVert
            #pragma fragment CrystalFrag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #include "Assets/Art/Environment/Shaders/ToonCrystalForward.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "Outline"
            // drawn by the outline RenderObjects feature (see DSEWA/ToonCharacter); width 0 = nothing visible
            Tags { "LightMode" = "DSEWAOutline" }
            Cull Front

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; half fogFactor : TEXCOORD0; UNITY_VERTEX_OUTPUT_STEREO };

            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                positionWS += TransformObjectToWorldNormal(input.normalOS) * _OutlineWidth * OutlineObjectScale();
                o.positionCS = TransformWorldToHClip(positionWS);
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target { return half4(MixFog(_OutlineColor.rgb, i.fogFactor), 1); }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; UNITY_VERTEX_INPUT_INSTANCE_ID };

            float4 vert(Attributes input) : SV_POSITION
            {
                UNITY_SETUP_INSTANCE_ID(input);
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDir = normalize(_LightPosition - positionWS);
            #else
                float3 lightDir = _LightDirection;
            #endif
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDir));
            #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                return positionCS;
            }

            half4 frag() : SV_Target { return 0; }
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

            float4 vert(Attributes input) : SV_POSITION
            {
                UNITY_SETUP_INSTANCE_ID(input);
                return TransformObjectToHClip(input.positionOS.xyz);
            }

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
