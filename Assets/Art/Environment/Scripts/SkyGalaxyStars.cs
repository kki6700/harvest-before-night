using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// GPU "particles" for the big galaxy ToonSky paints: a baked mesh of star knots (one quad each) sitting on the
/// spiral arms of the galaxy map, drawn per camera like MoonModel / SkyRingedPlanet (Graphics.RenderMesh, shrunk
/// inside the far plane by the shader). Placement, size, roll, tilt and spin come from the sky material
/// (_GalBig, _GalBigShape, _GalaxyDrift.w), so the knots stay locked to the painted spiral; _StarAmount fades them.
/// Bake: context menu "Bake Star Mesh" samples the exported galaxy map (R = spiral arms) and saves the mesh asset.
/// </summary>
[ExecuteAlways]
public class SkyGalaxyStars : MonoBehaviour
{
    public Material sky;
    public Material starMaterial;   // DSEWA/ToonGalaxyStars
    public Mesh starMesh;

    [Tooltip("Real distance in metres (shrunk inside the far plane)")]
    public float distance = 7000f;

    [Header("Bake")]
    [Tooltip("Galaxy map exported from GalaxyMaps.sbs (R = spiral arms), project-relative")]
    public string sourcePng = "Art/Environment/Sky/GalaxyMaps_export/Galaxy_Maps.png";
    public string meshAssetPath = "Assets/Art/Environment/Sky/Meshes/SkyGalaxyStars.asset";
    public int count = 700;
    public int seed = 7;
    [Tooltip("Star size as an angle (radians): min, max")]
    public Vector2 sizeRange = new Vector2(0.0012f, 0.0042f);
    [Tooltip("Share of stars placed by the bulge (centre) instead of the arms")]
    [Range(0f, 1f)] public float bulgeShare = 0.15f;
    [Tooltip("Map value (R) where an arm starts")]
    [Range(0f, 1f)] public float armThreshold = 0.12f;

    static readonly int DirId = Shader.PropertyToID("_GalDir");
    static readonly int RightId = Shader.PropertyToID("_GalRight");
    static readonly int UpId = Shader.PropertyToID("_GalUp");
    static readonly int ShapeId = Shader.PropertyToID("_GalShape");
    static readonly int DistId = Shader.PropertyToID("_GalDist");
    static readonly int CoreId = Shader.PropertyToID("_CoreColor");
    static readonly int EdgeId = Shader.PropertyToID("_EdgeColor");
    [System.NonSerialized] MaterialPropertyBlock mpb;

    static float Now()
    {
#if UNITY_EDITOR
        if (!Application.isPlaying) return (float)UnityEditor.EditorApplication.timeSinceStartup;
#endif
        return Time.time;
    }

    void OnEnable() => RenderPipelineManager.beginCameraRendering += OnBeginCamera;
    void OnDisable() => RenderPipelineManager.beginCameraRendering -= OnBeginCamera;

    void OnBeginCamera(ScriptableRenderContext ctx, Camera cam)
    {
        if (!sky || !starMaterial || !starMesh || cam.cameraType == CameraType.Preview) return;
        float fade = sky.GetFloat("_StarAmount");
        Vector4 g = sky.GetVector("_GalBig"), shape = sky.GetVector("_GalBigShape");
        if (fade < 0.01f || shape.w <= 0f) return;
        Vector3 P = ((Vector3)g).normalized;
        fade *= Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(0.02f, 0.2f, P.y));     // horizon fade like ToonSky
        Vector3 right = Vector3.Cross(Vector3.up, P).normalized;
        Vector3 up = Vector3.Cross(P, right);
        float spin = Now() * sky.GetVector("_GalaxyDrift").w;
        float shrink = Mathf.Min(1f, cam.farClipPlane * 0.9f / distance);

        if (mpb == null) mpb = new MaterialPropertyBlock();
        mpb.SetVector(DirId, P); mpb.SetVector(RightId, right); mpb.SetVector(UpId, up);
        mpb.SetVector(ShapeId, new Vector4(g.w, shape.x, shape.y, spin));
        mpb.SetVector(DistId, new Vector4(distance, shrink, fade * shape.w, 0));
        mpb.SetColor(CoreId, sky.GetColor("_GalaxyCore")); mpb.SetColor(EdgeId, sky.GetColor("_GalaxyEdge"));
        var rp = new RenderParams(starMaterial)
        {
            camera = cam, matProps = mpb, shadowCastingMode = ShadowCastingMode.Off, receiveShadows = false,
            worldBounds = new Bounds(cam.transform.position, Vector3.one * distance * 4f), layer = gameObject.layer
        };
        Graphics.RenderMesh(rp, starMesh, 0, Matrix4x4.identity);
    }

