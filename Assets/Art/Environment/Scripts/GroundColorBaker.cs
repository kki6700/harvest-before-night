using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
#if UNITY_EDITOR
using UnityEditor;
#endif

/// <summary>
/// RVT stand-in, step ① (Notion grass page §8-9): renders the ground's colour from straight above into one
/// texture and publishes it as globals, so ToonFoliage can blend its roots into the ground under it.
/// Area = <see cref="size"/> (world XZ) centred on this transform. Sources need a "GroundColorBake" pass.
/// Globals: _DSEWA_GroundColor (sRGB, alpha = covered) and _DSEWA_GroundColorRect = (minX, minZ, 1/sizeX, 1/sizeZ);
/// rect.z == 0 means no ground colour (foliage keeps its own root colour). _DSEWA_GroundShadowColor = the first
/// source material's _ShadowColor, so roots in shadow match the ground's shadow.
/// Terrains: a Terrain can't be drawn with DrawRenderer, so its material's "GroundColorBake" pass (DSEWA/ToonTerrain)
/// is drawn on a flat quad over the terrain with the terrain's splat map, layer textures and mask maps bound by hand.
///
/// Grass coverage (both-sides blend at grass / bare ground borders, like UE's RVT-driven landscape grass):
/// the first terrain's detail layers are summed, normalised by <see cref="coverageFullDensity"/> and blurred over
/// <see cref="coverageBlurMeters"/> into _DSEWA_GrassCoverage (R8, covers the whole terrain,
/// _DSEWA_GrassCoverageRect = (minX, minZ, 1/sizeX, 1/sizeZ), z == 0 = off). ToonTerrain darkens the ground towards
/// the grass roots near grass, ToonFoliage makes clumps at patch edges shorter. Rebuilt when the terrain's detail
/// data changes (editor dirty count) or the settings change.
///
/// Failure handling: anything that would give the foliage a wrong or stale texture (no graphics device, lost or
/// invalid render target, no drawable source, an exception while baking) turns the ground colour off
/// (rect.z = 0) so the grass falls back to its own root colour instead of sampling garbage. Each distinct problem is
/// logged once, not every frame, and a later successful bake clears it.
/// </summary>
[ExecuteAlways]
public class GroundColorBaker : MonoBehaviour
{
    public Renderer[] sources;
    public Terrain[] terrains;
    public Vector2 size = new Vector2(20f, 20f);
    public int resolution = 1024;
    [Tooltip("Re-bake every frame (editor look-dev). Turn off for a static level and call Bake() when the ground changes.")]
    public bool bakeEveryFrame = true;

    [Header("Grass coverage (soft grass / ground borders)")]
    public bool bakeGrassCoverage = true;
    [Tooltip("Detail instances per cell that count as full grass")]
    [Min(0.1f)] public float coverageFullDensity = 4f;
    [Tooltip("Blur radius in metres: how far the border blend reaches into the grass and onto the ground")]
    [Range(0f, 8f)] public float coverageBlurMeters = 1.5f;

    const string PassName = "GroundColorBake";
    const int MinResolution = 16;
    const int TerrainLayersPerPass = 4;   // _Control RGBA = 4 layers; ToonTerrain has no add pass
    static readonly int TexId = Shader.PropertyToID("_DSEWA_GroundColor");
    static readonly int RectId = Shader.PropertyToID("_DSEWA_GroundColorRect");
    static readonly int GroundShadowId = Shader.PropertyToID("_DSEWA_GroundShadowColor");
    static readonly int ShadowColorId = Shader.PropertyToID("_ShadowColor");
    static readonly int GroundLitId = Shader.PropertyToID("_DSEWA_GroundLitColor");
    static readonly int GroundLightId = Shader.PropertyToID("_DSEWA_GroundLight");
    static readonly int LitColorId = Shader.PropertyToID("_LitColor");
    static readonly int ThresholdId = Shader.PropertyToID("_Threshold");
    static readonly int SoftnessId = Shader.PropertyToID("_Softness");
    static readonly int AmbientId = Shader.PropertyToID("_AmbientShade");

