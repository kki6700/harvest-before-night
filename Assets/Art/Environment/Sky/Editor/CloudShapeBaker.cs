using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.VFX.SDF;

/// <summary>
/// Bakes up to 4 cloud meshes into one Texture3D (RGBAHalf) for SkyCloudShapes: channel i = signed distance of
/// object i, in units of the cube edge (negative inside). Each object (all its child meshes, in the object's
/// local space) is centred in its own cube with padding. Uses the VFX Graph MeshToSDFBaker.
/// Menu: select 1-4 objects in the Hierarchy / Project -> DSEWA/Sky/Bake Cloud Shapes.
/// </summary>
public static class CloudShapeBaker
{
    const string Folder = "Assets/Art/Environment/Sky/CloudShapes";

    [MenuItem("DSEWA/Sky/Bake Cloud Shapes (selected, max 4)")]
    static void BakeSelected()
    {
        var objs = Selection.gameObjects;
        if (objs.Length == 0 || objs.Length > 4) { Debug.LogError("Select 1-4 objects with meshes."); return; }
        string path = EditorUtility.SaveFilePanelInProject("Cloud shape texture", "T_CloudShapes", "asset", "", Folder);
        if (!string.IsNullOrEmpty(path)) Bake(objs, 96, path);
    }

    public static Texture3D Bake(GameObject[] objects, int resolution, string assetPath, float padding = 0.12f)
    {
        int res = resolution;
        var data = new ushort[res * res * res * 4];
        ushort outside = Mathf.FloatToHalf(1f);
        for (int i = 0; i < data.Length; i++) data[i] = outside;

        for (int ch = 0; ch < objects.Length && ch < 4; ch++)
        {
            Mesh mesh = Combine(objects[ch]);
            if (mesh == null) { Debug.LogError(objects[ch].name + ": no mesh"); continue; }
            Bounds b = mesh.bounds;
            float edge = Mathf.Max(b.size.x, Mathf.Max(b.size.y, b.size.z)) * (1f + padding * 2f);
            var baker = new MeshToSDFBaker(Vector3.one * edge, b.center, res, mesh, 3, 0.5f, 0f);
            baker.BakeSDF();
            RenderTexture rt = baker.SdfTexture;
            float[] sdf = Read3D(rt);
            if (rt.width != res || rt.height != res || rt.volumeDepth != res)
                Debug.LogWarning($"{objects[ch].name}: SDF is {rt.width}x{rt.height}x{rt.volumeDepth}, expected {res}^3");
            else FixInsideDepth(sdf, res);
            // MeshToSDFBaker stores distances normalised by the largest box side -> already in cube-edge units
            for (int z = 0; z < res && z < rt.volumeDepth; z++)
            for (int y = 0; y < res && y < rt.height; y++)
            for (int x = 0; x < res && x < rt.width; x++)
                data[((z * res + y) * res + x) * 4 + ch] = Mathf.FloatToHalf(sdf[(z * rt.height + y) * rt.width + x]);
            baker.Dispose();
            Object.DestroyImmediate(mesh);
        }

        return Save(data, res, assetPath);
    }

    /// <summary>
    /// Density volumes (e.g. VDB clouds converted by Tools/CloudVDB/vdb_to_raw.py: float32 res^3, x fastest,
    /// already centred in a padded cube) -> signed distance per channel. inside = density > threshold
    /// (after a light blur so single wisps do not make specks); distance = exact EDT both ways
    /// (smoothSdf: one more box blur against voxel steps, but it rounds the puffs away).
    /// </summary>
    public static Texture3D BakeFromDensity(string[] rawPaths, int res, float threshold, string assetPath, bool smoothSdf = false)
    {
        int count = res * res * res;
        var data = new ushort[count * 4];
        ushort outside = Mathf.FloatToHalf(1f);
        for (int i = 0; i < data.Length; i++) data[i] = outside;
        for (int ch = 0; ch < rawPaths.Length && ch < 4; ch++)
        {
            byte[] bytes = System.IO.File.ReadAllBytes(rawPaths[ch]);
            if (bytes.Length != count * 4) { Debug.LogError($"{rawPaths[ch]}: expected {res}^3 float32"); continue; }
            var dens = new float[count];
            System.Buffer.BlockCopy(bytes, 0, dens, 0, bytes.Length);
            dens = Blur(dens, res);
            var fIn = new float[count]; var fOut = new float[count];
            for (int i = 0; i < count; i++) { bool inside = dens[i] > threshold; fIn[i] = inside ? 1e10f : 0f; fOut[i] = inside ? 0f : 1e10f; }
            EDT3D(fIn, res);   // inside voxels: squared distance to the nearest outside voxel
            EDT3D(fOut, res);  // outside voxels: squared distance to the nearest inside voxel
            var sdf = new float[count];
            for (int i = 0; i < count; i++)
                sdf[i] = (dens[i] > threshold ? -(Mathf.Sqrt(fIn[i]) - 0.5f) : Mathf.Sqrt(fOut[i]) - 0.5f) / res;
            if (smoothSdf) sdf = Blur(sdf, res);   // off by default: it rounds away the puff detail
            for (int i = 0; i < count; i++) data[i * 4 + ch] = Mathf.FloatToHalf(sdf[i]);
        }
        return Save(data, res, assetPath);
    }

