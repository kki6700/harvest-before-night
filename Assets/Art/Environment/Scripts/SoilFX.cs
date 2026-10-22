using System.Collections;
using UnityEngine;

/// <summary>
/// Visual side of one farm-cell soil (DSEWA/ToonSoil). The game keeps the state; this only shows it:
///   OnTillHit(progress, point) - one hoe hit: a dug patch opens where the blade landed and spreads, clods fly,
///                                 the soil squashes a little; at progress 1 the whole cell is dug.
///   OnPlant()                  - a pit opens in the middle, the seed goes in, the soil closes into a small mound.
///   SetTill(0..1) (no effects, e.g. after loading), ResetSoil() (back to crust after harvest).
/// Writes only its own shader values through the renderer's MaterialPropertyBlock and keeps whatever else is in it
/// (FarmCellView's _BaseColor). Wet soil stays the game's job (its wet colour), per the art request doc. Call OnTillHit when the blade touches the ground (about 35 % into the swing),
/// not on the click. All timings / sizes are my own starting values.
/// </summary>
[RequireComponent(typeof(Renderer))]
public class SoilFX : MonoBehaviour
{
    [Header("Hoe hit")]
    [Tooltip("Seconds for a dug patch to open")] public float HitOpenTime = 0.18f;
    [Tooltip("Seconds for the whole cell to finish when the till is complete")] public float FinishTime = 0.35f;
    [Tooltip("Squash on each hit (fraction of the soil height)")] public float HitSquash = 0.35f;

    [Header("Clods")]
    public bool Clods = true;
    [Tooltip("Optional; a vertex-colour particle material is made if empty")] public Material ClodMaterial;
    public int ClodsPerHit = 12;
    public float ClodSize = 0.045f;
    public float ClodSpeed = 1.6f;

    [Header("Planting")]
    public float PitOpenTime = 0.16f;
    public float PitHoldTime = 0.18f;
    public float CoverTime = 0.28f;

    static readonly int TillId = Shader.PropertyToID("_Till");
    static readonly int HoleId = Shader.PropertyToID("_Hole");
    static readonly int MoundId = Shader.PropertyToID("_Mound");
    static readonly int BaseColorId = Shader.PropertyToID("_BaseColor");
    static readonly int[] HitIds =
    {
        Shader.PropertyToID("_Hit0"), Shader.PropertyToID("_Hit1"), Shader.PropertyToID("_Hit2"), Shader.PropertyToID("_Hit3")
    };

    Renderer _renderer;
    MaterialPropertyBlock _block;
    readonly Vector4[] _hits = new Vector4[4];
    int _nextHit;
    float _till, _hole, _mound;
    Vector3 _baseScale;
    ParticleSystem _clods;

    void Awake()
    {
        _renderer = GetComponent<Renderer>();
        _block = new MaterialPropertyBlock();
        _baseScale = transform.localScale;
    }

    // ---------------------------------------------------------------- game calls

    public void OnTillHit(float progress01, Vector3 worldPoint)
    {
        Vector3 local = transform.InverseTransformPoint(worldPoint);
        int slot = _nextHit;
        _nextHit = (_nextHit + 1) % _hits.Length;
        _hits[slot] = new Vector4(local.x, local.z, 0f, 0f);
        StartCoroutine(OpenHit(slot));
        StartCoroutine(Squash());
        if (Clods) BurstClods(worldPoint);
        if (progress01 >= 0.999f) StartCoroutine(Tween(v => _till = v, _till, 1f, FinishTime, HitOpenTime * 0.5f));
    }

    public void OnPlant() => StartCoroutine(PlantRoutine());

    public void SetTill(float progress01)
    {
        _till = progress01 >= 0.999f ? 1f : 0f;
        if (progress01 > 0f && progress01 < 0.999f)   // partly dug after a load: one patch in the middle that grows
            _hits[0] = new Vector4(0f, 0f, 0f, Mathf.Clamp01(progress01 * 1.4f));
    }


    public void ResetSoil()
    {
        StopAllCoroutines();
        _till = _hole = _mound = 0f;
        for (int i = 0; i < _hits.Length; i++) _hits[i] = Vector4.zero;
        transform.localScale = _baseScale;
    }

    // ---------------------------------------------------------------- routines

    IEnumerator OpenHit(int slot)
    {
        for (float t = 0f; t < HitOpenTime; t += Time.deltaTime)
        {
            float k = t / HitOpenTime;
            _hits[slot].w = 1f - (1f - k) * (1f - k);          // ease out
            yield return null;
        }
        _hits[slot].w = 1f;
    }