    static readonly int ControlId = Shader.PropertyToID("_Control");
    static readonly int[] SplatIds = { Shader.PropertyToID("_Splat0"), Shader.PropertyToID("_Splat1"), Shader.PropertyToID("_Splat2"), Shader.PropertyToID("_Splat3") };
    static readonly int[] SplatStIds = { Shader.PropertyToID("_Splat0_ST"), Shader.PropertyToID("_Splat1_ST"), Shader.PropertyToID("_Splat2_ST"), Shader.PropertyToID("_Splat3_ST") };
    static readonly int CoverageTexId = Shader.PropertyToID("_DSEWA_GrassCoverage");
    static readonly int CoverageRectId = Shader.PropertyToID("_DSEWA_GrassCoverageRect");
    static readonly int[] MaskIds = { Shader.PropertyToID("_Mask0"), Shader.PropertyToID("_Mask1"), Shader.PropertyToID("_Mask2"), Shader.PropertyToID("_Mask3") };

    RenderTexture rt;
    CommandBuffer cmd;
    Mesh unitQuad;                 // XZ 0..1, uv = xz
    MaterialPropertyBlock terrainProps;
    readonly HashSet<string> reported = new HashSet<string>();   // problems already logged (log once, not per frame)
    bool lastBakeOk;
    Texture2D coverageTex;
    int coverageStamp = int.MinValue;   // detects detail / settings changes so the CPU blur only reruns when needed

    /// <summary>True when the last bake published a valid ground colour texture.</summary>
    public bool IsValid => lastBakeOk && rt != null && rt.IsCreated();

    void OnEnable()
    {
#if UNITY_EDITOR
        AssemblyReloadEvents.beforeAssemblyReload += ReleaseResources;
#endif
        Bake();
    }

    void Update()
    {
        // re-bake when asked every frame, or when the target was lost (device reset, scene / domain reload)
        if (bakeEveryFrame || !IsValid) Bake();
    }

#if UNITY_EDITOR
    void OnValidate()
    {
        // rendering inside OnValidate is not allowed (it runs during serialisation) -> bake on the next editor tick
        EditorApplication.delayCall -= DelayedBake;
        EditorApplication.delayCall += DelayedBake;
    }

    void DelayedBake()
    {
        if (this != null && isActiveAndEnabled) Bake();
    }
#endif

    void OnDisable()
    {
#if UNITY_EDITOR
        AssemblyReloadEvents.beforeAssemblyReload -= ReleaseResources;
        EditorApplication.delayCall -= DelayedBake;
#endif
        ReleaseResources();
    }

    static void PublishNoCoverage()
    {
        Shader.SetGlobalVector(CoverageRectId, Vector4.zero);
        Shader.SetGlobalTexture(CoverageTexId, Texture2D.blackTexture);
    }

    /// <summary>Turns the ground colour off for every foliage shader (they keep their own root colour).</summary>
    static void PublishNone()
    {
        Shader.SetGlobalVector(RectId, Vector4.zero);
        Shader.SetGlobalTexture(TexId, Texture2D.blackTexture);   // never leave a destroyed texture bound
    }

    void ReleaseResources()
    {
        PublishNone();
        PublishNoCoverage();
        DestroySafe(coverageTex);
        coverageTex = null;
        coverageStamp = int.MinValue;
        lastBakeOk = false;
        cmd?.Release();
        cmd = null;
        if (rt != null)
        {
            rt.Release();
            DestroySafe(rt);
            rt = null;
        }
        DestroySafe(unitQuad);
        unitQuad = null;
    }

    static void DestroySafe(UnityEngine.Object o)
    {
        if (o == null) return;
        if (Application.isPlaying) Destroy(o);
        else DestroyImmediate(o);
    }

    void Report(string key, string message)
    {
        if (reported.Add(key)) Debug.LogWarning($"[GroundColorBaker] {message}", this);
    }

    [ContextMenu("Bake")]
    public void Bake()
    {
        try
        {
            lastBakeOk = BakeInternal();
            if (lastBakeOk) reported.Clear();
            else PublishNone();
            UpdateCoverage();
        }
        catch (Exception e)
        {
            lastBakeOk = false;
            PublishNone();
            Report("exception:" + e.GetType().Name + e.Message, $"bake failed, grass keeps its own root colour: {e}");
        }
    }