    static Texture3D Save(ushort[] data, int res, string assetPath)
    {
        var tex = new Texture3D(res, res, res, TextureFormat.RGBAHalf, false)
        { wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear };
        tex.SetPixelData(data, 0);
        tex.Apply(false, false);
        if (!AssetDatabase.IsValidFolder(Folder)) AssetDatabase.CreateFolder("Assets/Art/Environment/Sky", "CloudShapes");
        var existing = AssetDatabase.LoadAssetAtPath<Texture3D>(assetPath);
        if (existing != null) { EditorUtility.CopySerialized(tex, existing); Object.DestroyImmediate(tex); tex = existing; EditorUtility.SetDirty(tex); }
        else AssetDatabase.CreateAsset(tex, assetPath);
        AssetDatabase.SaveAssets();
        return tex;
    }

    // separable 3-tap box blur (clamped edges)
    static float[] Blur(float[] src, int n)
    {
        var a = (float[])src.Clone(); var b = new float[a.Length];
        for (int axis = 0; axis < 3; axis++)
        {
            int stride = axis == 0 ? 1 : axis == 1 ? n : n * n;
            for (int z = 0; z < n; z++)
            for (int y = 0; y < n; y++)
            for (int x = 0; x < n; x++)
            {
                int i = (z * n + y) * n + x;
                int c = axis == 0 ? x : axis == 1 ? y : z;
                float l = c > 0 ? a[i - stride] : a[i], r = c < n - 1 ? a[i + stride] : a[i];
                b[i] = (l + a[i] + r) / 3f;
            }
            var t = a; a = b; b = t;
        }
        return a;
    }

    static float[] Read3D(RenderTexture rt)
    {
        var req = AsyncGPUReadback.Request(rt, 0, 0, rt.width, 0, rt.height, 0, rt.volumeDepth, TextureFormat.RFloat);
        req.WaitForCompletion();
        if (req.hasError) { Debug.LogError("SDF readback failed"); return new float[rt.width * rt.height * rt.volumeDepth]; }
        var outData = new float[rt.width * rt.height * rt.volumeDepth];
        int slice = rt.width * rt.height;
        for (int z = 0; z < rt.volumeDepth; z++)
            System.Array.Copy(req.GetData<float>(z).ToArray(), 0, outData, z * slice, slice);
        return outData;
    }

    // Overlapping blobs (spheres pushed into each other) keep their inner faces, and the baker measures the
    // distance to ANY triangle -> the inside of a union reads far too shallow. Outside values are right (the inner
    // faces are hidden inside). Inside: depth = Euclidean distance to the nearest outside voxel (exact EDT,
    // Felzenszwalb), never less than the baked value (which is exact near the outer surface).
    static void FixInsideDepth(float[] sdf, int n)
    {
        int count = n * n * n;
        var f = new float[count];
        for (int i = 0; i < count; i++) f[i] = sdf[i] < 0 ? 1e10f : 0f;   // distance to an outside voxel
        EDT3D(f, n);
        for (int i = 0; i < count; i++)
        {
            if (sdf[i] >= 0) continue;
            float depth = (Mathf.Sqrt(f[i]) - 0.5f) / n;          // voxels -> cube-edge units
            sdf[i] = -Mathf.Max(-sdf[i], depth);
        }
    }

    // in place: f = 0 at feature voxels, large elsewhere -> squared distance (voxels) to the nearest feature
    static void EDT3D(float[] f, int n)
    {
        var line = new float[n]; var outLine = new float[n]; var v = new int[n]; var z = new float[n + 1];
        for (int axis = 0; axis < 3; axis++)
        {
            int stride = axis == 0 ? 1 : axis == 1 ? n : n * n;
            for (int a = 0; a < n; a++)
            for (int b = 0; b < n; b++)
            {
                int start = axis == 0 ? (a * n + b) * n : axis == 1 ? a * n * n + b : a * n + b;
                for (int i = 0; i < n; i++) line[i] = f[start + i * stride];
                EDT1D(line, outLine, v, z, n);
                for (int i = 0; i < n; i++) f[start + i * stride] = outLine[i];
            }
        }
    }

    // squared distance transform of a sampled function (Felzenszwalb & Huttenlocher)
    static void EDT1D(float[] fIn, float[] d, int[] v, float[] z, int n)
    {
        int k = 0; v[0] = 0; z[0] = float.NegativeInfinity; z[1] = float.PositiveInfinity;
        for (int q = 1; q < n; q++)
        {
            float s = ((fIn[q] + q * q) - (fIn[v[k]] + v[k] * v[k])) / (2f * q - 2f * v[k]);
            while (s <= z[k])
            {
                k--;
                s = ((fIn[q] + q * q) - (fIn[v[k]] + v[k] * v[k])) / (2f * q - 2f * v[k]);
            }
            k++; v[k] = q; z[k] = s; z[k + 1] = float.PositiveInfinity;
        }
        k = 0;
        for (int q = 0; q < n; q++)
        {
            while (z[k + 1] < q) k++;
            d[q] = (q - v[k]) * (q - v[k]) + fIn[v[k]];
        }
    }

    // all meshes under the object, in the object's local space
    static Mesh Combine(GameObject root)
    {
        var list = new List<CombineInstance>();
        Matrix4x4 toLocal = root.transform.worldToLocalMatrix;
        foreach (var mf in root.GetComponentsInChildren<MeshFilter>())
        {
            if (mf.sharedMesh == null) continue;
            for (int s = 0; s < mf.sharedMesh.subMeshCount; s++)
                list.Add(new CombineInstance { mesh = mf.sharedMesh, subMeshIndex = s, transform = toLocal * mf.transform.localToWorldMatrix });
        }
        if (list.Count == 0) return null;
        var m = new Mesh { indexFormat = IndexFormat.UInt32 };
        m.CombineMeshes(list.ToArray(), true, true);
        m.RecalculateBounds();
        return m;
    }
}
