using UnityEngine;

/// <summary>
/// Watering-can stream for the held tool: droplets leave the spout tip (child "WateringCan_SpoutTip", its forward points
/// out of the spout), fall in an arc and burst into a few small splashes where they hit anything with a collider
/// (the soil cells have one). Pour(seconds), or StartPour / StopPour.
/// PROTOTYPE REFERENCE ONLY: per the art request doc the developers assemble the particles (art delivers vfx_water_drop)
/// and show wet soil with their own colour, so this is not delivered to the team. Values are my own.
/// </summary>
public class WaterFX : MonoBehaviour
{
    public Transform Spout;
    [Tooltip("vfx_water_drop material (URP Particles/Unlit, transparent)")] public Material DropMaterial;
    public Color WaterColor = new Color(0.38f, 0.95f, 0.88f, 0.85f);   // palette cyan #62F2E1, a little transparent
    public float DropsPerSecond = 120f;
    public Vector2 DropSpeed = new Vector2(1.1f, 1.7f);
    public Vector2 DropSize = new Vector2(0.04f, 0.07f);
    [Tooltip("Spread of the stream (degrees)")] public float Spread = 5f;
    public int SplashDrops = 5;

    ParticleSystem _stream, _splash;
    float _stopAt = -1f;

    void Awake()
    {
        if (Spout == null) Spout = FindDeep(transform, "WateringCan_SpoutTip");
        if (Spout == null) Spout = transform;
    }

    public void Pour(float seconds) { StartPour(); _stopAt = Time.time + seconds; }

    public void StartPour()
    {
        if (_stream == null) Build();
        var em = _stream.emission; em.enabled = true;
        if (!_stream.isPlaying) _stream.Play();
        _stopAt = -1f;
    }

    public void StopPour()
    {
        if (_stream == null) return;
        var em = _stream.emission; em.enabled = false;
    }

    void Update()
    {
        if (_stopAt > 0f && Time.time >= _stopAt) { StopPour(); _stopAt = -1f; }
    }

    void Build()
    {
        // the falling stream
        var go = new GameObject("WaterStream");
        go.transform.SetParent(Spout, false);
        _stream = go.AddComponent<ParticleSystem>();
        _stream.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
        var main = _stream.main;
        main.playOnAwake = false;
        main.simulationSpace = ParticleSystemSimulationSpace.World;
        main.startLifetime = 1.4f;
        main.startSpeed = new ParticleSystem.MinMaxCurve(DropSpeed.x, DropSpeed.y);
        main.startSize = new ParticleSystem.MinMaxCurve(DropSize.x, DropSize.y);
        main.startColor = WaterColor;
        main.gravityModifier = 1f;
        main.maxParticles = 300;
        var emission = _stream.emission; emission.rateOverTime = DropsPerSecond; emission.enabled = false;
        var shape = _stream.shape;
        shape.shapeType = ParticleSystemShapeType.Cone; shape.angle = Spread; shape.radius = 0.012f;
        var col = _stream.collision;
        col.enabled = true; col.type = ParticleSystemCollisionType.World; col.mode = ParticleSystemCollisionMode.Collision3D;
        col.lifetimeLoss = 1f; col.bounce = 0f; col.dampen = 1f; col.quality = ParticleSystemCollisionQuality.Medium;
        col.radiusScale = 0.5f;
        SetupRenderer(go.GetComponent<ParticleSystemRenderer>());

        // little splashes where a drop lands
        var sgo = new GameObject("WaterSplash");
        sgo.transform.SetParent(go.transform, false);
        _splash = sgo.AddComponent<ParticleSystem>();
        _splash.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
        var sm = _splash.main;
        sm.playOnAwake = false;
        sm.simulationSpace = ParticleSystemSimulationSpace.World;
        sm.startLifetime = new ParticleSystem.MinMaxCurve(0.18f, 0.32f);
        sm.startSpeed = new ParticleSystem.MinMaxCurve(0.4f, 0.9f);
        sm.startSize = new ParticleSystem.MinMaxCurve(DropSize.x * 0.4f, DropSize.x * 0.8f);
        sm.startColor = WaterColor;
        sm.gravityModifier = 1.6f;
        var se = _splash.emission; se.rateOverTime = 0f;
        se.SetBursts(new[] { new ParticleSystem.Burst(0f, (short)SplashDrops) });
        var ss = _splash.shape; ss.shapeType = ParticleSystemShapeType.Hemisphere; ss.radius = 0.02f;
        var sz = _splash.sizeOverLifetime; sz.enabled = true;
        sz.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0f, 1f, 1f, 0.2f));
        SetupRenderer(sgo.GetComponent<ParticleSystemRenderer>());

        var sub = _stream.subEmitters; sub.enabled = true;
        sub.AddSubEmitter(_splash, ParticleSystemSubEmitterType.Collision, ParticleSystemSubEmitterProperties.InheritNothing);
    }

    void SetupRenderer(ParticleSystemRenderer r)
    {
        r.renderMode = ParticleSystemRenderMode.Billboard;
        r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        r.receiveShadows = false;
        if (DropMaterial == null)
        {
            var sh = Shader.Find("Universal Render Pipeline/Particles/Unlit");
            DropMaterial = new Material(sh != null ? sh : Shader.Find("Sprites/Default"));
        }
        r.sharedMaterial = DropMaterial;
    }

    static Transform FindDeep(Transform t, string name)
    {
        if (t.name == name) return t;
        foreach (Transform c in t) { var f = FindDeep(c, name); if (f != null) return f; }
        return null;
    }
}