    IEnumerator Squash()
    {
        const float duration = 0.22f;
        for (float t = 0f; t < duration; t += Time.deltaTime)
        {
            float k = t / duration;
            float y = 1f - HitSquash * Mathf.Sin(k * Mathf.PI) * (1f - k) * 1.6f;   // down, then a small rebound
            transform.localScale = new Vector3(_baseScale.x, _baseScale.y * y, _baseScale.z);
            yield return null;
        }
        transform.localScale = _baseScale;
    }

    IEnumerator PlantRoutine()
    {
        yield return Tween(v => _hole = v, _hole, 1f, PitOpenTime, 0f);
        yield return new WaitForSeconds(PitHoldTime);
        if (Clods) BurstClods(transform.position + transform.up * 0.08f, 6);
        float t0 = Time.time;
        while (Time.time - t0 < CoverTime)
        {
            float k = (Time.time - t0) / CoverTime;
            _hole = 1f - k;
            _mound = Mathf.Sin(k * Mathf.PI * 0.5f) * (1f + 0.25f * Mathf.Sin(k * Mathf.PI));   // a little overshoot
            yield return null;
        }
        _hole = 0f; _mound = 1f;
    }

    IEnumerator Tween(System.Action<float> set, float from, float to, float duration, float delay)
    {
        if (delay > 0f) yield return new WaitForSeconds(delay);
        for (float t = 0f; t < duration; t += Time.deltaTime)
        {
            float k = t / duration;
            set(Mathf.Lerp(from, to, k * k * (3f - 2f * k)));
            yield return null;
        }
        set(to);
    }

    // ---------------------------------------------------------------- clods

    void BurstClods(Vector3 point, int count = -1)
    {
        if (_clods == null) _clods = MakeClods();
        _renderer.GetPropertyBlock(_block);
        Color soil = _block.HasColor(BaseColorId) ? _block.GetColor(BaseColorId) : _renderer.sharedMaterial.GetColor(BaseColorId);
        var emit = new ParticleSystem.EmitParams
        {
            position = point + Vector3.up * 0.03f,
            applyShapeToPosition = true,
            startColor = Color.Lerp(soil, Color.white, 0.15f)
        };
        _clods.Emit(emit, count < 0 ? ClodsPerHit : count);
    }

    ParticleSystem MakeClods()
    {
        var go = new GameObject("SoilClods");
        go.transform.SetParent(transform, false);
        var ps = go.AddComponent<ParticleSystem>();
        ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
        var main = ps.main;
        main.playOnAwake = false;
        main.loop = false;
        main.simulationSpace = ParticleSystemSimulationSpace.World;
        main.startLifetime = new ParticleSystem.MinMaxCurve(0.45f, 0.75f);
        main.startSpeed = new ParticleSystem.MinMaxCurve(ClodSpeed * 0.5f, ClodSpeed);
        main.startSize = new ParticleSystem.MinMaxCurve(ClodSize * 0.5f, ClodSize);
        main.startRotation3D = true;
        main.startRotationX = main.startRotationY = main.startRotationZ = new ParticleSystem.MinMaxCurve(0f, Mathf.PI * 2f);
        main.gravityModifier = 2.2f;
        main.maxParticles = 128;
        var emission = ps.emission; emission.enabled = false;
        var shape = ps.shape;
        shape.shapeType = ParticleSystemShapeType.Cone;
        shape.angle = 35f; shape.radius = 0.06f;
        shape.rotation = new Vector3(-90f, 0f, 0f);                    // cone opens upward
        var size = ps.sizeOverLifetime; size.enabled = true;
        size.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0f, 1f, 1f, 0.3f));
        var rot = ps.rotationOverLifetime; rot.enabled = true; rot.separateAxes = true;
        rot.x = rot.y = rot.z = new ParticleSystem.MinMaxCurve(-6f, 6f);
        var r = go.GetComponent<ParticleSystemRenderer>();
        r.renderMode = ParticleSystemRenderMode.Mesh;
        var cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
        r.mesh = cube.GetComponent<MeshFilter>().sharedMesh;
        Destroy(cube);
        if (ClodMaterial == null)
        {
            var sh = Shader.Find("Universal Render Pipeline/Particles/Simple Lit");
            ClodMaterial = new Material(sh != null ? sh : Shader.Find("Sprites/Default"));
        }
        r.sharedMaterial = ClodMaterial;
        r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        return ps;
    }

    // ---------------------------------------------------------------- shader values

    void LateUpdate()
    {
        _renderer.GetPropertyBlock(_block);          // keep FarmCellView's colour
        _block.SetFloat(TillId, _till);
        _block.SetFloat(HoleId, _hole);
        _block.SetFloat(MoundId, _mound);
        for (int i = 0; i < _hits.Length; i++) _block.SetVector(HitIds[i], _hits[i]);
        _renderer.SetPropertyBlock(_block);
    }
}
