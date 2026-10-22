// DSEWA/ToonCharacter: DSEWA/SDCatToon for characters without fur or a drawn mouth (Cunsumer and other customers).
// Same two-tone ramp, cast/cloud shadow, outline and depth passes. One addition: _RimColor (default white = the
// SDCat rim) so DayNightBlend can tint the rim per time of day like the clouds' rim. Fur and mouth stay off (0).
// SD cat toon look, ported from Art/SDCat/scripts/toon_sd_cat.py (Blender EEVEE).
// Two-tone ramp over the painted base colour, fur-broken shadow edge, lit-side rim,
// inverted-hull outline with per-vertex width + fur tufts. See Docs/SDCat-Toon-Grass-Water-Shading.md §2.
// Mesh inputs (export_sd_cat_fbx.py): COLOR.r = outline width, uv1.xy / uv2.x = rest-pose object coords.
// Flat parts (mouth inside, whiskers): disable the "Outline" pass (material pass "DSEWAOutline", the LightMode
// the outline render feature draws; the old "SRPDefaultUnlit" switch no longer hides it) and set Lit = Shadow colour.
Shader "DSEWA/ToonCharacter"
{
    Properties
    {
        _BaseMap ("Base Color", 2D) = "white" {}
        [Normal][NoScaleOffset] _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Strength", Float) = 1
        _LitColor ("Lit Color", Color) = (0.97, 0.95, 0.93, 1)
        _ShadowColor ("Shadow Color", Color) = (0.85, 0.80, 0.93, 1)
        // Blender brightness = 0.764 × N·L × shadow + 0.08 (sun 3, albedo 0.8, world 0.1); ramp 0.30..0.34 → /0.764
        _Threshold ("Shadow Threshold", Range(-1, 1.5)) = 0.393
        _Softness ("Shadow Edge Width", Range(0.001, 0.3)) = 0.053
        _ShadowBlur ("Cast Shadow Smoothing (texels, 0 = URP)", Range(0, 4)) = 1.5
        _AmbientShade ("Ambient Shade", Range(0, 1)) = 0.105
        _FurFuzz ("Fur Edge Fuzz", Range(0, 0.3)) = 0
        _FurScale ("Fur Noise Scale (rest space xyz)", Vector) = (26.9, 32.3, 6.17, 0)
        _RimColor ("Rim Color", Color) = (1, 1, 1, 1)
        _RimStrength ("Rim Strength", Range(0, 1)) = 0.18
        _RimMin ("Rim Start", Range(0, 1)) = 0.78
        _RimMax ("Rim End", Range(0, 1)) = 0.82
        _LightColorAmount ("Light Color Influence", Range(0, 1)) = 0
        [Header(In Shadow (cloud or cast shadow))]
        _ShadowFormLift ("Lit Side Lift In Shadow", Range(0, 1)) = 0
        _RimInShadow ("Rim In Shadow", Range(0, 1)) = 0
        [Header(Drawn Mouth (mouth_sd_cat_shader.py))]
        _MouthCenter ("Mouth Center (rest x, z)", Vector) = (0, 0.036, 0, 0)
        _MouthSize ("Mouth Size", Float) = 0
        _MouthLineWidth ("Mouth Line Width", Float) = 0.007
        _MouthLineColor ("Mouth Line Color", Color) = (0.58, 0.51, 0.6, 1)
        _MouthInsideColor ("Mouth Inside Color", Color) = (0.77, 0.58, 0.65, 1)
        _MouthSmile ("Mouth Smile", Range(0, 1)) = 0
        _MouthOpen ("Mouth Open", Range(0, 1)) = 0
        [Header(Outline)]
        _OutlineColor ("Outline Color", Color) = (0.70, 0.64, 0.72, 1)
        _OutlineWidth ("Outline Width (m)", Float) = 0.009
        _TuftHeight ("Fur Tuft Height (m)", Float) = 0
        _TuftSize ("Fur Tuft Size (rest units)", Float) = 0.06
        _TuftContrast ("Fur Tuft Contrast", Float) = 1.4
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half _BumpScale;
            half4 _LitColor, _ShadowColor;
            half _Threshold, _Softness, _AmbientShade, _FurFuzz;
            half _ShadowBlur;
            float4 _FurScale;
            half4 _RimColor;
            half _RimStrength, _RimMin, _RimMax, _LightColorAmount;
            half _ShadowFormLift, _RimInShadow;
            float4 _MouthCenter;
            float _MouthSize, _MouthLineWidth, _MouthSmile, _MouthOpen;
            half4 _MouthLineColor, _MouthInsideColor;
            half4 _OutlineColor;
            float _OutlineWidth, _TuftHeight, _TuftSize, _TuftContrast;
        CBUFFER_END

        float Hash31(float3 p)
        {
            p = frac(p * 0.1031);
            p += dot(p, p.zyx + 31.32);
            return frac((p.x + p.y) * p.z);
        }

        float3 Hash33(float3 p)
        {
            p = float3(dot(p, float3(127.1, 311.7, 74.7)), dot(p, float3(269.5, 183.3, 246.1)), dot(p, float3(113.5, 271.9, 124.6)));
            return frac(sin(p) * 43758.5453);
        }

        float ValueNoise(float3 p)
        {
            float3 i = floor(p), f = frac(p);
            f = f * f * (3.0 - 2.0 * f);
            return lerp(lerp(lerp(Hash31(i), Hash31(i + float3(1, 0, 0)), f.x),
                             lerp(Hash31(i + float3(0, 1, 0)), Hash31(i + float3(1, 1, 0)), f.x), f.y),
                        lerp(lerp(Hash31(i + float3(0, 0, 1)), Hash31(i + float3(1, 0, 1)), f.x),
                             lerp(Hash31(i + float3(0, 1, 1)), Hash31(i + float3(1, 1, 1)), f.x), f.y), f.z);
        }

        // Blender Noise Texture, Detail 2, Roughness 0.55 (fac roughly 0.3..0.7)
        float FurNoise(float3 p)
        {
            float sum = 0, amp = 1, norm = 0;
            [unroll] for (int o = 0; o < 3; o++) { sum += ValueNoise(p) * amp; norm += amp; amp *= 0.55; p *= 2.0; }
            return sum / norm;
        }

        // Voronoi F1 distance, the 'SD Cat · 털뭉치' Clouds/Voronoi texture
        float VoronoiF1(float3 p)
        {
            float3 i = floor(p), f = frac(p);
            float d = 8.0;
            [unroll] for (int z = -1; z <= 1; z++)
            [unroll] for (int y = -1; y <= 1; y++)
            [unroll] for (int x = -1; x <= 1; x++)
            {
                float3 c = float3(x, y, z);
                d = min(d, length(c + Hash33(i + c) - f));
            }
            return d;
        }

        float3 RestPosition(float2 uv1, float2 uv2) { return float3(uv1, uv2.x); }

        // Node group 'SD Cat Mouth' (mouth_sd_cat_shader.py): ω + optional open mouth, in rest-pose
        // Blender object space (x right, y back, z up). Tail / eyelids lie outside the face mask.
        half3 ApplyMouth(half3 color, float3 rp)
        {
            const float aa = 0.0015;
            float x = rp.x - _MouthCenter.x, z = rp.z - _MouthCenter.y;
            float front = 1 - smoothstep(-0.52, -0.48, rp.y);
            float r = _MouthSize, hw = _MouthLineWidth * 0.5;
            #define MOUTH_STROKE(d) (1 - smoothstep(hw - aa, hw, abs(d)))
            float lx = abs(x) - r;
            float ring = MOUTH_STROKE(length(float2(lx, z)) - r);
            float limit = _MouthSmile * r * 0.35 * smoothstep(-0.002, 0.002, lx);
            float omega = ring * (1 - smoothstep(limit - 0.002, limit + 0.002, z));
            float h = max(_MouthOpen * r * 1.4, 0.0001), ew = r * 1.1;
            float e = length(float2(x / ew, (z - (-0.3 * r - h)) / h));
            float on = smoothstep(0.02, 0.05, _MouthOpen);
            float fill = (1 - smoothstep(0.97, 1.0, e)) * on;
            float rim = MOUTH_STROKE((e - 1) * min(ew, h)) * on;
            #undef MOUTH_STROKE
            omega *= 1 - fill;
            color = lerp(color, _MouthInsideColor.rgb, fill * front);
            return lerp(color, _MouthLineColor.rgb, max(omega, rim) * front);
        }
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
            #include "Assets/Art/Environment/Shaders/CloudShadow.hlsl"   // SurvivalKit cloud shadow: direct light only
            #include "Assets/Art/Environment/Shaders/ToonShadow.hlsl"     // smooth-contoured toon cast shadow

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
                float2 uv1 : TEXCOORD1;
                float2 uv2 : TEXCOORD2;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float4 tangentWS : TEXCOORD3;
                float3 restPos : TEXCOORD4;
                half fogFactor : TEXCOORD5;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs nrm = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                o.positionCS = pos.positionCS;
                o.positionWS = pos.positionWS;
                o.normalWS = nrm.normalWS;
                o.tangentWS = float4(nrm.tangentWS, input.tangentOS.w * GetOddNegativeScale());
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                o.restPos = RestPosition(input.uv1, input.uv2);
                o.fogFactor = ComputeFogFactor(pos.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 bitangent = i.tangentWS.w * cross(i.normalWS, i.tangentWS.xyz);
                half3 nTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.uv), _BumpScale);
                float3 N = normalize(TransformTangentToWorld(nTS, float3x3(i.tangentWS.xyz, bitangent, i.normalWS)));
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);

                Light light = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                // Blender: Diffuse → Shader to RGB → BW, plus fur noise nudging the edge
                half direct = ToonMainLightShadow(i.positionWS, _ShadowBlur) * EvaluateCloudShadow(i.positionWS);       // cloud shadow dims direct light only
                float shade = saturate(dot(N, light.direction)) * direct + _AmbientShade;
                float fur = FurNoise(i.restPos * _FurScale.xyz);
                shade += lerp(-_FurFuzz, _FurFuzz, saturate((fur - 0.3) / 0.4));
                float lit = smoothstep(_Threshold, _Threshold + _Softness, shade);
                // In shadow the whole body used to collapse to one flat Shadow Color. Keep the form: the side that
                // faces the light (ramp without occlusion) stays a step brighter than the core shadow -> 3 tones.
                float facesLight = smoothstep(_Threshold, _Threshold + _Softness, shade - saturate(dot(N, light.direction)) * (direct - 1));
                float tone = lit + (facesLight - lit) * _ShadowFormLift;

                half3 base = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb;
                half3 color = lerp(_ShadowColor.rgb, _LitColor.rgb, tone) * base;

                float facing = 1.0 - abs(dot(N, V));
                color += _RimColor.rgb * smoothstep(_RimMin, _RimMax, facing) * _RimStrength * lerp(_RimInShadow, 1, lit);
                color = ApplyMouth(color, i.restPos);
                color *= lerp(half3(1, 1, 1), light.color, _LightColorAmount);
                color = MixFog(color, i.fogFactor);
                return half4(color, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "Outline"
            // drawn by the "SDCat Outline" RenderObjects feature after the opaques (custom tag, so the opaque pass skips it):
            // with depth priming the opaque pass tests depth Equal, and the inflated hull is not in the depth prepass
            Tags { "LightMode" = "DSEWAOutline" }
            Cull Front

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 color : COLOR;
                float2 uv1 : TEXCOORD1;
                float2 uv2 : TEXCOORD2;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                half fogFactor : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                // Solidify (0.009 × width) + Displace (Voronoi tufts × 0.025 × width), both outward along the normal
                float width = input.color.r;
                float tuft = saturate((VoronoiF1(RestPosition(input.uv1, input.uv2) / _TuftSize) - 0.5) * _TuftContrast + 0.5);
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                positionWS += normalWS * (_OutlineWidth + _TuftHeight * tuft) * width;
                o.positionCS = TransformWorldToHClip(positionWS);
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                return half4(MixFog(_OutlineColor.rgb, i.fogFactor), 1);
            }
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

        // RVT stand-in (Notion grass page §8-9): GroundColorBaker draws this pass from above into
        // _DSEWA_GroundColor so foliage roots can take the ground colour under them. Lit albedo only.
        Pass
        {
            Name "GroundColorBake"
            Tags { "LightMode" = "DSEWAGroundBake" }
            Cull Off ZWrite Off ZTest Always

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            Varyings vert(Attributes input)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                return half4(SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb * _LitColor.rgb, 1);
            }
            ENDHLSL
        }
    }
}