    bool BakeInternal()
    {
        if (SystemInfo.graphicsDeviceType == GraphicsDeviceType.Null)
            return false;   // batch mode / -nographics: nothing to render into, no warning needed
        if (size.x <= 0f || size.y <= 0f || float.IsNaN(size.x) || float.IsNaN(size.y))
        {
            Report("size", $"size {size} must be positive.");
            return false;
        }
        bool hasSources = sources != null && sources.Length > 0;
        bool hasTerrains = terrains != null && terrains.Length > 0;
        if (!hasSources && !hasTerrains)
        {
            Report("empty", "no sources or terrains assigned.");
            return false;
        }
        if (!EnsureTarget()) return false;

        // Orthographic camera above the area looking straight down: view x = world +X, view y = world +Z.
        Vector3 c = transform.position;
        Matrix4x4 view = Matrix4x4.TRS(new Vector3(c.x, c.y + 500f, c.z), Quaternion.Euler(90f, 0f, 0f), new Vector3(1f, 1f, -1f)).inverse;
        Matrix4x4 proj = Matrix4x4.Ortho(-size.x * 0.5f, size.x * 0.5f, -size.y * 0.5f, size.y * 0.5f, 0.01f, 1000f);

        cmd ??= new CommandBuffer { name = "DSEWA Ground Colour Bake" };
        cmd.Clear();
        cmd.SetRenderTarget(rt);
        cmd.ClearRenderTarget(false, true, Color.clear);
        cmd.SetViewProjectionMatrices(view, proj);

        int drawn = 0;
        Material firstMat = null;
        if (hasSources) drawn += DrawSources(ref firstMat);
        if (hasTerrains) drawn += DrawTerrains(ref firstMat);
        if (drawn == 0)
        {
            Report("nothing", "none of the sources / terrains has a usable \"GroundColorBake\" pass.");
            return false;
        }

        cmd.GenerateMips(rt);
        Graphics.ExecuteCommandBuffer(cmd);

        // Shaded roots use the ground's own shadow colour, or they turn muddy next to the ground's shadow.
        Shader.SetGlobalColor(GroundShadowId, firstMat != null && firstMat.HasProperty(ShadowColorId) ? firstMat.GetColor(ShadowColorId) : Color.white);
        // Grass roots light themselves with the ground's own toon ramp and lit colour so the card base matches the ground.
        bool hasRamp = firstMat != null && firstMat.HasProperty(ThresholdId) && firstMat.HasProperty(SoftnessId)
                       && firstMat.HasProperty(AmbientId) && firstMat.HasProperty(LitColorId);
        Shader.SetGlobalColor(GroundLitId, hasRamp ? firstMat.GetColor(LitColorId) : Color.white);
        Shader.SetGlobalVector(GroundLightId, hasRamp
            ? new Vector4(firstMat.GetFloat(ThresholdId), firstMat.GetFloat(SoftnessId), firstMat.GetFloat(AmbientId), 1f)
            : Vector4.zero);
        Shader.SetGlobalTexture(TexId, rt);
        Shader.SetGlobalVector(RectId, new Vector4(c.x - size.x * 0.5f, c.z - size.y * 0.5f, 1f / size.x, 1f / size.y));
        return true;
    }

    int DrawSources(ref Material firstMat)
    {
        int drawn = 0;
        foreach (Renderer r in sources)
        {
            if (r == null) { Report("nullsource", "a source slot is empty (missing renderer)."); continue; }
            if (!r.enabled || !r.gameObject.activeInHierarchy) continue;
            Material[] mats = r.sharedMaterials;
            for (int i = 0; i < mats.Length; i++)
            {
                Material m = mats[i];
                if (m == null) { Report("nullmat:" + r.GetHashCode(), $"{r.name} has an empty material slot {i}."); continue; }
                int pass = m.FindPass(PassName);
                if (pass < 0) { Report("nopass:" + m.GetHashCode(), $"material {m.name} ({m.shader.name}) has no \"{PassName}\" pass; skipped."); continue; }
                cmd.DrawRenderer(r, m, i, pass);
                firstMat ??= m;
                drawn++;
            }
        }
        return drawn;
    }

