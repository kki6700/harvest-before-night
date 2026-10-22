// Normal-mapped billboard cloud cards (SG_CloudCard custom functions).
//
// CloudBillboard: turns the card about the world Y axis through its pivot so its face points at the camera
//   (cylindrical billboard: the cloud never tips over). The card's own facing is its vertex normal, so the cards keep
//   whatever plane they were modelled in. Amount 0 = authored orientation, 1 = full billboard.
// CloudNormalShade: lights the painted colour with the baked card normal (T_CloudCard_Normal: R right, G up, B toward
//   the viewer) against the main light - one soft toon step between Shadow Tint and full colour, plus a silver rim
//   when the sun is behind the cloud; Amount 0 = the old unlit look. The basis is rebuilt from the camera -> pivot direction, matching the billboard.
// All defaults are my own starting values (no reference values).

#ifndef DSEWA_CLOUD_BILLBOARD_INCLUDED
#define DSEWA_CLOUD_BILLBOARD_INCLUDED

float3 CloudPivotWS()
{
    return float3(UNITY_MATRIX_M._m03, UNITY_MATRIX_M._m13, UNITY_MATRIX_M._m23);
}

// horizontal direction from the pivot to the camera (falls back to +Z right above / below the card)
float3 CloudFacingWS(float3 pivotWS)
{
    float3 d = _WorldSpaceCameraPos - pivotWS;
    d.y = 0;
    float l = length(d);
    return l > 1e-4 ? d / l : float3(0, 0, 1);
}

void CloudBillboard_float(float3 PositionOS, float3 NormalOS, float Amount, out float3 Out)
{
    float3 pivot = CloudPivotWS();
    float3 offset = TransformObjectToWorld(PositionOS) - pivot;
    float3 n = TransformObjectToWorldDir(NormalOS);
    n.y = 0;
    float nl = length(n);
    float3 face = CloudFacingWS(pivot);
    if (nl > 1e-4)
    {
        n /= nl;
        // signed yaw from the card's facing to the camera direction, scaled by Amount
        float ang = atan2(n.z * face.x - n.x * face.z, dot(n, face)) * Amount;
        float c = cos(ang), s = sin(ang);
        offset = float3(c * offset.x + s * offset.z, offset.y, -s * offset.x + c * offset.z);
    }
    Out = TransformWorldToObject(pivot + offset);
}

void CloudNormalShade_float(float3 Color, float4 NormalSample, float Strength, float Softness, float Wrap,
                            float3 ShadowTint, float3 RimColor, float RimAmount, float Amount, out float3 Out, out float Lit)
{
    float3 pivot = CloudPivotWS();
    float3 face = CloudFacingWS(pivot);              // toward the viewer
    float3 up = float3(0, 1, 0);
    float3 right = cross(face, up);                  // screen right when looking at the card (left-handed)
    float3 nt = NormalSample.xyz * 2 - 1;
    nt.xy *= Strength;
    float3 N = normalize(right * nt.x + up * nt.y + face * max(nt.z, 1e-3));

#if defined(SHADERGRAPH_PREVIEW)
    float3 L = normalize(float3(-0.5, 0.6, 0.6));
    float3 lightCol = 1;
#else
    Light mainLight = GetMainLight();
    float3 L = mainLight.direction;
    // light colour normalised to its brightest channel: the rim takes the sun / moon hue, not its intensity
    float3 lightCol = mainLight.color / max(max(mainLight.color.r, mainLight.color.g), max(mainLight.color.b, 1e-3));
#endif
    float ndl = dot(N, L) + Wrap;
    float w = max(Softness, 1e-3);
    Lit = smoothstep(-w, w, ndl);
    float3 col = lerp(Color * ShadowTint, Color, Lit);
    // silver lining: sun behind the card, strongest where the normal turns away from the viewer (the rim)
    float back = saturate(-dot(L, face));
    float edge = pow(saturate(1 - dot(N, face)), 4);
    Out = lerp(Color, col + RimColor * lightCol * (edge * back * RimAmount), Amount);
}

#endif
