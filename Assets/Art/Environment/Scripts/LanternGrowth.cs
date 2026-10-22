using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Growth of the lantern fruit plant from one value: <see cref="growth"/> 0 = nothing above ground, 1 = fully grown and lit.
/// Works on the plant's own rig (LanternFruit.fbx): every bone grows from nothing to its rest size in the order the
/// sap reaches it (distance from the root along the bones), so the stem rises segment by segment and the side
/// branches sprout where they meet it. Leaves and fruit ride on their bones (they are bone children in the FBX);
/// leaves then unfold, the lanterns swell on their stalks and finally light up.
/// Timing (fractions of the growth value) and the leaf unfold angle are my own starting values.
/// </summary>
[ExecuteAlways]
public class LanternGrowth : MonoBehaviour
{
    public enum Control { Continuous, Stages }

    [Tooltip("Continuous: drive 'growth' directly. Stages: pick a stage and the plant grows (or shrinks) to it over Stage Transition seconds.")]
    public Control control = Control.Continuous;
    [Range(0f, 1f)] public float growth = 1f;

    [Header("Stages")]
    [Tooltip("Current stage (index into Stage Values).")]
    [Min(0)] public int stage = 4;
    [Tooltip("Growth value of each stage: sprout, stem, branches + leaves, fruit, lit (harvest ready).")]
    public float[] stageValues = { 0.08f, 0.32f, 0.74f, 0.94f, 1f };
    [Tooltip("Names shown in the debug readout, same order as Stage Values.")]
    public string[] stageNames = { "싹", "줄기", "가지·잎", "열매", "점등" };
    [Tooltip("Seconds to grow from one stage to the next (Play mode; in the editor the change is instant).")]
    [Min(0f)] public float stageTransition = 1.5f;

    /// <summary>Grow (or shrink) to a stage. instant = jump without the transition.</summary>
    public void SetStage(int index, bool instant = false)
    {
        control = Control.Stages;
        stage = Mathf.Clamp(index, 0, Mathf.Max(stageValues.Length - 1, 0));
        if (instant || !Application.isPlaying) { growth = StageTarget(); _applied = -1f; }
    }

    /// <summary>Next stage (wraps to the first after the last, like a harvest).</summary>
    public void NextStage() => SetStage(stageValues.Length == 0 ? 0 : (stage + 1) % stageValues.Length);

    public string StageName => stage >= 0 && stage < stageNames.Length ? stageNames[stage] : stage.ToString();

    float StageTarget() => stageValues.Length == 0 ? growth : stageValues[Mathf.Clamp(stage, 0, stageValues.Length - 1)];

    [Header("Timing (fractions of growth)")]
    [Tooltip("Growth value by which the farthest bone tip has reached full size.")]
    [Range(0.2f, 1f)] public float branchesDone = 0.6f;
    [Tooltip("How long one leaf takes to unfold once its bone is grown.")]
    [Range(0.02f, 0.5f)] public float leafTime = 0.12f;
    [Tooltip("Fruit start / end: lanterns swell on their stalks in this window.")]
    public Vector2 fruitWindow = new Vector2(0.76f, 0.94f);
    [Tooltip("Glow start / end: the lanterns light up in this window.")]
    public Vector2 glowWindow = new Vector2(0.94f, 1f);
    [Tooltip("Leaves open from this angle (degrees, folded up against the bone).")]
    public float leafFold = 70f;

    [Header("Preview (Play mode only)")]
    [Tooltip("In Play mode, grow by itself (Continuous: 0 to 1; Stages: one stage every Preview Stage Interval). The game drives growth instead.")]
    public bool playOnStart = false;
    [Tooltip("Stages preview: seconds between stages.")]
    public float previewStageInterval = 2.5f;
    [Tooltip("Seconds from seed to fully lit.")]
    public float previewDuration = 8f;
    [Tooltip("Seconds to stay fully grown before starting again (0 = play once).")]
    public float previewHold = 3f;
    float _previewStart;

    // rest pose, recorded once from the untouched plant so a scene saved half-grown never becomes the new "full size"
    [SerializeField, HideInInspector] List<Transform> _restT = new List<Transform>();
    [SerializeField, HideInInspector] List<Vector3> _restS = new List<Vector3>();
    [SerializeField, HideInInspector] List<Quaternion> _restR = new List<Quaternion>();

