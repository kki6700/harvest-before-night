using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

// Builds LF_ToonSky.asset: a soft, dreamy lens flare for the moon / sun directional light, made only of
// procedural SRP shapes (no textures):
//   at the light: a wide soft glow, a faint blurry moon-halo ring a little outside the disc
//   along the light -> screen-centre line: two very faint blurry light blobs
// No crisp polygons / rings: the first toon version (hexagon ghosts, double ring) read as too much.
// Colours follow the light colour (modulateByLightColor), so the same flare works for the moon and the sun.
// All sizes / intensities are my own starting values (no reference values). Re-run to rebuild after edits.
public static class ToonLensFlareBuilder
{
    const string Path = "Assets/Art/Environment/Sky/LF_ToonSky.asset";

    static LensFlareDataElementSRP Shape(SRPLensFlareType type, float position, float size, Color tint, float intensity,
                                         float edge, float fallOff = 1f)
    {
        return new LensFlareDataElementSRP
        {
            flareType = type,
            position = position,
            uniformScale = size,
            sizeXY = Vector2.one,
            tint = tint,
            localIntensity = intensity,
            blendMode = SRPLensFlareBlendMode.Additive,
            modulateByLightColor = true,
            edgeOffset = edge,      // large = soft, blurry edge
            fallOff = fallOff,
            autoRotate = false,
            visible = true,
        };
    }

    [MenuItem("DSEWA/Sky/Build Toon Lens Flare")]
    public static void Build()
    {
        var data = AssetDatabase.LoadAssetAtPath<LensFlareDataSRP>(Path);
        bool isNew = data == null;
        if (isNew) data = ScriptableObject.CreateInstance<LensFlareDataSRP>();

        var lavender = new Color(0.7f, 0.68f, 1f);
        var glow = Shape(SRPLensFlareType.Circle, 0f, 1.6f, lavender, 0.16f, edge: 0.95f, fallOff: 1.6f);
        var halo = Shape(SRPLensFlareType.Ring, 0f, 0.85f, new Color(0.75f, 0.85f, 1f), 0.1f, edge: 0.7f);
        halo.ringThickness = 0.14f;

        var blobA = Shape(SRPLensFlareType.Circle, 0.55f, 0.22f, new Color(0.7f, 0.65f, 1f), 0.05f, edge: 0.9f);
        var blobB = Shape(SRPLensFlareType.Circle, 1.35f, 0.38f, new Color(0.6f, 0.85f, 1f), 0.035f, edge: 0.9f);

        data.elements = new[] { glow, halo, blobA, blobB };

        if (isNew) AssetDatabase.CreateAsset(data, Path);
        EditorUtility.SetDirty(data);
        AssetDatabase.SaveAssets();
        Debug.Log("ToonLensFlareBuilder: " + Path + " elements " + data.elements.Length);
    }
}