#if UNITY_EDITOR
    [ContextMenu("Bake Star Mesh")]
    public void Bake()
    {
        string full = System.IO.Path.Combine(System.IO.Directory.GetCurrentDirectory(), sourcePng);
        var tex = new Texture2D(2, 2, TextureFormat.RGBA64, false, true);
        if (!System.IO.File.Exists(full) || !tex.LoadImage(System.IO.File.ReadAllBytes(full))) { Debug.LogError("SkyGalaxyStars: cannot read " + full); return; }
        var rng = new System.Random(seed);
        System.Func<float> R = () => (float)rng.NextDouble();
        var verts = new Vector3[count * 4]; var corners = new Vector2[count * 4]; var data = new Vector4[count * 4];
        var tris = new int[count * 6];
        Vector2[] cc = { new Vector2(-1, -1), new Vector2(1, -1), new Vector2(1, 1), new Vector2(-1, 1) };
        int placed = 0, guard = 0;
        while (placed < count && guard++ < count * 400)
        {
            Vector2 t; float w;
            if (R() < bulgeShare)
            {
                // bulge: gaussian around the centre (ToonSky's bulge is exp(-r^2 * 28))
                float a = R() * Mathf.PI * 2f, rr = Mathf.Sqrt(-Mathf.Log(Mathf.Max(R(), 1e-4f)) / 28f);
                t = new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * rr; w = 1f;
            }
            else
            {
                // arms: rejection-sample the spiral map, fading out like the sprite (smoothstep 0.6 .. 1.1 of r^2)
                t = new Vector2(R() * 2f - 1f, R() * 2f - 1f);
                float r2 = t.sqrMagnitude;
                if (r2 > 1.1f) continue;
                float arm = tex.GetPixelBilinear(t.x * 0.5f + 0.5f, t.y * 0.5f + 0.5f).r * (1f - Mathf.SmoothStep(0.6f, 1.1f, r2));
                // the map's arms are much brighter near the centre: accept anywhere on an arm (not by brightness),
                // otherwise every knot piles up in the middle
                if (R() > Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(armThreshold, armThreshold + 0.2f, arm))) continue;
                w = arm;
            }
            float core = Mathf.Clamp01(1f - t.magnitude * 1.4f);
            float bright = Mathf.Lerp(0.25f, 1f, Mathf.Pow(R(), 2.2f)) * Mathf.Lerp(0.6f, 1f, w);
            float size = Mathf.Lerp(sizeRange.x, sizeRange.y, Mathf.Pow(R(), 3f)) * Mathf.Lerp(0.7f, 1.2f, bright);
            float hash = R();
            for (int k = 0; k < 4; k++)
            {
                int v = placed * 4 + k;
                verts[v] = new Vector3(t.x, t.y, 0); corners[v] = cc[k];
                data[v] = new Vector4(size, hash, bright, core);
            }
            int b = placed * 4, ti = placed * 6;
            tris[ti] = b; tris[ti + 1] = b + 1; tris[ti + 2] = b + 2; tris[ti + 3] = b; tris[ti + 4] = b + 2; tris[ti + 5] = b + 3;
            placed++;
        }
        System.Array.Resize(ref verts, placed * 4); System.Array.Resize(ref corners, placed * 4);
        System.Array.Resize(ref data, placed * 4); System.Array.Resize(ref tris, placed * 6);
        var mesh = new Mesh { name = "SkyGalaxyStars" };
        mesh.vertices = verts; mesh.SetUVs(0, corners); mesh.SetUVs(1, data); mesh.triangles = tris;
        mesh.bounds = new Bounds(Vector3.zero, Vector3.one * 1e6f);
        string dir = System.IO.Path.GetDirectoryName(meshAssetPath);
        if (!UnityEditor.AssetDatabase.IsValidFolder(dir)) System.IO.Directory.CreateDirectory(dir);
        var existing = UnityEditor.AssetDatabase.LoadAssetAtPath<Mesh>(meshAssetPath);
        if (existing) { existing.Clear(); UnityEditor.EditorUtility.CopySerialized(mesh, existing); starMesh = existing; }
        else { UnityEditor.AssetDatabase.CreateAsset(mesh, meshAssetPath); starMesh = mesh; }
        UnityEditor.AssetDatabase.SaveAssets();
        UnityEditor.EditorUtility.SetDirty(this);
        DestroyImmediate(tex);
        Debug.Log("SkyGalaxyStars: baked " + placed + " stars");
    }
#endif
}
