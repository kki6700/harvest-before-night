using UnityEngine;

/// <summary>
/// One authored cloud in the ToonSky volumetric layer (child of SkyCloudShapes).
/// The shape texture cube is centred on this transform: position = world metres, rotation = yaw only,
/// scale.x = cube edge in metres, scale.y / scale.x = vertical stretch.
/// The sky widens its march range to cover every shape, so shapes may reach above / below the cloud layer.
/// </summary>
public class SkyCloudShape : MonoBehaviour
{
    [Tooltip("Texture channel of the shape (0 R, 1 G, 2 B, 3 A) = which baked mesh")]
    [Range(0, 3)] public int channel;
    [Tooltip("Density multiplier (thin shapes such as rings need more, or the toon cut drops them)")]
    [Range(0f, 8f)] public float density = 2f;

    void OnDrawGizmos()
    {
        Gizmos.color = new Color(0.6f, 0.8f, 1f, 0.6f);
        Gizmos.matrix = Matrix4x4.TRS(transform.position, Quaternion.Euler(0, transform.eulerAngles.y, 0),
                                      new Vector3(transform.lossyScale.x, transform.lossyScale.y, transform.lossyScale.x));
        Gizmos.DrawWireCube(Vector3.zero, Vector3.one);
    }
}
