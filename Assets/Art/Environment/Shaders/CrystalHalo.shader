// DSEWA/CrystalHalo: soft aura of the crystal's own colour, so the light seems to hang in the air around it.
// Added to a crystal's MeshRenderer as an EXTRA material slot (Unity draws the last submesh again with it), queue
// Transparent so it is drawn after the sky; additive, no depth write.
// Same trick as the lantern fruit halo after its 10/19 fix: the shell is grown out from the renderer's centre, not along
// the vertex normals (faceted meshes have split normals; a normal-grown shell tears open at every edge).
// Breathes on the same beat as DSEWA/ToonCrystal (same _PulsePeriod / _PulseCell / hash) and fades with the ground fog.
// All defaults are my own starting values.
Shader "DSEWA/CrystalHalo"
{
    Properties
    {
        [HDR] _HaloColor ("Halo Color", Color) = (0.5, 0.4, 1.6, 1)
        _HaloStrength ("Halo Strength", Range(0, 3)) = 0.6
        _HaloSize ("Shell Grow (fraction of the crystal's size)", Range(0, 0.6)) = 0.18
        _HaloPower ("Softness (higher = tighter to the body)", Range(0.5, 8)) = 2.2
        _PulsePeriod ("Pulse Period (s), same as the crystal", Range(0.2, 20)) = 10
        _PulseCell ("Beat Shared Within (m), same as the crystal", Float) = 5
        _PulseRange ("Pulse Min / Max", Vector) = (0.6, 1.2, 0, 0)
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True" }

        Pass
        {
            Name "Halo"
            Tags { "LightMode" = "UniversalForward" }
            Blend One One
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets/Art/Environment/Shaders/GroundFog.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _HaloColor;
                half _HaloStrength, _HaloSize, _HaloPower;
                float _PulsePeriod, _PulseCell;
                float4 _PulseRange;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 radialWS : TEXCOORD1;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                float3 pWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 centre = (unity_RendererBounds_Min.xyz + unity_RendererBounds_Max.xyz) * 0.5;
                float3 extent = unity_RendererBounds_Max.xyz - unity_RendererBounds_Min.xyz;
                float size = max(extent.x, max(extent.y, extent.z));
                float3 radial = normalize(pWS - centre + 1e-5);
                pWS += radial * _HaloSize * size;
                o.positionWS = pWS;
                o.radialWS = radial;
                o.positionCS = TransformWorldToHClip(pWS);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                half facing = saturate(dot(normalize(i.radialWS), V));
                half a = pow(facing, _HaloPower);

                float3 objPos = GetObjectToWorldMatrix()._m03_m13_m23;
                float3 key = _PulseCell > 0.01 ? float3(floor(objPos.xz / _PulseCell), 0).xzy : objPos;
                float cycle = frac(_Time.y / max(_PulsePeriod, 0.01) + frac(sin(dot(key, float3(12.9898, 78.233, 37.719))) * 43758.5453));
                float pulse = lerp(_PulseRange.x, _PulseRange.y, 0.5 + 0.5 * sin(cycle * TWO_PI));

                half fogAmount = 0;
                if (_DSEWA_GroundFogColor.a > 0.5)
                {
                    float d = distance(i.positionWS, _WorldSpaceCameraPos);
                    float f = saturate((d - _DSEWA_GroundFog.x) / max(_DSEWA_GroundFog.y - _DSEWA_GroundFog.x, 1e-3));
                    fogAmount = f * f * (3 - 2 * f) * _DSEWA_GroundFog.z;
                }
                return half4(_HaloColor.rgb * a * _HaloStrength * pulse * (1.0 - fogAmount), 0);
            }
            ENDHLSL
        }
    }
}
