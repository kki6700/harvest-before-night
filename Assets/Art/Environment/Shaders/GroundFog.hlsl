#ifndef DSEWA_GROUND_FOG_INCLUDED
#define DSEWA_GROUND_FOG_INCLUDED

// Ground-only distance fog (GroundFog component): the terrain and grass melt into the sky's horizon colour with
// distance, while the sky / clouds stay untouched (Unity's global fog would also wash out the far cloud cards).
float4 _DSEWA_GroundFog;        // start (m), end (m), max amount, height falloff (1/m above the camera)
float4 _DSEWA_GroundFogColor;   // rgb, a = 1 when set

half3 ApplyGroundFog(half3 color, float3 positionWS)
{
    if (_DSEWA_GroundFogColor.a < 0.5) return color;
    float d = distance(positionWS, _WorldSpaceCameraPos);
    float f = saturate((d - _DSEWA_GroundFog.x) / max(_DSEWA_GroundFog.y - _DSEWA_GroundFog.x, 1e-3));
    f = f * f * (3 - 2 * f);
    // high ground (hill tops) keeps a little more of its own colour
    f *= exp(-max(positionWS.y - _WorldSpaceCameraPos.y, 0) * _DSEWA_GroundFog.w);
    return lerp(color, _DSEWA_GroundFogColor.rgb, f * _DSEWA_GroundFog.z);
}

#endif
