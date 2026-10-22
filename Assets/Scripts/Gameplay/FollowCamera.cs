using UnityEngine;
using UnityEngine.InputSystem;

/// <summary>
/// Third-person camera that follows the cat from behind and above.
/// Hold the right mouse button and drag to orbit; the mouse wheel zooms.
/// The camera position is smoothed so it does not jitter with the walk cycle.
/// </summary>
public class FollowCamera : MonoBehaviour
{
    public Transform target;
    [Tooltip("Point on the target the camera looks at (m above its feet).")]
    public float lookHeight = 0.8f;
    public float distance = 6.5f;
    public float minDistance = 3f, maxDistance = 11f;
    [Tooltip("Pitch (degrees down) and starting yaw.")]
    public float pitch = 28f;
    public float yaw = 0f;
    public float orbitSensitivity = 0.15f;
    public float minPitch = 10f, maxPitch = 60f;
    [Tooltip("How quickly the camera catches up with the target (higher = tighter).")]
    public float followSharpness = 8f;

    Vector3 _focus;

    void Start()
    {
        if (target != null) _focus = target.position + Vector3.up * lookHeight;
    }

    void LateUpdate()
    {
        if (target == null) return;

        var mouse = Mouse.current;
        if (mouse != null)
        {
            if (mouse.rightButton.isPressed)
            {
                Vector2 delta = mouse.delta.ReadValue();
                yaw += delta.x * orbitSensitivity;
                pitch = Mathf.Clamp(pitch - delta.y * orbitSensitivity, minPitch, maxPitch);
            }
            float scroll = mouse.scroll.ReadValue().y;
            if (Mathf.Abs(scroll) > 0.01f)
                distance = Mathf.Clamp(distance - Mathf.Sign(scroll) * 0.5f, minDistance, maxDistance);
        }

        // smooth the focus point, then place the camera on a sphere around it
        Vector3 wanted = target.position + Vector3.up * lookHeight;
        _focus = Vector3.Lerp(_focus, wanted, 1f - Mathf.Exp(-followSharpness * Time.deltaTime));
        Quaternion rot = Quaternion.Euler(pitch, yaw, 0f);
        transform.position = _focus - rot * Vector3.forward * distance;
        transform.rotation = rot;
    }
}
