using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// Toon lens flare for the sky light (sun by day, moon by night - DayNightBlend drives one directional light).
///
/// Why not a LensFlareComponentSRP on the directional light itself: for directional lights URP tests occlusion
/// against a point on the far plane, and our 3D moon (MoonModel) is real geometry drawn at ~92 % of the far plane
/// that writes depth, so the moon always hid its own flare. occlusionOffset cannot pull the test point forward
/// either: for directional lights it is pushed along (camera - light GameObject position), i.e. an arbitrary
/// direction that changes with the camera.
///
/// So this component spawns a hidden, unsaved flare object and, right before every camera renders, places it
/// `distance` (fraction of the far plane) along the light direction from that camera - just in front of the moon.
/// URP then treats it as a local flare: the occlusion test sits at that point, so terrain, characters, props and
/// clouds in front of the moon occlude it, the moon behind it does not. Colour still comes from the light
/// (lightOverride). Strength blends day/night with the night volume weight and fades near the horizon.
/// Strengths / sizes are my own starting values.
/// </summary>
[ExecuteAlways]
[RequireComponent(typeof(Light))]
public class ToonLensFlareFade : MonoBehaviour
{
    public LensFlareDataSRP flareData;
    public Volume nightVolume;
    [Range(0f, 3f)] public float dayIntensity = 0.6f;
    [Range(0f, 3f)] public float nightIntensity = 2f;
    [Range(0.1f, 10f)] public float scale = 4f;
    [Tooltip("Light elevation (degrees) where the flare starts / is fully on")]
    public Vector2 horizonFade = new Vector2(2f, 12f);
    [Tooltip("Where the flare (and its occlusion test) sits, as a fraction of the camera far plane. Keep it in front of the moon model (MoonModel draws at 0.92 x far minus its radius).")]
    [Range(0.1f, 0.95f)] public float distance = 0.8f;
    [Tooltip("Occlusion test radius in metres at that distance")]
    public float occlusionRadius = 25f;
    public bool useOcclusion = true;

    Light skyLight;
    GameObject flareGO;
    LensFlareComponentSRP flare;

    void OnEnable()
    {
        skyLight = GetComponent<Light>();
        // an old setup may have the component on the light itself: it would draw a second, wrongly occluded flare
        var onLight = GetComponent<LensFlareComponentSRP>();
        if (onLight) onLight.enabled = false;

        flareGO = new GameObject("ToonSkyFlare (runtime)") { hideFlags = HideFlags.HideAndDontSave };
        flare = flareGO.AddComponent<LensFlareComponentSRP>();
        flare.lightOverride = skyLight;
        flare.allowOffScreen = false;
        flare.attenuationByLightShape = false;
        // the flare sits ~2 km away: switch off distance attenuation / scaling
        flare.maxAttenuationDistance = 1e6f;
        flare.maxAttenuationScale = 1e6f;
        flare.distanceAttenuationCurve = AnimationCurve.Constant(0f, 1f, 1f);
        flare.scaleByDistanceCurve = AnimationCurve.Constant(0f, 1f, 1f);
        flare.occlusionOffset = 0f;
        flare.sampleCount = 16;
        Apply();
        RenderPipelineManager.beginCameraRendering += OnBeginCamera;
    }

    void OnDisable()
    {
        RenderPipelineManager.beginCameraRendering -= OnBeginCamera;
        if (flareGO) DestroyImmediate(flareGO);
        flareGO = null; flare = null;
    }

    void LateUpdate() => Apply();

    void Apply()
    {
        if (!flare) return;
        flare.lensFlareData = flareData;
        flare.scale = scale;
        flare.useOcclusion = useOcclusion;
        flare.occlusionRadius = occlusionRadius;
        float night = nightVolume ? nightVolume.weight : 0f;
        float elevation = Mathf.Asin(Mathf.Clamp(-transform.forward.y, -1f, 1f)) * Mathf.Rad2Deg;
        float horizon = Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(horizonFade.x, horizonFade.y, elevation));
        flare.intensity = Mathf.Lerp(dayIntensity, nightIntensity, night) * horizon;
    }

    void OnBeginCamera(ScriptableRenderContext ctx, Camera cam)
    {
        if (!flareGO) return;
        flareGO.transform.position = cam.transform.position - transform.forward * (cam.farClipPlane * distance);
    }
}
