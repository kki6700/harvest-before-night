using UnityEngine;

/// <summary>
/// Publishes the cloud-shadow globals read by CloudShadow.hlsl (port of SurvivalKit's MI_CloudShadow light
/// function). Defaults are the research values; UE tiling is in cm, so 830.007629 / 1675.230957 -> metres.
/// Disabling the component turns the cloud shadow off.
/// </summary>
[ExecuteAlways]
public class CloudShadowSettings : MonoBehaviour
{
    [Tooltip("Noise size A in metres (UE tiling 830.007629 cm)")]
    public float tilingA = 8.30007629f;
    [Tooltip("Noise size B in metres (UE tiling 1675.230957 cm)")]
    public float tilingB = 16.75230957f;
    [Tooltip("Pan speed in noise UV per second (UE Speed)")]
    public float speed = -0.005f;
    [Tooltip("SmoothStep min / max (UE Levels Min / Max)")]
    public Vector2 levels = new Vector2(0.292f, 0.762758f);
    [Tooltip("Lerp(1, mask, opacity); > 1 extrapolates (UE Opacity)")]
    public float opacity = 1.675799f;

    [Header("My controls (not in the research): with the stand-in noise the research values shade ~half the ground")]
    [Tooltip("Added to the noise before the SmoothStep: + = fewer, smaller shadows. 0 = research as-is")]
    [Range(-0.5f, 0.5f)] public float coverageOffset = 0.25f;
    [Tooltip("How dark the shadows get: 0 = none, 1 = research result")]
    [Range(0f, 1f)] public float strength = 0.7f;

    static readonly int TilingId = Shader.PropertyToID("_DSEWA_CloudShadowTiling");
    static readonly int LevelsId = Shader.PropertyToID("_DSEWA_CloudShadowLevels");
    static readonly int TweakId = Shader.PropertyToID("_DSEWA_CloudShadowTweak");

    void OnEnable() => Apply();
    void OnValidate() => Apply();
    void OnDisable() => Shader.SetGlobalVector(TilingId, Vector4.zero);

    void Apply()
    {
        if (!isActiveAndEnabled) return;
        Shader.SetGlobalVector(TilingId, new Vector4(Mathf.Max(tilingA, 1e-3f), Mathf.Max(tilingB, 1e-3f), speed, opacity));
        Shader.SetGlobalVector(LevelsId, new Vector4(levels.x, levels.y, 0f, 0f));
        Shader.SetGlobalVector(TweakId, new Vector4(coverageOffset, Mathf.Max(strength, 1e-4f), 0f, 0f));
    }
}
