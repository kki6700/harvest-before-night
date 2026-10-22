using UnityEngine;
#if UNITY_EDITOR
using UnityEditor;
#endif

/// <summary>
/// Lets the unlit cloud cards (SG_CloudCard) take the sun: every card gets its own shade colours (the graph's gradient
/// map: painting luminance -> Shade Shadow .. Shade Lit), Tint and Brightness through a MaterialPropertyBlock,
/// from where it sits relative to the sun as seen from the camera.
/// Clouds towards the sun get warm sunset colours (a little brighter when almost in front of the sun),
/// clouds on the far side get cool sky-lit colours, and the tint follows the main light's colour.
/// Cards only show in an arc around the sun (they fade out by azimuth while CloudDrift turns the ring); the arc is read
/// from the skybox's _VolSunSideFade so the volumetric clouds take over exactly where the cards fade.
/// The Shader Graph is untouched; disable the component to get the material values back.
/// It also publishes its colours as globals (_DSEWA_Cloud*) for the mesh clouds (DSEWA/ToonCloudMesh), which pick
/// the sun-side / far-side colour per pixel.
/// Put it on CloudCards next to CloudDrift.
/// </summary>
[ExecuteAlways]
public class CloudSunLight : MonoBehaviour
{
    [Tooltip("Defaults to the first directional light")]
    public Light sun;

    [Header("Shade colours by side of the sky (gradient map)")]
    [Tooltip("Lit part of clouds towards the sun")]
    public Color sunSideLit = new Color(1f, 0.83f, 0.63f);
    [Tooltip("Shadowed part of clouds towards the sun")]
    public Color sunSideShadow = new Color(0.78f, 0.50f, 0.66f);
    [Tooltip("Lit part of clouds on the far side (sky light only)")]
    public Color farSideLit = new Color(0.96f, 0.87f, 0.94f);
    [Tooltip("Shadowed part of clouds on the far side")]
    public Color farSideShadow = new Color(0.56f, 0.46f, 0.76f);
    [Tooltip("How fast the warm side gives way to the cool side (higher = warm only right around the sun)")]
    [Range(0.5f, 8f)] public float sideFalloff = 2f;

    [Header("Brightness")]
    public float sunSideBrightness = 1.2f;
    public float farSideBrightness = 1.05f;
    [Tooltip("Extra brightness for cards almost in front of the sun (backlit). Keep small: it also lifts the card's faint edges")]
    public float backlitBoost = 0.12f;
    [Tooltip("Angle in degrees within which the backlit boost applies")]
    [Range(1f, 60f)] public float backlitAngle = 25f;

    [Header("Sun-side arc (cards hand the sky over to the volumetric clouds outside it)")]
    [Tooltip("Read arc + feather from the skybox's _VolSunSideFade (z, w) when it has it")]
    public bool arcFromSkybox = true;
    [Tooltip("Half-width in degrees of the arc where cards are fully visible")]
    [Range(0f, 180f)] public float sunArc = 60f;
    [Tooltip("Degrees over which cards fade out past the arc")]
    [Range(1f, 90f)] public float sunArcFeather = 30f;

    [Header("Main light")]
    [Tooltip("0 = ignore the light's colour, 1 = multiply the tint by it fully")]
    [Range(0f, 1f)] public float lightColorInfluence = 0.3f;
    [Tooltip("Scale brightness with the light intensity (relative to this intensity)")]
    public float referenceIntensity = 1.7f;

    static readonly int TintId = Shader.PropertyToID("_Tint");
    static readonly int BrightnessId = Shader.PropertyToID("_Brightness");
    static readonly int ShadeLitId = Shader.PropertyToID("_ShadeLitColor");
    static readonly int ShadeShadowId = Shader.PropertyToID("_ShadeShadowColor");
    static readonly int OpacityId = Shader.PropertyToID("_Opacity");
    static readonly int SunSideFadeId = Shader.PropertyToID("_VolSunSideFade");
    // globals for the mesh clouds (DSEWA/ToonCloudMesh), which pick the side colour per pixel
    static readonly int GSunLitId = Shader.PropertyToID("_DSEWA_CloudSunLit");
    static readonly int GSunShadowId = Shader.PropertyToID("_DSEWA_CloudSunShadow");
    static readonly int GFarLitId = Shader.PropertyToID("_DSEWA_CloudFarLit");
    static readonly int GFarShadowId = Shader.PropertyToID("_DSEWA_CloudFarShadow");
    static readonly int GTintId = Shader.PropertyToID("_DSEWA_CloudTint");
    static readonly int GParamsId = Shader.PropertyToID("_DSEWA_CloudParams");
    static readonly int GHazeId = Shader.PropertyToID("_DSEWA_CloudHaze");
    static readonly int HorizonId = Shader.PropertyToID("_HorizonColor");
    MaterialPropertyBlock mpb;
    Renderer[] renderers;

