using System;
using UnityEngine;

/// <summary>
/// Terrain layers spawn the grass (Unreal "Landscape Grass Type" style): the detail density of each cell is computed
/// from the painted terrain-layer weights, so painting a layer (e.g. the path) also adds / removes grass.
/// count = Σ_layers remap(weight) × rule density × patch mask, dithered to whole instances.
/// Faint brush edges get fewer instances (weight remap), the bush shape comes from a world-space patch noise.
/// Edge shrinking and the darker ground under grass come from GroundColorBaker's coverage map (it re-bakes when
/// the details change). Painting the terrain texture regenerates that region automatically (auto update);
/// hand-painted details inside the spawn area are overwritten.
/// </summary>
[ExecuteAlways]
[RequireComponent(typeof(Terrain))]
public class LayerGrassSpawner : MonoBehaviour
{
    [Serializable]
    public class LayerRule
    {
        public TerrainLayer layer;
        [Tooltip("Max instances of each detail prototype per detail cell at full layer weight (index = detail prototype)")]
        public float[] density = { 0f, 0f };
        [Tooltip("0 = uniform carpet, 1 = bushes only where the patch noise is high")]
        [Range(0f, 1f)] public float patchiness = 0.7f;
        [Tooltip("Tall prototypes (index >= 1) only grow in the dense middle of patches: mask power")]
        public float tallPatchPower = 2f;
    }

    public LayerRule[] rules = Array.Empty<LayerRule>();

    [Header("Weight remap (thin brush edges -> sparse grass)")]
    [Range(0f, 1f)] public float weightMin = 0.15f;
    [Range(0f, 1f)] public float weightMax = 0.7f;

    [Header("Patch noise (bush shapes)")]
    public float patchScale = 7f;
    [Range(0f, 1f)] public float patchThreshold = 0.45f;
    [Range(0.01f, 0.5f)] public float patchSoftness = 0.18f;
    public int seed = 7;

    [Header("Spawn area (performance)")]
    [Tooltip("World centre of the grass area")]
    public Vector3 center = Vector3.zero;
    [Tooltip("Radius in metres; 0 = whole terrain")]
    public float radius = 40f;
    [Tooltip("Width of the soft fade at the area border (metres)")]
    public float borderFade = 10f;
    [Range(1, 32)] public int maxPerCell = 16;
    [Tooltip("No grass inside these colliders' world bounds (XZ), e.g. the pool floor and walls")]
    public Collider[] excludeAreas = Array.Empty<Collider>();
    [Tooltip("No grass where the ground is lower than this world height (e.g. under the lake water). Very low = off")]
    public float excludeBelowHeight = -1000f;

    [Header("Update")]
    public bool autoUpdate = true;

    Terrain terrain;

    void OnEnable()
    {
        terrain = GetComponent<Terrain>();
        TerrainCallbacks.textureChanged += OnTextureChanged;
    }

    void OnDisable()
    {
        TerrainCallbacks.textureChanged -= OnTextureChanged;
    }

    void OnTextureChanged(Terrain t, string textureName, RectInt region, bool synced)
    {
        if (!autoUpdate || t != terrain || textureName != TerrainData.AlphamapTextureName) return;
        // alphamap region -> detail region (+1 cell margin)
        TerrainData td = t.terrainData;
        float s = (float)td.detailResolution / td.alphamapResolution;
        var r = new RectInt(Mathf.FloorToInt(region.xMin * s) - 1, Mathf.FloorToInt(region.yMin * s) - 1,
                            Mathf.CeilToInt(region.width * s) + 3, Mathf.CeilToInt(region.height * s) + 3);
        Generate(r);
    }

    [ContextMenu("Regenerate All")]
    public void GenerateAll()
    {
        if (terrain == null) terrain = GetComponent<Terrain>();
        int res = terrain.terrainData.detailResolution;
        Generate(new RectInt(0, 0, res, res));
    }

