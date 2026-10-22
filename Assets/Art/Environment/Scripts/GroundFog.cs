using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// Ground-only distance fog for ToonTerrain / ToonFoliage (GroundFog.hlsl): the ground and grass melt into the sky's
/// horizon colour with distance, the sky and clouds stay clear. The colour is read from the skybox every frame
/// (horizon, mixed towards the haze band), so it follows the time-of-day slider. Disable to turn the fog off.
/// </summary>
[ExecuteAlways]
public class GroundFog : MonoBehaviour
{
    [Tooltip("Distance (m) where the fog starts")]
    public float start = 15f;
    [Tooltip("Distance (m) where the fog reaches Max Amount")]
    public float end = 260f;
    [Range(0f, 1f)] public float maxAmount = 0.85f;
    [Tooltip("Hill tops keep more colour: fog *= exp(-height above the camera x falloff)")]
    public float heightFalloff = 0.01f;
    [Tooltip("0 = sky horizon colour, 1 = horizon haze band colour")]
    [Range(0f, 1f)] public float bandMix = 0.5f;
    [Header("Night")]
    [Tooltip("Max Amount at night; blended by the night post volume's weight (DayNightBlend drives it)")]
    [Range(0f, 1f)] public float nightAmount = 0.25f;
    public Volume nightVolume;

    static readonly int FogId = Shader.PropertyToID("_DSEWA_GroundFog");
    static readonly int ColorId = Shader.PropertyToID("_DSEWA_GroundFogColor");
    static readonly int HorizonId = Shader.PropertyToID("_HorizonColor");
    static readonly int BandId = Shader.PropertyToID("_BandColor");

    void OnEnable() => RenderPipelineManager.beginContextRendering += OnBeginRendering;

    void OnDisable()
    {
        RenderPipelineManager.beginContextRendering -= OnBeginRendering;
        Shader.SetGlobalVector(ColorId, Vector4.zero);
    }

    void OnBeginRendering(ScriptableRenderContext ctx, System.Collections.Generic.List<Camera> cams) => Push();

    public void Push()
    {
        Color c = Color.gray;
        var sky = RenderSettings.skybox;
        if (sky != null && sky.HasProperty(HorizonId))
            c = sky.HasProperty(BandId) ? Color.Lerp(sky.GetColor(HorizonId), sky.GetColor(BandId), bandMix) : sky.GetColor(HorizonId);
        float amount = nightVolume != null ? Mathf.Lerp(maxAmount, nightAmount, nightVolume.weight) : maxAmount;
        Shader.SetGlobalVector(FogId, new Vector4(start, end, amount, heightFalloff));
        Shader.SetGlobalVector(ColorId, new Vector4(c.r, c.g, c.b, 1f));
    }
}