    void OnEnable()
    {
        renderers = GetComponentsInChildren<Renderer>(true);
#if UNITY_EDITOR
        EditorApplication.update += EditorTick;
#endif
    }

    void OnDisable()
    {
#if UNITY_EDITOR
        EditorApplication.update -= EditorTick;
#endif
        Shader.SetGlobalVector(GParamsId, Vector4.zero);   // mesh clouds fall back to their material colours
        if (renderers == null) return;
        foreach (var r in renderers) if (r != null) { r.SetPropertyBlock(null); r.enabled = true; }
    }

    Light FindSun()
    {
        if (sun != null) return sun;
        if (RenderSettings.sun != null) return RenderSettings.sun;
        foreach (var l in FindObjectsByType<Light>(FindObjectsSortMode.None))
            if (l.type == LightType.Directional) return l;
        return null;
    }

    void Apply()
    {
        var light = FindSun();
        var cam = Camera.main;
        if (light == null || renderers == null) return;
        if (mpb == null) mpb = new MaterialPropertyBlock();
        Vector3 eye = cam != null ? cam.transform.position : transform.position;
        Vector3 toSun = -light.transform.forward;
        Vector2 sunFlat = new Vector2(toSun.x, toSun.z).normalized;
        Color lightTint = Color.Lerp(Color.white, light.color, lightColorInfluence);
        float intensity = referenceIntensity > 0f ? light.intensity / referenceIntensity : 1f;
        float cosBack = Mathf.Cos(backlitAngle * Mathf.Deg2Rad);
        float arc = sunArc, feather = sunArcFeather;
        var sky = RenderSettings.skybox;
        if (arcFromSkybox && sky != null && sky.HasProperty(SunSideFadeId))
        {
            Vector4 v = sky.GetVector(SunSideFadeId);
            arc = v.z; feather = Mathf.Max(v.w, 1f);
        }

        Shader.SetGlobalVector(GSunLitId, new Vector4(sunSideLit.r, sunSideLit.g, sunSideLit.b, sunSideBrightness));
        Shader.SetGlobalVector(GSunShadowId, (Vector4)sunSideShadow);
        Shader.SetGlobalVector(GFarLitId, new Vector4(farSideLit.r, farSideLit.g, farSideLit.b, farSideBrightness));
        Shader.SetGlobalVector(GFarShadowId, (Vector4)farSideShadow);
        Shader.SetGlobalVector(GTintId, new Vector4(lightTint.r, lightTint.g, lightTint.b, intensity));
        Shader.SetGlobalVector(GParamsId, new Vector4(sideFalloff, 1f, 0f, 0f));
        if (sky != null && sky.HasProperty(HorizonId))
        {
            Color h = sky.GetColor(HorizonId);
            Shader.SetGlobalVector(GHazeId, new Vector4(h.r, h.g, h.b, 1f));
        }

        foreach (var r in renderers)
        {
            if (r == null) continue;
            Vector3 dir = (r.bounds.center - eye).normalized;
            Vector2 flat = new Vector2(dir.x, dir.z).normalized;
            // 1 = same azimuth as the sun, 0 = opposite side of the sky
            float side = Mathf.Pow(Mathf.Clamp01(Vector2.Dot(flat, sunFlat) * 0.5f + 0.5f), sideFalloff);
            Color lit = Color.Lerp(farSideLit, sunSideLit, side);
            Color shadow = Color.Lerp(farSideShadow, sunSideShadow, side);
            float bright = Mathf.Lerp(farSideBrightness, sunSideBrightness, side);
            float azimuth = Vector2.Angle(flat, sunFlat);
            float show = 1f - Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(arc, arc + feather, azimuth));
            float baseOpacity = r.sharedMaterial != null && r.sharedMaterial.HasProperty(OpacityId) ? r.sharedMaterial.GetFloat(OpacityId) : 1f;
            float back = Mathf.InverseLerp(cosBack, 1f, Vector3.Dot(dir, toSun));
            bright = (bright + backlitBoost * back * back) * intensity;

            r.GetPropertyBlock(mpb);
            mpb.SetColor(ShadeLitId, lit);
            mpb.SetColor(ShadeShadowId, shadow);
            mpb.SetColor(TintId, lightTint);
            mpb.SetFloat(BrightnessId, bright);
            mpb.SetFloat(OpacityId, baseOpacity * show);
            r.SetPropertyBlock(mpb);
            bool visible = show > 0.001f;   // skip the overdraw of cards that are fully faded
            if (r.enabled != visible) r.enabled = visible;
        }
    }

    void LateUpdate()
    {
        if (Application.isPlaying) Apply();
    }

#if UNITY_EDITOR
    void EditorTick()
    {
        if (Application.isPlaying || this == null) return;
        Apply();
    }

    void OnValidate() { renderers = GetComponentsInChildren<Renderer>(true); }
#endif
}