    struct Part { public Transform t; public Vector3 restScale; public Quaternion restRot; public float t0, t1; }
    readonly List<Part> _bones = new List<Part>(), _leaves = new List<Part>(), _fruit = new List<Part>();
    readonly List<Renderer> _fruitRenderers = new List<Renderer>();
    readonly List<Material[]> _fruitMats = new List<Material[]>();
    MaterialPropertyBlock _mpb;
    float _applied = -1f;
    bool _ready;

    static readonly string[] ShellGlowProps = { "_GlowStrength", "_GlowWide", "_HaloStrength" };

    void OnEnable() { Build(); _applied = -1f; Apply(); }

    void OnDisable()
    {
        // back to the rest pose so the prefab / scene is never saved half-grown
        float g = growth; growth = 1f; Apply(); growth = g; _applied = -1f;
    }

    void OnValidate()
    {
        _applied = -1f;
        if (control == Control.Stages && !Application.isPlaying) growth = StageTarget();   // editor: show the stage at once
    }

    [ContextMenu("Recapture Rest Pose (plant must be fully grown)")]
    void RecaptureRest() { _restT.Clear(); _restS.Clear(); _restR.Clear(); Build(); _applied = -1f; Apply(); }

    void CaptureRest(IEnumerable<Transform> parts)
    {
        if (_restT.Count > 0) return;
        foreach (var t in parts) { _restT.Add(t); _restS.Add(t.localScale); _restR.Add(t.localRotation); }
    }

    Part MakePart(Transform t, float t0, float t1)
    {
        int i = _restT.IndexOf(t);
        return new Part { t = t, restScale = i >= 0 ? _restS[i] : t.localScale, restRot = i >= 0 ? _restR[i] : t.localRotation, t0 = t0, t1 = t1 };
    }

    void Start()
    {
        _previewStart = Time.time;
        if (Application.isPlaying && playOnStart && control == Control.Stages) { stage = 0; growth = StageTarget(); }   // preview starts from the sprout
    }

    void Update()
    {
        if (Application.isPlaying && playOnStart)
        {
            float t = Time.time - _previewStart;
            if (control == Control.Stages && stageValues.Length > 0)
            {
                int n = stageValues.Length;
                // walk through the stages, rest on the last one, then start again from the sprout
                int step = Mathf.FloorToInt(t / Mathf.Max(previewStageInterval, 0.1f)) % (n + 1);
                stage = Mathf.Min(step, n - 1);
                if (step == n) { stage = 0; _previewStart = Time.time; growth = StageTarget(); }
            }
            else
            {
                float cycle = previewDuration + previewHold;
                if (previewHold > 0f) t %= cycle;
                growth = Mathf.Clamp01(t / Mathf.Max(previewDuration, 0.01f));
            }
        }
        if (Application.isPlaying && control == Control.Stages)
        {
            // move toward the stage at a steady speed: one stage gap per Stage Transition seconds
            float target = StageTarget();
            float gap = stageValues.Length > 1 ? 1f / (stageValues.Length - 1) : 1f;
            float speed = stageTransition > 0f ? gap / stageTransition * 1.4f : float.MaxValue;
            growth = Mathf.MoveTowards(growth, target, speed * Time.deltaTime);
        }
        if (!Mathf.Approximately(_applied, growth)) Apply();
    }

