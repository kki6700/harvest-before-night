using UnityEngine;

// Builds a round grid mesh for a DSEWA/ToonPuddle puddle and lays it on the terrain under it (each vertex at the terrain
// height plus a small lift), so the puddle follows bumps and slopes. UV = position in the disc, -1..1; the shader cuts
// the irregular water shape and the wet ring out of it. Rebuilt when moved or when a value changes in the inspector.
// Defaults are my own values.
[ExecuteAlways]
[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
public class PuddleSurface : MonoBehaviour
{
    [Tooltip("Mesh radius in metres (water + wet ring; the water itself is about 0.7 of this)")]
    public float radius = 0.8f;
    [Tooltip("Lift above the ground (m), keeps the puddle from flickering through the terrain")]
    public float lift = 0.01f;
    [Range(4, 32)] public int rings = 12;
    [Range(8, 96)] public int segments = 48;

    Mesh mesh;
    Vector3 builtPos;
    Quaternion builtRot;
    float builtScale;

    void OnEnable() { Rebuild(); }
    void OnValidate() { Rebuild(); }

    void Update()
    {
        if (transform.position != builtPos || transform.rotation != builtRot || transform.lossyScale.x != builtScale) Rebuild();
    }

    float GroundY(Vector3 world)
    {
        var t = Terrain.activeTerrain;
        if (t != null) return t.SampleHeight(world) + t.transform.position.y;
        return Physics.Raycast(world + Vector3.up * 50f, Vector3.down, out var hit, 200f) ? hit.point.y : transform.position.y;
    }

    public void Rebuild()
    {
        if (mesh == null)
        {
            mesh = new Mesh { name = "PuddleSurface" };
            mesh.hideFlags = HideFlags.DontSave;
        }
        int vCount = 1 + rings * segments;
        var verts = new Vector3[vCount];
        var uvs = new Vector2[vCount];
        var norms = new Vector3[vCount];
        var tris = new int[(segments + (rings - 1) * segments * 2) * 3];

        void Put(int idx, Vector2 d)
        {
            var world = transform.TransformPoint(new Vector3(d.x * radius, 0f, d.y * radius));
            world.y = GroundY(world) + lift;
            verts[idx] = transform.InverseTransformPoint(world);
            uvs[idx] = d;
            norms[idx] = transform.InverseTransformDirection(Vector3.up);
        }

        Put(0, Vector2.zero);
        for (int r = 1; r <= rings; r++)
            for (int s = 0; s < segments; s++)
            {
                float a = s * Mathf.PI * 2f / segments;
                Put(1 + (r - 1) * segments + s, new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * (r / (float)rings));
            }

        int k = 0;
        for (int s = 0; s < segments; s++)
        {
            tris[k++] = 0; tris[k++] = 1 + (s + 1) % segments; tris[k++] = 1 + s;
        }
        for (int r = 1; r < rings; r++)
            for (int s = 0; s < segments; s++)
            {
                int a0 = 1 + (r - 1) * segments + s, a1 = 1 + (r - 1) * segments + (s + 1) % segments;
                int b0 = a0 + segments, b1 = a1 + segments;
                tris[k++] = a0; tris[k++] = a1; tris[k++] = b0;
                tris[k++] = a1; tris[k++] = b1; tris[k++] = b0;
            }

        mesh.Clear();
        mesh.vertices = verts; mesh.uv = uvs; mesh.normals = norms; mesh.triangles = tris;
        mesh.RecalculateBounds();
        GetComponent<MeshFilter>().sharedMesh = mesh;
        var mr = GetComponent<MeshRenderer>();
        mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;

        builtPos = transform.position; builtRot = transform.rotation; builtScale = transform.lossyScale.x;
    }
}
