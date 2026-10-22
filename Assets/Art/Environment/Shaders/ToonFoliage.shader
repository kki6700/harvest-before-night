// Toon grass cards for terrain details (Instanced Mesh) — Notion plan "DSEWA 수풀·잔디 기획" §5.
// Same two-tone ramp as SDCatToon; colour from the alien-planet palette, the texture only gives the
// silhouette (alpha clip) and a grey brightness. Mesh inputs (export_grass_fbx.py): normals point up,
// COLOR.r = 0 root -> 1 tip, COLOR.g = per-card random phase.
// Cat push: a script sets the global _DSEWA_CatPush = (x, y, z, radius) in world space; radius 0 = off.
Shader "DSEWA/ToonFoliage"
{
    Properties
    {
        _BaseMap ("Silhouette (alpha)", 2D) = "white" {}
        _Cutoff ("Alpha Clip", Range(0, 1)) = 0.5
        _RootColor ("Root Color", Color) = (0.12, 0.37, 0.42, 1)
        _TipColor ("Tip Color", Color) = (0.44, 0.89, 0.78, 1)
        _ShadowTint ("Shadow Tint (multiply)", Color) = (0.42, 0.40, 0.72, 1)
        _Threshold ("Shadow Threshold", Range(-1, 1.5)) = 0.393
        _Softness ("Shadow Edge Width", Range(0.001, 0.3)) = 0.053
        _ShadowBlur ("Cast Shadow Smoothing (texels, 0 = URP)", Range(0, 4)) = 1.5
        _AmbientShade ("Ambient Shade", Range(0, 1)) = 0.105
        _WindDir ("Wind Direction (xz)", Vector) = (1, 0, 0.35, 0)
        _WindStrength ("Wind Strength (m)", Float) = 0.12
        _WindSpeed ("Wind Speed", Float) = 1.6
        _WindFreq ("Wind Wave Frequency", Float) = 0.35
        _PushStrength ("Cat Push Strength (m)", Float) = 0.6
        _WindRadius ("Wind Radius around the player (m, 0 = everywhere)", Float) = 25
        _WindFade ("Wind Fade Width (m)", Float) = 10
        [Header(Color Controls (SurvivalKit MF_ColorControls order))]
        _Tint ("Tint", Color) = (1, 1, 1, 1)
        _Desaturation ("Desaturation (negative = more saturated)", Range(-1, 1)) = 0
        _HueShift ("Hue Shift (turns)", Range(-0.5, 0.5)) = 0
        _Brightness ("Brightness", Range(0, 3)) = 1
        _Contrast ("Cheap Contrast", Range(-0.5, 1)) = 0
        [Header(Wind Colour (SurvivalKit MF_GrassWind))]
        _WindColor ("Wind Colour", Color) = (0.62, 0.94, 0.86, 1)   // pale mint, same family as the grass
        _WindColorAmount ("Wind Colour Amount", Range(0, 1)) = 0.5
        _WindColorScale ("Wind Colour Scale (1/m)", Float) = 0.35
        _WindColorSpeed ("Wind Colour Speed (m/s)", Float) = 1.2
        _WindColorThreshold ("Wind Colour Threshold", Range(0, 1)) = 0.57
        _WindColorSoftness ("Wind Colour Edge Softness", Range(0.01, 0.5)) = 0.04
        [Header(Grass Shine)]
        _ShineColor ("Shine Colour", Color) = (0.85, 1, 0.95, 1)
        _ShineStrength ("Shine Strength", Range(0, 1)) = 0.25
        _ShinePower ("Shine Tip Falloff", Range(1, 8)) = 3
        [Header(Ground Blend (RVT stand in from GroundColorBaker))]
        _GroundBlend ("Ground Blend", Range(0, 1)) = 1
        _GroundBlendHeight ("Ground Blend Height (0 root, 1 tip)", Range(0.01, 1)) = 0.35
        _GroundBlendCardShade ("Keep Card Shading", Range(0, 1)) = 0.15
        [Header(Card Base (where the card meets the ground))]
        _RootSink ("Sink Into Ground (m)", Range(0, 0.1)) = 0.02
        _RootErode ("Root Edge Erosion", Range(0, 1)) = 0.6
        _RootErodeHeight ("Erosion Height (0 root, 1 tip)", Range(0.01, 0.5)) = 0.18
        _RootErodeScale ("Erosion Noise Scale (uv x, y)", Vector) = (55, 9, 0, 0)
        [Header(Grass Border (coverage baked by GroundColorBaker))]
        _EdgeShrink ("Shrink At Patch Edges", Range(0, 1)) = 1
        _EdgeShrinkMin ("Edge Min Scale", Range(0.05, 1)) = 0.35
        _EdgeShrinkRange ("Edge Coverage Range (lo, hi)", Vector) = (0.1, 0.6, 0, 0)
        [Header(Clump Volume (sphere normal from the clump pivot))]
        _Volume ("Volume (0 = flat up normal)", Range(0, 1)) = 0.6
        _VolumeHeightScale ("Volume Height Scale", Range(0.05, 2)) = 0.4
        [Header(Variation (per clump and world patches))]
        _ClumpHueVar ("Clump Hue Jitter (turns)", Range(0, 0.1)) = 0.025
        _ClumpValueVar ("Clump Brightness Jitter", Range(0, 0.5)) = 0.1
        _PatchTint ("Patch Tint (multiply)", Color) = (1.06, 1.0, 0.72, 1)
        _PatchAmount ("Patch Amount", Range(0, 1)) = 0.5
        _PatchScale ("Patch Scale (1/m)", Float) = 0.25
        [Header(Sheen and Backlight)]
        _SheenColor ("Sheen Colour", Color) = (1, 1, 0.85, 1)
        _SheenStrength ("Sheen Strength", Range(0, 1)) = 0.35
        _SheenPower ("Sheen Sharpness", Range(1, 64)) = 12
        _SheenThreshold ("Sheen Band Threshold", Range(0, 1)) = 0.55
        _SheenLean ("Blade Lean For Sheen", Range(0, 2)) = 0.8
        _TransColor ("Backlight Colour", Color) = (0.9, 1, 0.45, 1)
        _TransStrength ("Backlight Strength", Range(0, 1)) = 0.4
        [Header(Tip Glow (bioluminescent night))]
        [HDR] _TipGlowColor ("Tip Glow Colour", Color) = (0.35, 0.5, 1.6, 1)
        _TipGlow ("Tip Glow Amount (0 off)", Range(0, 2)) = 0
        _TipGlowStart ("Tip Glow Start Height (0 root, 1 tip)", Range(0, 1)) = 0.65
        _TransThreshold ("Backlight Threshold", Range(0, 1)) = 0.6
    }

    SubShader
    {
        Tags { "RenderType" = "TransparentCutout" "Queue" = "AlphaTest" "RenderPipeline" = "UniversalPipeline" }
        Cull Off

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half _Cutoff;
            half4 _RootColor, _TipColor, _ShadowTint;
            half _Threshold, _Softness, _AmbientShade;
            half _ShadowBlur;
            float4 _WindDir;
            float _WindStrength, _WindSpeed, _WindFreq, _PushStrength;
            float _WindRadius, _WindFade;
            half4 _Tint;
            half _Desaturation, _HueShift, _Brightness, _Contrast;
            half4 _WindColor;
            half _WindColorAmount, _WindColorScale, _WindColorSpeed, _WindColorThreshold, _WindColorSoftness;
            half4 _ShineColor;
            half _ShineStrength, _ShinePower;
            half _GroundBlend, _GroundBlendHeight, _GroundBlendCardShade;
            half _RootSink, _RootErode, _RootErodeHeight;
            float4 _RootErodeScale;
            half _EdgeShrink, _EdgeShrinkMin;
            half4 _EdgeShrinkRange;
            half _Volume, _VolumeHeightScale;
            half _ClumpHueVar, _ClumpValueVar;
            half4 _PatchTint;
            half _PatchAmount, _PatchScale;
            half4 _SheenColor;
            half _SheenStrength, _SheenPower, _SheenThreshold, _SheenLean;
            half4 _TransColor;
            half _TransStrength, _TransThreshold;
            half4 _TipGlowColor;
            half _TipGlow, _TipGlowStart;
        CBUFFER_END
        float4 _DSEWA_CatPush;                       // global: xyz = cat position, w = radius
        float4 _DSEWA_WindCenter;                    // global: xyz = player position, w = 1 when set (else the camera)
        float4 _DSEWA_GroundColorRect;               // global: (minX, minZ, 1/sizeX, 1/sizeZ); z = 0 -> no baker
        float4 _DSEWA_GroundShadowColor;             // global: the ground material's shadow multiply, so shaded roots match it
        float4 _DSEWA_GroundLitColor;                // global: the ground material's lit colour (the bake = albedo x lit colour)
        float4 _DSEWA_GroundLight;                   // global: ground toon ramp (threshold, softness, ambient, 1 = set)

        TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
        TEXTURE2D(_DSEWA_GroundColor); SAMPLER(sampler_DSEWA_GroundColor);
        float4 _DSEWA_GrassCoverageRect;             // global: (minX, minZ, 1/sizeX, 1/sizeZ); z = 0 -> no coverage
        TEXTURE2D(_DSEWA_GrassCoverage); SAMPLER(sampler_DSEWA_GrassCoverage);

        // Clumps at the edge of a grass patch get smaller (coverage = blurred detail density), so patches fade out
        // instead of ending in a wall. No coverage here (hand-placed grass away from patches) = full size.
        float GrassEdgeScale(float2 pivotXZ)
        {
            if (_DSEWA_GrassCoverageRect.z == 0 || _EdgeShrink <= 0) return 1;
            float2 uv = (pivotXZ - _DSEWA_GrassCoverageRect.xy) * _DSEWA_GrassCoverageRect.zw;
            if (any(uv != saturate(uv))) return 1;
            half cov = SAMPLE_TEXTURE2D_LOD(_DSEWA_GrassCoverage, sampler_DSEWA_GrassCoverage, uv, 0).r;
            if (cov < 0.002) return 1;
            return lerp(1, lerp(_EdgeShrinkMin, 1, smoothstep(_EdgeShrinkRange.x, _EdgeShrinkRange.y, cov)), _EdgeShrink);
        }

        // RVT stand-in: ground colour under a world XZ position, baked from above by GroundColorBaker.
        // a = 1 where ground was baked, 0 outside the area or with no baker.
        half4 SampleGroundColor(float2 xz)
        {
            if (_DSEWA_GroundColorRect.z == 0) return 0;
            float2 uv = (xz - _DSEWA_GroundColorRect.xy) * _DSEWA_GroundColorRect.zw;
            if (any(uv != saturate(uv))) return 0;
            return SAMPLE_TEXTURE2D_LOD(_DSEWA_GroundColor, sampler_DSEWA_GroundColor, uv, 0);
        }

        // Wind only near the player: 1 inside _WindRadius, fading to 0 over _WindFade (radius 0 = wind everywhere).
        // Centre = _DSEWA_WindCenter (FoliagePushSource on the player), else the camera.
        half WindMask(float2 xz)
        {
            if (_WindRadius <= 0) return 1;
            float2 c = _DSEWA_WindCenter.w > 0 ? _DSEWA_WindCenter.xz : _WorldSpaceCameraPos.xz;
            return 1 - smoothstep(_WindRadius, _WindRadius + max(_WindFade, 1e-3), distance(xz, c));
        }

        // Bend the card in world space: rooted (offset ∝ height²), wind wave + push away from the cat.
        float3 FoliageBend(float3 positionWS, float4 color)
        {
            float3 pivot = TransformObjectToWorld(float3(0, 0, 0));
            positionWS = pivot + (positionWS - pivot) * GrassEdgeScale(pivot.xz);   // every pass goes through here
            positionWS.y -= _RootSink;                                     // bottom edge hides under the ground
            float h = color.r * color.r;
            float2 offset = 0;
            half wind = WindMask(pivot.xz);                                // per clump: the card bends as one
            UNITY_BRANCH
            if (wind > 0)                                                  // far grass skips the wind maths
            {
                float2 dir = normalize(_WindDir.xz + 1e-5);
                float phase = _Time.y * _WindSpeed + color.g * 6.2832 + dot(positionWS.xz, dir) * _WindFreq;
                offset = dir * (sin(phase) * 0.7 + sin(phase * 2.3 + 1.7) * 0.3) * _WindStrength * h * wind;
            }
            if (_DSEWA_CatPush.w > 0)
            {
                float2 away = positionWS.xz - _DSEWA_CatPush.xz;
                float d = length(away);
                float k = saturate(1 - d / _DSEWA_CatPush.w);
                k *= k;
                offset += (away / max(d, 1e-3)) * k * _PushStrength * h;
                positionWS.y -= k * _PushStrength * 0.5 * h;               // lie down a little
            }
            positionWS.xz += offset;
            return positionWS;
        }

        half3 HueRotate(half3 c, float turns)                             // rotate around the grey axis
        {
            float a = turns * 6.2832;
            float3 k = float3(0.57735, 0.57735, 0.57735);
            float ca = cos(a), sa = sin(a);
            return c * ca + cross(k, c) * sa + k * dot(k, c) * (1 - ca);
        }

        // MF_ColorControls: Color x Tint -> Desaturation -> HueShift -> Brightness -> CheapContrast
        half3 ColorControls(half3 c)
        {
            c *= _Tint.rgb;
            half lum = dot(c, half3(0.2126, 0.7152, 0.0722));
            c = lerp(c, lum.xxx, _Desaturation);                          // negative values push saturation up
            c = HueRotate(c, _HueShift);
            c *= _Brightness;
            return saturate(lerp(-_Contrast, 1 + _Contrast, c));          // SurvivalKitCheapContrast
        }

        float Hash21(float2 p)
        {
            p = frac(p * float2(123.34, 456.21));
            p += dot(p, p + 45.32);
            return frac(p.x * p.y);
        }

        float ValueNoise2(float2 p)
        {
            float2 i = floor(p), f = frac(p);
            f = f * f * (3 - 2 * f);
            return lerp(lerp(Hash21(i), Hash21(i + float2(1, 0)), f.x),
                        lerp(Hash21(i + float2(0, 1)), Hash21(i + float2(1, 1)), f.x), f.y);
        }

        // MF_GrassWind colour part: a world-space noise scrolling with the wind tints the field in gusts.
        // Hard-edged (toon) bands; stronger towards the tips.
        half WindColorMask(float3 positionWS, half height)
        {
            half near = WindMask(positionWS.xz);
            UNITY_BRANCH
            if (near <= 0) return 0;
            float2 dir = normalize(_WindDir.xz + 1e-5);
            float2 p = positionWS.xz * _WindColorScale - dir * _Time.y * _WindColorSpeed * _WindColorScale;
            float n = ValueNoise2(p) * 0.65 + ValueNoise2(p * 2.3 + 17.1) * 0.35;
            return smoothstep(_WindColorThreshold, _WindColorThreshold + _WindColorSoftness, n) * saturate(0.35 + height) * near;
        }

        // Card base: near the root, vertical streak noise eats into the silhouette so the card does not end in a
        // straight line where it meets the ground (stems / gaps instead). Returns 1 = keep, 0 = cut.
        half RootKeep(float2 uv, half height)
        {
            half bottom = 1 - smoothstep(0, _RootErodeHeight, height);
            if (bottom <= 0 || _RootErode <= 0) return 1;
            float n = ValueNoise2(uv * _RootErodeScale.xy) * 0.7 + ValueNoise2(uv * _RootErodeScale.xy * 2.7 + 13.1) * 0.3;
            return step(bottom * _RootErode, n);
        }

        void ClipAlpha(float3 uvh)
        {
            clip(SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvh.xy).a * RootKeep(uvh.xy, uvh.z) - _Cutoff);
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
            #include "Assets/Art/Environment/Shaders/GroundFog.hlsl"      // ground-only distance fog

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 color : COLOR;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                half height : TEXCOORD3;
                half fogFactor : TEXCOORD4;
                float2 restXZ : TEXCOORD5;               // unbent world XZ: ground colour must not slide with the wind
                float3 volumeWS : TEXCOORD6;             // clump dome normal (also leans the blades for the sheen)
                half clump : TEXCOORD7;                  // per-clump random from the pivot position
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                float3 restWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 positionWS = FoliageBend(restWS, input.color);
                o.positionWS = positionWS;
                o.restXZ = restWS.xz;
                o.positionCS = TransformWorldToHClip(positionWS);
                // Clump volume: the mesh normals all point up (same light everywhere = flat); blend towards a dome
                // centred on the pivot so each clump gets a sunny side and a toon-shadow side.
                float3 domeOS = float3(input.positionOS.x, input.positionOS.y * _VolumeHeightScale + 1e-3, input.positionOS.z);
                o.volumeWS = TransformObjectToWorldNormal(normalize(domeOS));
                o.normalWS = normalize(lerp(TransformObjectToWorldNormal(input.normalOS), o.volumeWS, _Volume));
                o.clump = Hash21(TransformObjectToWorld(float3(0, 0, 0)).xz * 7.13);
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                o.height = input.color.r;
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                clip(tex.a * RootKeep(i.uv, i.height) - _Cutoff);
                half4 ground = SampleGroundColor(i.restXZ);                                          // roots grow out of the ground
                half rootT = saturate(i.height / _GroundBlendHeight);
                half rootMask = (1 - rootT * rootT * rootT * (rootT * (rootT * 6 - 15) + 10)) * _GroundBlend * ground.a;   // smootherstep: no visible start / end

                // Roots are lit like the ground under them (up normal, the ground's shadow colour), the blade like grass.
                // Both are toon-cut separately and the finished colours blended by height: blending the normals before
                // the cut flipped light / shadow halfway up the blade and left a hard band.
                Light light = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                half direct = min(ToonMainLightShadow(i.positionWS, _ShadowBlur), ToonCharacterShadow(i.positionWS, _ShadowBlur)) * EvaluateCloudShadow(i.positionWS);       // cloud shadow dims direct light only
                float lit = smoothstep(_Threshold, _Threshold + _Softness, saturate(dot(normalize(i.normalWS), light.direction)) * direct + _AmbientShade);
                // Root ramp = the ground's own ramp (its threshold / softness / ambient), else the root reads as shadow
                // on sunlit ground (low sun: ground 0.35 > its 0.12 threshold but < the grass 0.393).
                half4 gl = _DSEWA_GroundLight.w > 0 ? _DSEWA_GroundLight : half4(_Threshold, _Softness, _AmbientShade, 0);
                float litRoot = smoothstep(gl.x, gl.x + gl.y, saturate(light.direction.y) * direct + gl.z);

                half3 color = ColorControls(lerp(_RootColor.rgb, _TipColor.rgb, i.height) * tex.rgb);
                // Variation: every clump a little different, plus large world patches (drier / lusher areas)
                color = HueRotate(color, (i.clump - 0.5) * 2 * _ClumpHueVar);
                color *= 1 + (frac(i.clump * 13.7) - 0.5) * 2 * _ClumpValueVar;
                half patch = smoothstep(0.4, 0.6, ValueNoise2(i.restXZ * _PatchScale + 31.7));
                color *= lerp(half3(1, 1, 1), _PatchTint.rgb, patch * _PatchAmount);
                color = lerp(color, _WindColor.rgb, WindColorMask(i.positionWS, i.height) * _WindColorAmount);
                color *= lerp(_ShadowTint.rgb, half3(1, 1, 1), lit);
                // bake = albedo x ground lit colour -> recover the albedo and apply the ground's own lit / shadow colour
                half3 groundLit = _DSEWA_GroundLight.w > 0 ? max(_DSEWA_GroundLitColor.rgb, 0.05) : half3(1, 1, 1);
                half3 rootColor = ground.rgb / groundLit * lerp(1, tex.rgb, _GroundBlendCardShade)
                                * lerp(_DSEWA_GroundShadowColor.rgb, groundLit, litRoot);
                color = lerp(color, rootColor, rootMask);
                color += _ShineColor.rgb * pow(saturate(i.height), _ShinePower) * _ShineStrength * lit;   // Grass Shine: lit tips

                // Sheen: Kajiya-Kay highlight along the blade (up, leaning out of the clump), cut into a hard toon band
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                float3 T = normalize(float3(0, 1, 0) + float3(i.volumeWS.x, 0, i.volumeWS.z) * _SheenLean);
                float TdotH = dot(T, normalize(light.direction + V));
                float sheen = pow(sqrt(saturate(1 - TdotH * TdotH)), _SheenPower) + (i.clump - 0.5) * 0.1;
                color += _SheenColor.rgb * smoothstep(_SheenThreshold, _SheenThreshold + 0.04, sheen) * _SheenStrength * lit * i.height;

                // Backlight: looking towards the sun, thin tips let the light through
                half back = smoothstep(_TransThreshold, _TransThreshold + 0.05, saturate(dot(-V, light.direction)));
                color += _TransColor.rgb * back * direct * smoothstep(0.3, 1, i.height) * _TransStrength;
                color = ApplyGroundFog(color, i.positionWS);
                // Bioluminescent tips: self-lit, after the fog so the far field still glows (HDR -> bloom)
                color += _TipGlowColor.rgb * smoothstep(_TipGlowStart, 1, i.height) * (0.75 + 0.5 * i.clump) * _TipGlow;
                return half4(MixFog(color, i.fogFactor), 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float4 color : COLOR; float2 uv : TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; float3 uv : TEXCOORD0; };

            Varyings vert(Attributes input)
            {
                UNITY_SETUP_INSTANCE_ID(input);
                Varyings o;
                float3 positionWS = FoliageBend(TransformObjectToWorld(input.positionOS.xyz), input.color);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
            #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDir = normalize(_LightPosition - positionWS);
            #else
                float3 lightDir = _LightDirection;
            #endif
                o.positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDir));
            #if UNITY_REVERSED_Z
                o.positionCS.z = min(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                o.positionCS.z = max(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                o.uv = float3(TRANSFORM_TEX(input.uv, _BaseMap), input.color.r);
                return o;
            }

            half4 frag(Varyings i) : SV_Target { ClipAlpha(i.uv); return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On ColorMask R

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            struct Attributes { float4 positionOS : POSITION; float4 color : COLOR; float2 uv : TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; float3 uv : TEXCOORD0; };

            Varyings vert(Attributes input)
            {
                UNITY_SETUP_INSTANCE_ID(input);
                Varyings o;
                o.positionCS = TransformWorldToHClip(FoliageBend(TransformObjectToWorld(input.positionOS.xyz), input.color));
                o.uv = float3(TRANSFORM_TEX(input.uv, _BaseMap), input.color.r);
                return o;
            }

            half frag(Varyings i) : SV_Target { ClipAlpha(i.uv); return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }
            ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float4 color : COLOR; float2 uv : TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; float3 uv : TEXCOORD0; float3 normalWS : TEXCOORD1; };

            Varyings vert(Attributes input)
            {
                UNITY_SETUP_INSTANCE_ID(input);
                Varyings o;
                o.positionCS = TransformWorldToHClip(FoliageBend(TransformObjectToWorld(input.positionOS.xyz), input.color));
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                o.uv = float3(TRANSFORM_TEX(input.uv, _BaseMap), input.color.r);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                ClipAlpha(i.uv);
                float3 n = normalize(i.normalWS);
            #if defined(_GBUFFER_NORMALS_OCT)
                return half4(PackFloat2To888(saturate(PackNormalOctQuadEncode(n) * 0.5 + 0.5)), 0);
            #else
                return half4(n, 0);
            #endif
            }
            ENDHLSL
        }
    }
}
