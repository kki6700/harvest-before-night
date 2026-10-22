using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// Draws the ringed planet and its two moons as 3D meshes in the sky (replaces the flat disc ToonSky drew).
/// Like MoonModel it renders per camera right before the camera draws (Graphics.RenderMesh): no scene objects move,
/// and the meshes are shrunk towards the camera inside the far plane by the shaders (_CameraShrink).
/// Everything art-directed stays on the sky material, so the DayNightBlend presets keep driving it:
/// _PlanetDir / _PlanetSize (angular radius) / _RingInnerOuter (inner, outer, roll on screen, opening) /
/// _PlanetSpin / _RingSpin / colours / _Moon2*, _Moon4* orbits, and _PlanetAmount fades it in and out.
/// ToonSky stops drawing its own ringed planet and moons 2 and 4 while this is enabled (_PlanetSkyDraw = 0).
/// </summary>
[ExecuteAlways]
public class SkyRingedPlanet : MonoBehaviour
{
    public Material sky;
    public Material bodyMaterial;   // DSEWA/ToonPlanet
    public Material ringMaterial;   // DSEWA/ToonPlanetRing
    public Material moonMaterial;   // DSEWA/ToonPlanet (no bands)
    public Mesh sphere;

    [Tooltip("Real distance in metres (the shaders shrink it inside the camera's far plane)")]
    public float distance = 4500f;
    [Tooltip("Moons orbit in the ring plane, tipped by this much (degrees)")]
    public float moonInclination = 6f;
    [Tooltip("Ring mesh segments round the circle")]
    public int ringSegments = 256;
    public bool animateInEditor = true;

    static readonly int ShrinkId = Shader.PropertyToID("_CameraShrink");
    static readonly int FadeId = Shader.PropertyToID("_Fade");
    static readonly int SpinId = Shader.PropertyToID("_Spin");
    static readonly int TurnId = Shader.PropertyToID("_RingTurn");
    static readonly int RingIOId = Shader.PropertyToID("_RingInnerOuter");
    static readonly int LitId = Shader.PropertyToID("_LitColor");
    static readonly int ShadowId = Shader.PropertyToID("_ShadowColor");
    static readonly int BandColId = Shader.PropertyToID("_BandColor");
    static readonly int RimId = Shader.PropertyToID("_RimColor");
    static readonly int BandsId = Shader.PropertyToID("_Bands");
    static readonly int BandAmountId = Shader.PropertyToID("_BandAmount");
    static readonly int RingColId = Shader.PropertyToID("_RingColor");
    static readonly int OpacityId = Shader.PropertyToID("_Opacity");

    // runtime cache only (NonSerialized: a script reload must not bring back a mesh built by older code)
    [System.NonSerialized] Mesh ringMesh;
    [System.NonSerialized] float builtInner = -1, builtOuter = -1;
    [System.NonSerialized] int builtSegments = -1;
    [System.NonSerialized] MaterialPropertyBlock bodyMpb, ringMpb, moonMpb;

    static float Now()
    {
#if UNITY_EDITOR
        if (!Application.isPlaying) return (float)UnityEditor.EditorApplication.timeSinceStartup;
#endif
        return Time.time;
    }

#if UNITY_EDITOR
    void Update()
    {
        if (!Application.isPlaying && animateInEditor) UnityEditor.EditorApplication.QueuePlayerLoopUpdate();
    }
#endif

    void OnEnable()
    {
        RenderPipelineManager.beginCameraRendering += OnBeginCamera;
        if (sky) sky.SetFloat("_PlanetSkyDraw", 0);
    }

    void OnDisable()
    {
        RenderPipelineManager.beginCameraRendering -= OnBeginCamera;
        if (sky) sky.SetFloat("_PlanetSkyDraw", 1);
    }