    void Build()
    {
        _bones.Clear(); _leaves.Clear(); _fruit.Clear(); _fruitRenderers.Clear(); _fruitMats.Clear();
        var all = GetComponentsInChildren<Transform>(true);
        Transform root = null;
        foreach (var t in all) if (t.name == "Root") { root = t; break; }
        if (root == null) { _ready = false; return; }
        // measure the bones in the rest pose (positions of child bones depend on the parents' current scale)
        for (int i = 0; i < _restT.Count; i++)
            if (_restT[i] != null) { _restT[i].localScale = _restS[i]; _restT[i].localRotation = _restR[i]; }

        var dist = new Dictionary<Transform, float>();
        var bones = new List<Transform>();
        void Walk(Transform b, float d)
        {
            dist[b] = d; bones.Add(b);
            foreach (Transform c in b)
                if (IsBone(c)) Walk(c, d + Vector3.Distance(b.position, c.position));
        }
        Walk(root, 0f);
        float maxTip = 0f;
        var tip = new Dictionary<Transform, float>();
        foreach (var b in bones)
        {
            float len = 0.05f;   // leaf bones with no child: a short default length (m)
            foreach (Transform c in b) if (IsBone(c)) len = Mathf.Max(len, Vector3.Distance(b.position, c.position));
            tip[b] = dist[b] + len;
            maxTip = Mathf.Max(maxTip, tip[b]);
        }
        var parts = new List<Transform>(bones);
        foreach (var t in all) if ((t.name.Contains("_Leaf_") || t.name.Contains("_Fruit_")) && !parts.Contains(t)) parts.Add(t);
        CaptureRest(parts);
        foreach (var b in bones)
        {
            if (b == root) continue;
            _bones.Add(MakePart(b, dist[b] / maxTip * branchesDone, tip[b] / maxTip * branchesDone));
        }

        foreach (var t in all)
        {
            if (t.name.Contains("_Leaf_"))
            {
                float start = ParentBoneTip(t, tip, maxTip);
                _leaves.Add(MakePart(t, start, start + leafTime));
            }
            else if (t.name.Contains("_Fruit_") && t.GetComponent<Renderer>() != null)   // the lantern meshes, not the Stalk_Fruit_* bones
            {
                float k = Mathf.InverseLerp(0f, branchesDone, ParentBoneTip(t, tip, maxTip));
                float span = (fruitWindow.y - fruitWindow.x) * 0.5f;
                float s0 = Mathf.Lerp(fruitWindow.x, fruitWindow.y - span, k);   // lower fruit first
                _fruit.Add(MakePart(t, s0, s0 + span));
                var r = t.GetComponent<Renderer>();
                if (r) { _fruitRenderers.Add(r); _fruitMats.Add(r.sharedMaterials); }
            }
        }
        _mpb ??= new MaterialPropertyBlock();
        _ready = true;
    }

    static bool IsBone(Transform t) => t.GetComponent<Renderer>() == null && !t.name.StartsWith("IK_");

    float ParentBoneTip(Transform t, Dictionary<Transform, float> tip, float maxTip)
    {
        for (var p = t.parent; p != null; p = p.parent)
            if (tip.TryGetValue(p, out float v)) return v / maxTip * branchesDone;
        return branchesDone;
    }

    static float Ease(float x) { x = Mathf.Clamp01(x); return x * x * (3f - 2f * x); }

    static float EaseOutBack(float x)
    {
        x = Mathf.Clamp01(x);
        const float c1 = 1.4f, c3 = c1 + 1f;
        return 1f + c3 * Mathf.Pow(x - 1f, 3f) + c1 * Mathf.Pow(x - 1f, 2f);
    }

    void Apply()
    {
        if (!_ready) Build();
        if (!_ready) return;
        _applied = growth;
        const float tiny = 0.001f;   // never exactly 0: keeps the skinning matrices valid

        foreach (var b in _bones)
        {
            float k = Ease(Mathf.InverseLerp(b.t0, b.t1, growth));
            b.t.localScale = b.restScale * Mathf.Max(k, tiny);
        }
        foreach (var l in _leaves)
        {
            float x = Mathf.InverseLerp(l.t0, l.t1, growth);
            float k = EaseOutBack(x);
            l.t.localScale = l.restScale * Mathf.Max(k, tiny);
            l.t.localRotation = l.restRot * Quaternion.Euler((1f - Ease(x)) * leafFold, 0f, 0f);
        }
        float glow = Ease(Mathf.InverseLerp(glowWindow.x, glowWindow.y, growth));
        for (int i = 0; i < _fruit.Count; i++)
        {
            var f = _fruit[i];
            float k = EaseOutBack(Mathf.InverseLerp(f.t0, f.t1, growth));
            f.t.localScale = f.restScale * Mathf.Max(k, tiny);
        }
        for (int i = 0; i < _fruitRenderers.Count; i++)
        {
            var r = _fruitRenderers[i]; var mats = _fruitMats[i];
            for (int m = 0; m < mats.Length; m++)
            {
                if (mats[m] == null) continue;
                if (glow >= 0.999f) { r.SetPropertyBlock(null, m); continue; }   // fully lit: plain material (batching)
                _mpb.Clear();
                foreach (var p in ShellGlowProps)
                    if (mats[m].HasProperty(p)) _mpb.SetFloat(p, mats[m].GetFloat(p) * glow);
                if (mats[m].HasProperty("_BaseColor") && !mats[m].HasProperty("_GlowStrength"))
                {
                    // inner glow sphere (URP Unlit, HDR colour): fade from a dim ember to full brightness
                    Color c = mats[m].GetColor("_BaseColor");
                    _mpb.SetColor("_BaseColor", Color.Lerp(c * 0.08f, c, glow));
                }
                r.SetPropertyBlock(_mpb, m);
            }
        }
    }
}
