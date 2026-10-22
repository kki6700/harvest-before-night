using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// Authored cloud shapes for the ToonSky volumetric layer. A baked shape texture (Texture3D, signed distance
/// in units of the cube edge, up to 4 shapes in RGBA) is placed by the SkyCloudShape children; the sky shader
/// unions them with its procedural domes. Globals: _DSEWA_SkyShapeTex, _DSEWA_SkyShapeBox[i] (world centre,
/// edge m), _DSEWA_SkyShapeRot[i] (cos yaw, sin yaw, vertical stretch, channel + density/8),
/// _DSEWA_SkyShapeParams (count, procedural cut 0 keep .. 1 remove, lowest world y, highest world y).
/// The globals are pushed before every render, so edits show in the editor without a repaint trigger.
/// </summary>
[ExecuteAlways]
public class SkyCloudShapes : MonoBehaviour
{
    public const int MaxShapes = 16;

    public Texture3D shapeTexture;
    [Tooltip("0 = keep the procedural dome clouds as well, 1 = only the authored shapes")]
    [Range(0f, 1f)] public float removeProcedural;
    [Tooltip("Per channel (R, G, B, A): lowest / highest occupied height inside the cube, in cube-edge units " +
             "(-0.5 .. 0.5). Only used to fit the sky's march range; flat VDB clouds fill a thin slab of the cube.")]
    public Vector2[] channelExtentY = { new Vector2(-0.5f, 0.5f), new Vector2(-0.5f, 0.5f), new Vector2(-0.5f, 0.5f), new Vector2(-0.5f, 0.5f) };

    static readonly int TexId = Shader.PropertyToID("_DSEWA_SkyShapeTex");
    static readonly int BoxId = Shader.PropertyToID("_DSEWA_SkyShapeBox");
    static readonly int RotId = Shader.PropertyToID("_DSEWA_SkyShapeRot");
    static readonly int ParamsId = Shader.PropertyToID("_DSEWA_SkyShapeParams");

    readonly Vector4[] box = new Vector4[MaxShapes];
    readonly Vector4[] rot = new Vector4[MaxShapes];

    void OnEnable()
    {
        RenderPipelineManager.beginContextRendering += OnBeginRendering;
        Push();
    }

    void OnDisable()
    {
        RenderPipelineManager.beginContextRendering -= OnBeginRendering;
        Shader.SetGlobalVector(ParamsId, Vector4.zero);
    }

    void OnBeginRendering(ScriptableRenderContext ctx, System.Collections.Generic.List<Camera> cams) => Push();

    public void Push()
    {
        int n = 0;
        float minY = float.MaxValue, maxY = float.MinValue;
        if (shapeTexture != null)
        {
            foreach (var s in GetComponentsInChildren<SkyCloudShape>())
            {
                if (n >= MaxShapes) break;
                Transform t = s.transform;
                float edge = Mathf.Max(t.lossyScale.x, 1f);
                float yaw = t.eulerAngles.y * Mathf.Deg2Rad;
                box[n] = new Vector4(t.position.x, t.position.y, t.position.z, edge);
                rot[n] = new Vector4(Mathf.Cos(yaw), Mathf.Sin(yaw), Mathf.Max(t.lossyScale.y / edge, 0.05f),
                                     s.channel + Mathf.Clamp(s.density, 0f, 7.99f) / 8f);
                Vector2 ext = channelExtentY != null && s.channel < channelExtentY.Length ? channelExtentY[s.channel] : new Vector2(-0.5f, 0.5f);
                float h = edge * rot[n].z;
                minY = Mathf.Min(minY, t.position.y + ext.x * h);
                maxY = Mathf.Max(maxY, t.position.y + ext.y * h);
                n++;
            }
            Shader.SetGlobalTexture(TexId, shapeTexture);
            Shader.SetGlobalVectorArray(BoxId, box);
            Shader.SetGlobalVectorArray(RotId, rot);
        }
        Shader.SetGlobalVector(ParamsId, n > 0 ? new Vector4(n, removeProcedural, minY, maxY) : Vector4.zero);
    }
}