    // flat annulus in the ring's object space (y = 0), radii in planet radii (drawn with scale = planet radius)
    void BuildRing(float inner, float outer)
    {
        if (ringMesh != null && Mathf.Approximately(inner, builtInner) && Mathf.Approximately(outer, builtOuter) && builtSegments == ringSegments) return;
        if (ringMesh == null) { ringMesh = new Mesh { name = "SkyPlanetRing", hideFlags = HideFlags.HideAndDontSave }; }
        int n = Mathf.Max(16, ringSegments);
        var v = new Vector3[(n + 1) * 2];
        var nr = new Vector3[v.Length];
        var uv = new Vector2[v.Length];
        var tri = new int[n * 6];
        for (int i = 0; i <= n; i++)
        {
            float a = i / (float)n * Mathf.PI * 2f;
            var d = new Vector3(Mathf.Cos(a), 0, Mathf.Sin(a));
            v[i * 2] = d * inner; v[i * 2 + 1] = d * outer;
            nr[i * 2] = nr[i * 2 + 1] = Vector3.up;
            uv[i * 2] = new Vector2(0, i / (float)n); uv[i * 2 + 1] = new Vector2(1, i / (float)n);
            if (i < n)
            {
                int k = i * 6, b = i * 2;
                tri[k] = b; tri[k + 1] = b + 2; tri[k + 2] = b + 1;
                tri[k + 3] = b + 1; tri[k + 4] = b + 2; tri[k + 5] = b + 3;
            }
        }
        ringMesh.Clear();
        ringMesh.vertices = v; ringMesh.normals = nr; ringMesh.uv = uv; ringMesh.triangles = tri;
        ringMesh.RecalculateBounds();
        builtInner = inner; builtOuter = outer; builtSegments = ringSegments;
    }

    void OnBeginCamera(ScriptableRenderContext ctx, Camera cam)
    {
        if (!sky || !bodyMaterial || !ringMaterial || !sphere || cam.cameraType == CameraType.Preview) return;
        float amount = sky.GetFloat("_PlanetAmount");
        if (amount < 0.01f) return;

        float time = Application.isPlaying || animateInEditor ? Now() : 0f;
        Vector3 eye = cam.transform.position;
        Vector3 P = ((Vector3)sky.GetVector("_PlanetDir")).normalized;
        float angR = sky.GetFloat("_PlanetSize");                       // angular radius (rad)
        float R = distance * Mathf.Tan(angR);                           // planet radius in metres
        Vector4 rio = sky.GetVector("_RingInnerOuter");                 // inner, outer, roll on screen, opening (sin)
        float shrink = Mathf.Min(1f, cam.farClipPlane * 0.92f / (distance + R * rio.y * 2f));

        // spin axis exactly as ToonSky built it: rolled on screen, tipped towards the viewer by the ring opening
        Vector3 right = Vector3.Cross(Vector3.up, P).normalized;
        Vector3 upv = Vector3.Cross(P, right);
        float roll = rio.z;
        float tilt = Mathf.Asin(Mathf.Clamp01(rio.w)) * sky.GetFloat("_PlanetAxisSign");
        Vector3 axis = (Mathf.Cos(roll) * upv - Mathf.Sin(roll) * right).normalized;
        axis = (axis * Mathf.Cos(tilt) - P * Mathf.Sin(tilt)).normalized;
        Quaternion frame = Quaternion.FromToRotation(Vector3.up, axis);
        float spinRad = time * sky.GetFloat("_PlanetSpin");
        Quaternion bodyRot = Quaternion.AngleAxis(spinRad * Mathf.Rad2Deg, axis) * frame;
        Vector3 centre = eye + P * distance;

        if (bodyMpb == null) { bodyMpb = new MaterialPropertyBlock(); ringMpb = new MaterialPropertyBlock(); moonMpb = new MaterialPropertyBlock(); }

        bodyMpb.SetFloat(ShrinkId, shrink); bodyMpb.SetFloat(FadeId, amount);
        bodyMpb.SetFloat(SpinId, 0);
        bodyMpb.SetVector(RingIOId, rio);
        bodyMpb.SetColor(LitId, sky.GetColor("_PlanetLit")); bodyMpb.SetColor(ShadowId, sky.GetColor("_PlanetShadow"));
        bodyMpb.SetColor(BandColId, sky.GetColor("_PlanetBand")); bodyMpb.SetColor(RimId, sky.GetColor("_PlanetRim"));
        bodyMpb.SetFloat(BandsId, sky.GetFloat("_PlanetBands")); bodyMpb.SetFloat(BandAmountId, sky.GetFloat("_PlanetBandAmount"));
        var rpBody = new RenderParams(bodyMaterial)
        {
            camera = cam, matProps = bodyMpb, shadowCastingMode = ShadowCastingMode.Off, receiveShadows = false,
            worldBounds = new Bounds(eye, Vector3.one * distance * 4f), layer = gameObject.layer
        };
        float meshR = Mathf.Max(sphere.bounds.extents.x, 1e-4f);         // Unity's built-in sphere has radius 1 here
        Graphics.RenderMesh(rpBody, sphere, 0, Matrix4x4.TRS(centre, bodyRot, Vector3.one * R / meshR));

        // ring: same frame (not the body spin), clumps turn in the shader
        float ringAmount = sky.GetFloat("_RingAmount");
        if (ringAmount > 0.001f)
        {
            BuildRing(rio.x, rio.y);
            ringMpb.SetFloat(ShrinkId, shrink); ringMpb.SetFloat(FadeId, amount);
            ringMpb.SetFloat(TurnId, time * sky.GetFloat("_RingSpin"));
            ringMpb.SetVector(RingIOId, rio);
            ringMpb.SetColor(RingColId, sky.GetColor("_RingColor"));
            ringMpb.SetFloat(OpacityId, ringAmount);
            var rpRing = new RenderParams(ringMaterial)
            {
                camera = cam, matProps = ringMpb, shadowCastingMode = ShadowCastingMode.Off, receiveShadows = false,
                worldBounds = new Bounds(eye, Vector3.one * distance * 4f), layer = gameObject.layer
            };
            Graphics.RenderMesh(rpRing, ringMesh, 0, Matrix4x4.TRS(centre, frame, Vector3.one * R));
        }

        // moons: orbit in the ring plane (slightly inclined); radius / size converted from ToonSky's angular values
        if (moonMaterial)
        {
            DrawMoon(cam, eye, centre, axis, R, angR, sky.GetVector("_Moon2Orbit"), sky.GetFloat("_Moon2Size"),
                     sky.GetColor("_Moon2Lit"), sky.GetColor("_Moon2Shadow"), time, shrink, amount);
            DrawMoon(cam, eye, centre, axis, R, angR, sky.GetVector("_Moon4Orbit"), sky.GetFloat("_Moon4Size"),
                     sky.GetColor("_Moon2Lit") * 0.95f, sky.GetColor("_Moon2Shadow") * 1.1f, time, shrink, amount);
        }
    }