    int DrawTerrains(ref Material firstMat)
    {
        int drawn = 0;
        foreach (Terrain t in terrains)
        {
            if (t == null) { Report("nullterrain", "a terrain slot is empty (missing terrain)."); continue; }
            if (!t.isActiveAndEnabled) continue;
            TerrainData td = t.terrainData;
            if (td == null) { Report("notd:" + t.GetHashCode(), $"terrain {t.name} has no TerrainData."); continue; }
            Material mat = t.materialTemplate;
            if (mat == null) { Report("nomat:" + t.GetHashCode(), $"terrain {t.name} has no material."); continue; }
            int pass = mat.FindPass(PassName);
            if (pass < 0) { Report("nopass:" + mat.GetHashCode(), $"terrain material {mat.name} ({mat.shader.name}) has no \"{PassName}\" pass; skipped."); continue; }
            if (td.size.x <= 0f || td.size.z <= 0f) { Report("tdsize:" + t.GetHashCode(), $"terrain {t.name} has zero size."); continue; }

            EnsureQuad();
            terrainProps ??= new MaterialPropertyBlock();
            terrainProps.Clear();

            Texture2D[] alphamaps = td.alphamapTextures;
            if (alphamaps != null && alphamaps.Length > 0 && alphamaps[0] != null)
                terrainProps.SetTexture(ControlId, alphamaps[0]);
            else
                Report("noctrl:" + t.GetHashCode(), $"terrain {t.name} has no splat map; baking layer 0 only.");

            TerrainLayer[] layers = td.terrainLayers ?? Array.Empty<TerrainLayer>();
            if (layers.Length > TerrainLayersPerPass)
                Report("layers:" + t.GetHashCode(), $"terrain {t.name} has {layers.Length} layers; only the first {TerrainLayersPerPass} are baked.");
            for (int i = 0; i < TerrainLayersPerPass && i < layers.Length; i++)
            {
                TerrainLayer layer = layers[i];
                if (layer == null || layer.diffuseTexture == null)
                {
                    Report("layer:" + t.GetHashCode() + ":" + i, $"terrain {t.name} layer {i} has no diffuse texture; it bakes grey.");
                    continue;
                }
                terrainProps.SetTexture(SplatIds[i], layer.diffuseTexture);
                // mask map B = height for the shader's height blend; without it the baked borders differ from the screen
                if (layer.maskMapTexture != null) terrainProps.SetTexture(MaskIds[i], layer.maskMapTexture);
                Vector2 tile = layer.tileSize, off = layer.tileOffset;
                if (tile.x <= 0f || tile.y <= 0f) { Report("tile:" + t.GetHashCode() + ":" + i, $"terrain {t.name} layer {i} has tile size {tile}."); tile = Vector2.one; }
                terrainProps.SetVector(SplatStIds[i], new Vector4(td.size.x / tile.x, td.size.z / tile.y, off.x / tile.x, off.y / tile.y));
            }

            Matrix4x4 m = Matrix4x4.TRS(t.GetPosition(), Quaternion.identity, new Vector3(td.size.x, 1f, td.size.z));
            cmd.DrawMesh(unitQuad, m, mat, 0, pass, terrainProps);
            firstMat ??= mat;
            drawn++;
        }
        return drawn;
    }

    // ---------------------------------------------------------------- grass coverage
    void UpdateCoverage()
    {
        Terrain t = null;
        if (bakeGrassCoverage && terrains != null)
            foreach (Terrain c in terrains) if (c != null && c.isActiveAndEnabled && c.terrainData != null) { t = c; break; }
        if (t == null) { PublishNoCoverage(); return; }
        try
        {
            TerrainData td = t.terrainData;
            int stamp = td.GetHashCode() ^ coverageFullDensity.GetHashCode() * 31 ^ coverageBlurMeters.GetHashCode() * 17 ^ td.detailWidth * 7;
#if UNITY_EDITOR
            stamp ^= EditorUtility.GetDirtyCount(td) * 486187739;   // painting details dirties the terrain data
#endif
            if (stamp != coverageStamp || coverageTex == null) { BuildCoverage(td); coverageStamp = stamp; }
            if (coverageTex == null) { PublishNoCoverage(); return; }
            Vector3 p = t.GetPosition();
            Shader.SetGlobalTexture(CoverageTexId, coverageTex);
            Shader.SetGlobalVector(CoverageRectId, new Vector4(p.x, p.z, 1f / td.size.x, 1f / td.size.z));
        }
        catch (Exception e)
        {
            PublishNoCoverage();
            Report("coverage:" + e.GetType().Name, $"grass coverage failed, borders stay hard: {e.Message}");
        }
    }