    public void Generate(RectInt region)
    {
        if (terrain == null) terrain = GetComponent<Terrain>();
        TerrainData td = terrain.terrainData;
        if (td == null || rules == null || rules.Length == 0) return;
        int res = td.detailResolution;
        int protoCount = td.detailPrototypes.Length;
        if (protoCount == 0) return;

        // clip to the terrain and, if set, to the spawn area
        int x0 = Mathf.Max(0, region.xMin), y0 = Mathf.Max(0, region.yMin);
        int x1 = Mathf.Min(res, region.xMax), y1 = Mathf.Min(res, region.yMax);
        Vector3 tp = terrain.GetPosition();
        float cell = td.size.x / res;
        if (radius > 0f)
        {
            float rr = radius + borderFade;
            x0 = Mathf.Max(x0, Mathf.FloorToInt((center.x - rr - tp.x) / cell));
            x1 = Mathf.Min(x1, Mathf.CeilToInt((center.x + rr - tp.x) / cell));
            y0 = Mathf.Max(y0, Mathf.FloorToInt((center.z - rr - tp.z) / cell));
            y1 = Mathf.Min(y1, Mathf.CeilToInt((center.z + rr - tp.z) / cell));
        }
        if (x1 <= x0 || y1 <= y0) return;
        int w = x1 - x0, h = y1 - y0;

        // layer index of each rule
        TerrainLayer[] layers = td.terrainLayers;
        var ruleLayer = new int[rules.Length];
        for (int r = 0; r < rules.Length; r++) ruleLayer[r] = rules[r].layer == null ? -1 : Array.IndexOf(layers, rules[r].layer);

        // alphamap block covering the region
        float a = (float)td.alphamapResolution / res;
        int ax0 = Mathf.Clamp(Mathf.FloorToInt(x0 * a), 0, td.alphamapWidth - 1), ay0 = Mathf.Clamp(Mathf.FloorToInt(y0 * a), 0, td.alphamapHeight - 1);
        int ax1 = Mathf.Clamp(Mathf.CeilToInt(x1 * a), ax0 + 1, td.alphamapWidth), ay1 = Mathf.Clamp(Mathf.CeilToInt(y1 * a), ay0 + 1, td.alphamapHeight);
        float[,,] alpha = td.GetAlphamaps(ax0, ay0, ax1 - ax0, ay1 - ay0);
        int aw = ax1 - ax0, ah = ay1 - ay0;

        var outLayers = new int[protoCount][,];
        for (int p = 0; p < protoCount; p++) outLayers[p] = new int[h, w];
        float ox = seed * 17.13f, oz = seed * 31.71f;

        for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++)
        {
            int dx = x0 + x, dy = y0 + y;
            float wx = tp.x + (dx + 0.5f) * cell, wz = tp.z + (dy + 0.5f) * cell;

            float area = 1f;
            if (radius > 0f)
            {
                float d = Vector2.Distance(new Vector2(wx, wz), new Vector2(center.x, center.z));
                area = 1f - Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(radius, radius + borderFade, d));
                if (area <= 0f) continue;
            }

            if (InExcludedArea(wx, wz) || terrain.SampleHeight(new Vector3(wx, 0f, wz)) + tp.y < excludeBelowHeight) { for (int p = 0; p < protoCount; p++) outLayers[p][y, x] = 0; continue; }

            // average the alphamap texels that fall in this detail cell
            int sx = Mathf.Clamp(Mathf.FloorToInt(dx * a) - ax0, 0, aw - 1), sy = Mathf.Clamp(Mathf.FloorToInt(dy * a) - ay0, 0, ah - 1);
            int ex = Mathf.Clamp(Mathf.CeilToInt((dx + 1) * a) - ax0, sx + 1, aw), ey = Mathf.Clamp(Mathf.CeilToInt((dy + 1) * a) - ay0, sy + 1, ah);

            float n = Mathf.PerlinNoise(wx / patchScale + ox, wz / patchScale + oz) * 0.7f
                    + Mathf.PerlinNoise(wx / (patchScale * 0.37f) + oz, wz / (patchScale * 0.37f) + ox) * 0.3f;
            float patch = Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(patchThreshold - patchSoftness, patchThreshold + patchSoftness, n));

            for (int p = 0; p < protoCount; p++)
            {
                float count = 0f;
                for (int r = 0; r < rules.Length; r++)
                {
                    int li = ruleLayer[r];
                    if (li < 0 || li >= td.alphamapLayers) continue;
                    LayerRule rule = rules[r];
                    float dens = p < rule.density.Length ? rule.density[p] : 0f;
                    if (dens <= 0f) continue;
                    float wsum = 0f; int nn = 0;
                    for (int yy = sy; yy < ey; yy++) for (int xx = sx; xx < ex; xx++) { wsum += alpha[yy, xx, li]; nn++; }
                    float weight = Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(weightMin, weightMax, wsum / nn));
                    float mask = Mathf.Lerp(1f, patch, rule.patchiness);
                    if (p > 0) mask = Mathf.Pow(mask, rule.tallPatchPower);
                    count += weight * dens * mask;
                }
                count *= area;
                // dither the fraction with a stable per-cell hash so regeneration is deterministic
                float hash = Frac(Mathf.Sin((dx * 12.9898f + dy * 78.233f + p * 37.719f + seed) ) * 43758.5453f);
                outLayers[p][y, x] = Mathf.Clamp(Mathf.FloorToInt(count + hash), 0, maxPerCell);
            }
        }

        for (int p = 0; p < protoCount; p++) td.SetDetailLayer(x0, y0, p, outLayers[p]);
    }

    bool InExcludedArea(float wx, float wz)
    {
        if (excludeAreas == null) return false;
        foreach (Collider c in excludeAreas)
        {
            if (c == null) continue;
            Bounds b = c.bounds;
            if (wx >= b.min.x && wx <= b.max.x && wz >= b.min.z && wz <= b.max.z) return true;
        }
        return false;
    }

    static float Frac(float v) => v - Mathf.Floor(v);
}