    void DrawMoon(Camera cam, Vector3 eye, Vector3 centre, Vector3 axis, float R, float angR, Vector4 orb, float angSize,
                  Color lit, Color shadow, float time, float shrink, float amount)
    {
        if (orb.x <= 0 || angSize <= 1e-4f) return;
        // orbit plane = ring plane tipped about a fixed in-plane axis
        Vector3 n = Quaternion.AngleAxis(moonInclination, Vector3.Cross(axis, Vector3.up).sqrMagnitude > 1e-6f
                     ? Vector3.Cross(axis, Vector3.up).normalized : Vector3.right) * axis;
        Vector3 e1 = Vector3.Cross(n, Vector3.up).sqrMagnitude > 1e-6f ? Vector3.Cross(n, Vector3.up).normalized : Vector3.right;
        Vector3 e2 = Vector3.Cross(n, e1);
        float radius = orb.x / Mathf.Max(angR, 1e-4f) * R;              // ToonSky's orbit radius was angular
        float a = orb.w + 2f * Mathf.PI * time / Mathf.Max(orb.y, 1f);
        Vector3 pos = centre + (e1 * Mathf.Cos(a) + e2 * Mathf.Sin(a)) * radius;
        float size = Vector3.Distance(eye, pos) * Mathf.Tan(angSize) / Mathf.Max(sphere.bounds.extents.x, 1e-4f);
        moonMpb.SetFloat(ShrinkId, shrink); moonMpb.SetFloat(FadeId, amount);
        moonMpb.SetFloat(BandAmountId, 0);
        moonMpb.SetVector(RingIOId, sky.GetVector("_RingInnerOuter"));
        moonMpb.SetColor(LitId, lit); moonMpb.SetColor(ShadowId, shadow);
        moonMpb.SetColor(RimId, lit);
        var rp = new RenderParams(moonMaterial)
        {
            camera = cam, matProps = moonMpb, shadowCastingMode = ShadowCastingMode.Off, receiveShadows = false,
            worldBounds = new Bounds(eye, Vector3.one * distance * 4f), layer = gameObject.layer
        };
        Graphics.RenderMesh(rp, sphere, 0, Matrix4x4.TRS(pos, Quaternion.identity, Vector3.one * size));
    }
}
