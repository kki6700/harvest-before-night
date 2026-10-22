using UnityEngine;

/// <summary>
/// Parent of the mesh clouds (DSEWA/ToonCloudMesh). The clouds sit at real scale km away and the shader shrinks
/// them towards the camera, but Unity culls by the real bounds (beyond the far plane) -> every child renderer gets
/// a huge world-bounds override so it is never culled. Also turns shadow casting / receiving off.
/// </summary>
[ExecuteAlways]
public class CloudMeshGroup : MonoBehaviour
{
    [Tooltip("Size of the bounds override (m). Must contain the camera frustum wherever the camera goes")]
    public float boundsSize = 100000f;

    void OnEnable() => Refresh();
    void OnTransformChildrenChanged() => Refresh();

    [ContextMenu("Refresh")]
    public void Refresh()
    {
        foreach (var r in GetComponentsInChildren<MeshRenderer>(true))
        {
            r.bounds = new Bounds(Vector3.zero, Vector3.one * boundsSize);
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.receiveShadows = false;
        }
    }

    void OnDisable()
    {
        foreach (var r in GetComponentsInChildren<MeshRenderer>(true)) r.ResetBounds();
    }
}
