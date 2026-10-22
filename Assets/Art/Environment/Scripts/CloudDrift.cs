using UnityEngine;
#if UNITY_EDITOR
using UnityEditor;
using UnityEditor.SceneManagement;
#endif

/// <summary>
/// Moves the cloud cards: the whole ring slowly turns around this object's Y axis (clouds cross the sky without
/// ever leaving it, cards keep facing the centre) and every card "breathes" on its own beat (scale, height, a little
/// sway) so the clouds look alive. Put it on CloudCards (cards are its children, centre ~ camera).
/// The turn direction follows the cloud shadows (CloudShadowSettings pan) for the part of the sky the main camera
/// looks at. Edit-mode preview restores the authored layout before the scene is saved, before a script reload and
/// before Play mode (Unity serialises the scene before OnDisable runs there, so the drifted pose would otherwise become
/// the new "authored" layout and the cards would creep a little further every reload).
/// </summary>
[ExecuteAlways]
public class CloudDrift : MonoBehaviour
{
    [Header("Drift (whole ring turns)")]
    [Tooltip("Cloud speed in m/s at the cards' distance; turned into degrees per second (speed / radius)")]
    public float windSpeed = 8f;
    [Tooltip("Follow CloudShadowSettings so the clouds in front of the main camera drift the same way as the shadows")]
    public bool matchCloudShadows = true;
    [Tooltip("Used when not matching the shadows: +1 = counter-clockwise seen from above, -1 = clockwise")]
    public float direction = 1f;

    [Header("Breathing (each card)")]
    [Tooltip("Scale change, fraction of the card size")]
    [Range(0f, 0.2f)] public float scaleAmount = 0.05f;
    [Tooltip("Up / down bob in metres")]
    public float bobHeight = 4f;
    [Tooltip("Yaw sway in degrees")]
    public float swayDegrees = 1.5f;
    [Tooltip("Seconds per breath, random per card between x and y")]
    public Vector2 breathPeriod = new Vector2(40f, 90f);

    [Header("Editor")]
    public bool previewInEditMode = true;

    Quaternion baseRotation;
    Transform[] cards;
    Vector3[] basePos, baseScale;
    Quaternion[] baseRot;
    float[] phase, period;
    float radius = 900f;
    bool cached;
    double startTime;   // drift starts from the authored layout when the component is enabled

    void OnEnable()
    {
        Cache();
#if UNITY_EDITOR
        EditorApplication.update += EditorTick;
        EditorSceneManager.sceneSaving += OnSceneSaving;
        EditorSceneManager.sceneSaved += OnSceneSaved;
        AssemblyReloadEvents.beforeAssemblyReload += Restore;
        EditorApplication.playModeStateChanged += OnPlayModeChanged;
#endif
    }

    void OnDisable()
    {
#if UNITY_EDITOR
        EditorApplication.update -= EditorTick;
        EditorSceneManager.sceneSaving -= OnSceneSaving;
        EditorSceneManager.sceneSaved -= OnSceneSaved;
        AssemblyReloadEvents.beforeAssemblyReload -= Restore;
        EditorApplication.playModeStateChanged -= OnPlayModeChanged;
#endif
        Restore();
    }

    void Cache()
    {
        baseRotation = transform.localRotation;
        int n = transform.childCount;
        cards = new Transform[n]; basePos = new Vector3[n]; baseScale = new Vector3[n]; baseRot = new Quaternion[n];
        phase = new float[n]; period = new float[n];
        var rnd = new System.Random(1234);
        float sum = 0f;
        for (int i = 0; i < n; i++)
        {
            var c = transform.GetChild(i);
            cards[i] = c; basePos[i] = c.localPosition; baseScale[i] = c.localScale; baseRot[i] = c.localRotation;
            phase[i] = (float)rnd.NextDouble() * Mathf.PI * 2f;
            period[i] = Mathf.Lerp(breathPeriod.x, breathPeriod.y, (float)rnd.NextDouble());
            sum += new Vector2(c.localPosition.x, c.localPosition.z).magnitude;
        }
        if (n > 0) radius = Mathf.Max(sum / n, 1f);
        startTime = Now();
        cached = true;
    }

    void Restore()
    {
        if (!cached) return;
        transform.localRotation = baseRotation;
        for (int i = 0; i < cards.Length; i++)
        {
            if (cards[i] == null) continue;
            cards[i].localPosition = basePos[i]; cards[i].localScale = baseScale[i]; cards[i].localRotation = baseRot[i];
        }
    }

    float TurnSign()
    {
        if (!matchCloudShadows) return Mathf.Sign(direction == 0 ? 1 : direction);
        var shadow = FindAnyObjectByType<CloudShadowSettings>();
        var cam = Camera.main;
        if (shadow == null || cam == null) return Mathf.Sign(direction == 0 ? 1 : direction);
        // CloudShadow.hlsl adds time * speed to both noise axes, so the shadows travel along -sign(speed) * (1, 1)
        Vector2 wind = new Vector2(1f, 1f).normalized * -Mathf.Sign(shadow.speed);
        Vector3 f = cam.transform.forward; Vector2 p = new Vector2(f.x, f.z);
        if (p.sqrMagnitude < 1e-4f) return 1f;
        p.Normalize();
        // a positive turn about +Y moves a point (x, z) along (z, -x); Unity's positive Y rotation is clockwise from above
        Vector2 tangent = new Vector2(p.y, -p.x);
        return Vector2.Dot(tangent, wind) >= 0f ? 1f : -1f;
    }

    void Apply(float time)
    {
        if (!cached || cards == null) return;
        float degPerSec = windSpeed / radius * Mathf.Rad2Deg * TurnSign();
        transform.localRotation = baseRotation * Quaternion.Euler(0f, time * degPerSec, 0f);
        for (int i = 0; i < cards.Length; i++)
        {
            var c = cards[i]; if (c == null) continue;
            float a = time * Mathf.PI * 2f / period[i] + phase[i];
            float s = Mathf.Sin(a), s2 = Mathf.Sin(a * 0.73f + 1.7f);
            c.localScale = baseScale[i] * (1f + scaleAmount * s);
            c.localPosition = basePos[i] + Vector3.up * (bobHeight * s2);
            c.localRotation = baseRot[i] * Quaternion.Euler(0f, swayDegrees * s2, 0f);
        }
    }

    static double Now()
    {
#if UNITY_EDITOR
        if (!Application.isPlaying) return EditorApplication.timeSinceStartup;
#endif
        return Time.timeAsDouble;
    }

    void Update()
    {
        if (Application.isPlaying) Apply((float)(Now() - startTime));
    }

#if UNITY_EDITOR
    void EditorTick()
    {
        if (Application.isPlaying || this == null) return;
        if (!previewInEditMode) { Restore(); return; }
        Apply((float)(Now() - startTime));
        SceneView.RepaintAll();
    }

    void OnSceneSaving(UnityEngine.SceneManagement.Scene scene, string path) { if (scene == gameObject.scene) Restore(); }
    void OnSceneSaved(UnityEngine.SceneManagement.Scene scene) { }

    void OnPlayModeChanged(PlayModeStateChange change) { if (change == PlayModeStateChange.ExitingEditMode) Restore(); }

    // restore first so the new cache starts from the authored layout, not a drifted pose
    void OnValidate() { if (cached && cards != null && cards.Length != transform.childCount) { Restore(); Cache(); } }
#endif
}
