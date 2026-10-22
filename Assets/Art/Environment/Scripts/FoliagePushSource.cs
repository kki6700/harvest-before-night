using UnityEngine;

// Put on the SD cat (the player): grass using DSEWA/ToonFoliage bends away from this object within `radius`,
// and the grass wind is centred here (wind radius / fade are on the grass materials). Without this component the
// wind follows the camera.
[ExecuteAlways]
public class FoliagePushSource : MonoBehaviour
{
    static readonly int CatPush = Shader.PropertyToID("_DSEWA_CatPush");
    static readonly int WindCenter = Shader.PropertyToID("_DSEWA_WindCenter");
    public float radius = 1.2f;

    void LateUpdate()
    {
        var p = transform.position;
        Shader.SetGlobalVector(CatPush, new Vector4(p.x, p.y, p.z, radius));
        Shader.SetGlobalVector(WindCenter, new Vector4(p.x, p.y, p.z, 1f));
    }

    void OnDisable()
    {
        Shader.SetGlobalVector(CatPush, Vector4.zero);
        Shader.SetGlobalVector(WindCenter, Vector4.zero);
    }
}
