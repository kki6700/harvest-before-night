using UnityEngine;

/// <summary>
/// Brush-stamp cloud: scatters brush stamps (camera-facing quads cut out by a brush alpha, DSEWA/BrushCloud) over the
/// surface of a cloud mesh, so the cloud reads as one volume painted with brush dabs.
/// Each stamp stores its centre (vertex position), corner + size + rotation (UV0), a random value (UV1) and the
/// cloud's rounded normal at that point (vertex normal) - the shader lights every dab with the whole cloud's shape,
/// so the dabs only break up the outline and the light/shadow boundary.
/// The mesh is built in memory from the seed (nothing is saved to the scene); the source mesh must be Read/Write.
/// All numbers are my own starting values (no reference values).
/// </summary>
[ExecuteAlways]
[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
public class BrushCloud : MonoBehaviour
{
    [Tooltip("Cloud shape (Read/Write enabled)")]
    public Mesh source;
    public int seed = 1;
    [Range(16, 4000)] public int stamps = 600;
    [Tooltip("Stamp size relative to the cloud's largest bounds extent")]
    [Range(0.02f, 0.6f)] public float stampSize = 0.16f;
    [Tooltip("+- random size")]
    [Range(0f, 0.9f)] public float sizeJitter = 0.45f;
    [Tooltip("Stamps sit this far inside the surface (fraction of their size): 0 = centred on the surface")]
    [Range(0f, 1f)] public float inset = 0.3f;
    [Tooltip("0 = the mesh's own normals, 1 = normals from the cloud centre (rounder, simpler light)")]
    [Range(0f, 1f)] public float spherize = 0.5f;
    [Tooltip("Fewer, smaller stamps on the underside (flat cloud bottom)")]
    [Range(0f, 1f)] public float bottomThin = 0.5f;

    [Header("Bottom streaks (flat horizontal strokes under the cloud, anime sky)")]
    [Range(0, 200)] public int streaks = 0;
    [Tooltip("Streak size relative to a stamp")]
    [Range(0.2f, 4f)] public float streakSize = 1.2f;
    [Tooltip("Width / height of a streak")]
    [Range(1f, 12f)] public float streakStretch = 5f;
    [Tooltip("Height band from the cloud bottom where streaks sit (fraction of the cloud height)")]
    [Range(0f, 0.5f)] public float streakBand = 0.15f;

    Mesh built;

    void OnEnable() => Build();
    void OnValidate() => Build();
    void OnDisable()
    {
        if (built != null) { if (Application.isPlaying) Destroy(built); else DestroyImmediate(built); built = null; }
    }

    [ContextMenu("Rebuild")]
    public void Build()
    {
        var mf = GetComponent<MeshFilter>();
        if (source == null || mf == null) return;
        if (!source.isReadable) { Debug.LogWarning($"BrushCloud: enable Read/Write on {source.name}", this); return; }

        var v = source.vertices;
        var n = source.normals;
        var tri = source.triangles;
        int triCount = tri.Length / 3;
        // area-weighted triangle picking
        var cdf = new float[triCount];
        float total = 0;
        for (int t = 0; t < triCount; t++)
        {
            Vector3 a = v[tri[t * 3]], b = v[tri[t * 3 + 1]], c = v[tri[t * 3 + 2]];
            total += Vector3.Cross(b - a, c - a).magnitude * 0.5f;
            cdf[t] = total;
        }
        Bounds bounds = source.bounds;
        Vector3 centre = bounds.center;
        float ext = Mathf.Max(bounds.extents.x, Mathf.Max(bounds.extents.y, bounds.extents.z));
        float baseSize = stampSize * ext;

        var rnd = new System.Random(seed);
        float R() => (float)rnd.NextDouble();

        int capacity = stamps + streaks;
        var pos = new Vector3[capacity * 4];
        var nrm = new Vector3[capacity * 4];
        var uv0 = new Vector4[capacity * 4];
        var uv1 = new Vector4[capacity * 4];
        var idx = new int[capacity * 6];
        Vector2[] corners = { new Vector2(-1, -1), new Vector2(1, -1), new Vector2(1, 1), new Vector2(-1, 1) };
        float maxSize = 0;
        int made = 0, guard = 0;
        while (made < stamps && guard++ < stamps * 20)
        {
            float pick = R() * total;
            int t = System.Array.BinarySearch(cdf, pick);
            if (t < 0) t = ~t;
            t = Mathf.Min(t, triCount - 1);
            int i0 = tri[t * 3], i1 = tri[t * 3 + 1], i2 = tri[t * 3 + 2];
            float r1 = Mathf.Sqrt(R()), r2 = R();
            float w0 = 1 - r1, w1 = r1 * (1 - r2), w2 = r1 * r2;
            Vector3 p = v[i0] * w0 + v[i1] * w1 + v[i2] * w2;
            Vector3 sn = (n[i0] * w0 + n[i1] * w1 + n[i2] * w2).normalized;
            Vector3 cn = Vector3.Normalize(Vector3.Lerp(sn, (p - centre).normalized, spherize));
            // underside: skip some, shrink the rest
            float down = Mathf.Clamp01(-cn.y);
            if (R() < down * bottomThin) continue;
            float size = baseSize * (1 + (R() * 2 - 1) * sizeJitter) * (1 - 0.4f * down * bottomThin);
            p -= sn * size * inset;
            AddStamp(p, cn, size, R() * Mathf.PI * 2, 1f);
        }

        // bottom streaks: long flat strokes along the underside, lit like the belly
        float bottom = bounds.min.y, height = bounds.size.y;
        guard = 0;
        int streaksMade = 0;
        while (streaksMade < streaks && guard++ < streaks * 50)
        {
            float pick = R() * total;
            int t = System.Array.BinarySearch(cdf, pick);
            if (t < 0) t = ~t;
            t = Mathf.Min(t, triCount - 1);
            int i0 = tri[t * 3], i1 = tri[t * 3 + 1], i2 = tri[t * 3 + 2];
            float r1 = Mathf.Sqrt(R()), r2 = R();
            Vector3 p = v[i0] * (1 - r1) + v[i1] * (r1 * (1 - r2)) + v[i2] * (r1 * r2);
            if (p.y > bottom + height * streakBand) continue;
            Vector3 cn = Vector3.Normalize(Vector3.Lerp((p - centre).normalized, Vector3.down, 0.5f));
            float size = baseSize * streakSize * (1 + (R() * 2 - 1) * sizeJitter * 0.5f);
            AddStamp(p, cn, size, (R() - 0.5f) * 0.06f, streakStretch * (0.7f + 0.6f * R()));
            streaksMade++;
        }

        void AddStamp(Vector3 p, Vector3 cn, float size, float angle, float stretch)
        {
            float rand = R();
            maxSize = Mathf.Max(maxSize, size * stretch);
            for (int k = 0; k < 4; k++)
            {
                int vi = made * 4 + k;
                pos[vi] = p;
                nrm[vi] = cn;
                uv0[vi] = new Vector4(corners[k].x, corners[k].y, size, angle);
                uv1[vi] = new Vector4(rand, R(), stretch, 0);
            }
            int ii = made * 6, b0 = made * 4;
            idx[ii] = b0; idx[ii + 1] = b0 + 2; idx[ii + 2] = b0 + 1;
            idx[ii + 3] = b0; idx[ii + 4] = b0 + 3; idx[ii + 5] = b0 + 2;
            made++;
        }
        System.Array.Resize(ref pos, made * 4);
        System.Array.Resize(ref nrm, made * 4);
        System.Array.Resize(ref uv0, made * 4);
        System.Array.Resize(ref uv1, made * 4);
        System.Array.Resize(ref idx, made * 6);

        if (built == null) { built = new Mesh { name = "BrushCloud (built)", hideFlags = HideFlags.DontSave }; }
        built.Clear();
        built.indexFormat = made * 4 > 65000 ? UnityEngine.Rendering.IndexFormat.UInt32 : UnityEngine.Rendering.IndexFormat.UInt16;
        built.vertices = pos;
        built.normals = nrm;
        built.SetUVs(0, uv0);
        built.SetUVs(1, uv1);
        built.triangles = idx;
        var bb = bounds;
        bb.Expand(maxSize * 2.9f);   // quads are expanded in the shader (corner x size x sqrt 2)
        built.bounds = bb;
        mf.sharedMesh = built;
    }
}