    void BuildCoverage(TerrainData td)
    {
        int w = td.detailWidth, h = td.detailHeight, layers = td.detailPrototypes.Length;
        if (w <= 0 || h <= 0 || layers == 0 || td.size.x <= 0f)
        {
            DestroySafe(coverageTex);
            coverageTex = null;
            return;
        }
        var cov = new float[w * h];
        for (int l = 0; l < layers; l++)
        {
            int[,] d = td.GetDetailLayer(0, 0, w, h, l);   // [y, x]
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++) cov[y * w + x] += d[y, x];
        }
        float inv = 1f / Mathf.Max(coverageFullDensity, 0.1f);
        for (int i = 0; i < cov.Length; i++) cov[i] = Mathf.Clamp01(cov[i] * inv);

        // three box blurs ~ a gaussian; radius in cells from metres
        int r = Mathf.RoundToInt(coverageBlurMeters / (td.size.x / w) / 1.7f);
        if (r > 0)
        {
            var tmp = new float[cov.Length];
            for (int pass = 0; pass < 3; pass++) { BoxBlur(cov, tmp, w, h, r, true); BoxBlur(tmp, cov, w, h, r, false); }
        }

        if (coverageTex == null || coverageTex.width != w || coverageTex.height != h)
        {
            DestroySafe(coverageTex);
            coverageTex = new Texture2D(w, h, TextureFormat.R8, false, true)
            {
                name = "_DSEWA_GrassCoverage",
                wrapMode = TextureWrapMode.Clamp,
                filterMode = FilterMode.Bilinear,
                hideFlags = HideFlags.HideAndDontSave,
            };
        }
        var bytes = new byte[w * h];
        for (int i = 0; i < bytes.Length; i++) bytes[i] = (byte)Mathf.RoundToInt(Mathf.Clamp01(cov[i]) * 255f);
        coverageTex.SetPixelData(bytes, 0);
        coverageTex.Apply(false, false);
    }

    // running-sum box blur along x (horizontal) or y, clamped at the borders
    static void BoxBlur(float[] src, float[] dst, int w, int h, int r, bool horizontal)
    {
        int n = horizontal ? w : h, lines = horizontal ? h : w;
        float norm = 1f / (2 * r + 1);
        for (int line = 0; line < lines; line++)
        {
            int Idx(int k) { k = Mathf.Clamp(k, 0, n - 1); return horizontal ? line * w + k : k * w + line; }
            float sum = 0f;
            for (int k = -r; k <= r; k++) sum += src[Idx(k)];
            for (int k = 0; k < n; k++)
            {
                dst[Idx(k)] = sum * norm;
                sum += src[Idx(k + r + 1)] - src[Idx(k - r)];
            }
        }
    }

    void EnsureQuad()
    {
        if (unitQuad != null) return;
        unitQuad = new Mesh { name = "GroundColorBaker Quad", hideFlags = HideFlags.HideAndDontSave };
        unitQuad.vertices = new[] { new Vector3(0, 0, 0), new Vector3(1, 0, 0), new Vector3(0, 0, 1), new Vector3(1, 0, 1) };
        unitQuad.uv = new[] { new Vector2(0, 0), new Vector2(1, 0), new Vector2(0, 1), new Vector2(1, 1) };
        unitQuad.triangles = new[] { 0, 2, 1, 1, 2, 3 };
        unitQuad.RecalculateBounds();
    }

    bool EnsureTarget()
    {
        int maxSize = Mathf.Max(MinResolution, SystemInfo.maxTextureSize);
        int res = Mathf.Clamp(resolution, MinResolution, maxSize);
        if (res != resolution) Report("res", $"resolution {resolution} is out of range, using {res} (max {maxSize}).");

        // keep the target only if it still exists on the GPU (device reset / reload can drop it)
        if (rt != null && rt.width == res && rt.IsCreated()) return true;
        if (rt != null) { rt.Release(); DestroySafe(rt); rt = null; }

        GraphicsFormat format = GraphicsFormat.R8G8B8A8_SRGB;
        if (!SystemInfo.IsFormatSupported(format, GraphicsFormatUsage.Render))
            format = GraphicsFormat.R8G8B8A8_UNorm;   // colours a little off, better than no ground blend
        rt = new RenderTexture(res, res, format, GraphicsFormat.None)
        {
            name = "_DSEWA_GroundColor",
            useMipMap = true,
            autoGenerateMips = false,
            wrapMode = TextureWrapMode.Clamp,
            filterMode = FilterMode.Bilinear,
            hideFlags = HideFlags.HideAndDontSave,
        };
        if (!rt.Create())
        {
            Report("create", $"could not create the {res}×{res} ground colour target.");
            DestroySafe(rt);
            rt = null;
            return false;
        }
        return true;
    }
}
