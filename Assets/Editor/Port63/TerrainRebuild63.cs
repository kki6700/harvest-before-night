using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

// One-off port helper: rebuilds the 6.6 binary TerrainData from the files exported to TerrainExport/,
// keeping the original asset GUID so BackGroundScene's terrain references stay intact.
public static class TerrainRebuild63
{
    const string Target = "Assets/Art/Environment/DeepBlue/TD_LookDev_DeepBlue.asset";
    const string Temp = "Assets/Art/Environment/DeepBlue/TD_Rebuild_tmp.asset";

    static Color ParseColor(string s)
    {
        var c = s.Split(',');
        return new Color(float.Parse(c[0]), float.Parse(c[1]), float.Parse(c[2]), float.Parse(c[3]));
    }

    public static void Run()
    {
        string dir = Path.Combine(Directory.GetCurrentDirectory(), "TerrainExport");
        var kv = new Dictionary<string, string>();
        var layers = new List<string>();
        var dps = new List<string>();
        foreach (var line in File.ReadAllLines(Path.Combine(dir, "terrain.txt")))
        {
            int i = line.IndexOf('='); if (i < 0) continue;
            string k = line.Substring(0, i), v = line.Substring(i + 1);
            if (k == "layer") layers.Add(v); else if (k == "dp") dps.Add(v); else kv[k] = v;
        }

        var td = new TerrainData();
        int hr = int.Parse(kv["heightmapResolution"]);
        td.heightmapResolution = hr;
        var sz = kv["size"].Split(',');
        td.size = new Vector3(float.Parse(sz[0]), float.Parse(sz[1]), float.Parse(sz[2]));
        td.baseMapResolution = int.Parse(kv["baseMapResolution"]);
        td.alphamapResolution = int.Parse(kv["alphamapResolution"]);
        td.SetDetailResolution(int.Parse(kv["detailResolution"]), int.Parse(kv["detailResolutionPerPatch"]));
        td.SetDetailScatterMode((DetailScatterMode)int.Parse(kv["detailScatterMode"]));
        var wg = kv["wavingGrass"].Split(',');
        td.wavingGrassAmount = float.Parse(wg[0]); td.wavingGrassSpeed = float.Parse(wg[1]); td.wavingGrassStrength = float.Parse(wg[2]);
        td.wavingGrassTint = new Color(float.Parse(wg[3]), float.Parse(wg[4]), float.Parse(wg[5]), float.Parse(wg[6]));
        td.enableHolesTextureCompression = bool.Parse(kv["enableHolesTextureCompression"]);

        // heights
        var h = new float[hr, hr];
        using (var r = new BinaryReader(File.OpenRead(Path.Combine(dir, "heights.bin"))))
            for (int y = 0; y < hr; y++) for (int x = 0; x < hr; x++) h[y, x] = r.ReadSingle();
        td.SetHeights(0, 0, h);

        // holes
        int hor = int.Parse(kv["holesResolution"]);
        var ho = new bool[hor, hor];
        using (var r = new BinaryReader(File.OpenRead(Path.Combine(dir, "holes.bin"))))
            for (int y = 0; y < hor; y++) for (int x = 0; x < hor; x++) ho[y, x] = r.ReadBoolean();
        td.SetHoles(0, 0, ho);

        // paint layers + splat
        var tl = new TerrainLayer[layers.Count];
        for (int i = 0; i < tl.Length; i++) tl[i] = AssetDatabase.LoadAssetAtPath<TerrainLayer>(AssetDatabase.GUIDToAssetPath(layers[i]));
        td.terrainLayers = tl;
        int ar = td.alphamapResolution, L = int.Parse(kv["alphamapLayers"]);
        var a = new float[ar, ar, L];
        using (var r = new BinaryReader(File.OpenRead(Path.Combine(dir, "alphamaps.bin"))))
            for (int y = 0; y < ar; y++) for (int x = 0; x < ar; x++) for (int l = 0; l < L; l++) a[y, x, l] = r.ReadSingle();
        td.SetAlphamaps(0, 0, a);

        // detail prototypes + layers
        var protos = new DetailPrototype[dps.Count];
        for (int i = 0; i < protos.Length; i++)
        {
            var f = dps[i].Split('|');
            protos[i] = new DetailPrototype
            {
                prototype = AssetDatabase.LoadAssetAtPath<GameObject>(AssetDatabase.GUIDToAssetPath(f[0])),
                usePrototypeMesh = bool.Parse(f[1]), useInstancing = bool.Parse(f[2]), renderMode = (DetailRenderMode)int.Parse(f[3]),
                minWidth = float.Parse(f[4]), maxWidth = float.Parse(f[5]), minHeight = float.Parse(f[6]), maxHeight = float.Parse(f[7]),
                noiseSeed = int.Parse(f[8]), noiseSpread = float.Parse(f[9]), density = float.Parse(f[10]), holeEdgePadding = float.Parse(f[11]),
                healthyColor = ParseColor(f[12]), dryColor = ParseColor(f[13]), useDensityScaling = bool.Parse(f[14]),
                alignToGround = float.Parse(f[15]), positionJitter = float.Parse(f[16]), targetCoverage = float.Parse(f[17]),
            };
        }
        td.detailPrototypes = protos;
        int dr = td.detailResolution;
        for (int i = 0; i < protos.Length; i++)
        {
            var d = new int[dr, dr];
            using (var r = new BinaryReader(File.OpenRead(Path.Combine(dir, "detail" + i + ".bin"))))
                for (int y = 0; y < dr; y++) for (int x = 0; x < dr; x++) d[y, x] = r.ReadInt32();
            td.SetDetailLayer(0, 0, i, d);
        }

        // write under a temp path, then swap the file under the original .meta (keeps the GUID)
        AssetDatabase.CreateAsset(td, Temp);
        AssetDatabase.SaveAssets();
        string root = Directory.GetCurrentDirectory();
        File.Copy(Path.Combine(root, Temp), Path.Combine(root, Target), true);
        AssetDatabase.DeleteAsset(Temp);
        AssetDatabase.ImportAsset(Target, ImportAssetOptions.ForceUpdate);

        var check = AssetDatabase.LoadAssetAtPath<TerrainData>(Target);
        check.name = Path.GetFileNameWithoutExtension(Target);
        EditorUtility.SetDirty(check);
        AssetDatabase.SaveAssets();
        long total = 0;
        for (int i = 0; i < check.detailPrototypes.Length; i++)
        {
            var d = check.GetDetailLayer(0, 0, check.detailResolution, check.detailResolution, i);
            foreach (var v in d) total += v;
        }
        Debug.Log("TerrainRebuild63: hm " + check.heightmapResolution + " size " + check.size + " layers " + check.terrainLayers.Length
                  + " protos " + check.detailPrototypes.Length + " detailTotal " + total + " h(256,256) " + check.GetHeight(256, 256));
    }
}
