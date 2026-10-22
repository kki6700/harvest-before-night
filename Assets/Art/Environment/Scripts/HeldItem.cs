using UnityEngine;

/// <summary>
/// Holds a prop in front of the camera like an item in the player's hand (first person, no hands drawn).
/// The prop trails the camera on a damped spring and tilts with turning and moving, so things inside it react
/// (LiquidWobble on a bottle reads this motion). Stays on its own layer: the liquid shader needs the main camera's
/// depth prepass, so it is not moved to the Viewmodel overlay like the basket.
/// All defaults are my own starting values.
/// </summary>
[DisallowMultipleComponent]
public class HeldItem : MonoBehaviour
{
    [Tooltip("Camera to hold the item in front of. Empty = Camera.main.")]
    public Transform viewCamera;
    [Tooltip("Item pivot relative to the camera: right, up, forward (m).")]
    public Vector3 holdOffset = new Vector3(0.13f, -0.2f, 0.38f);
    [Tooltip("Uniform scale while held.")]
    public float holdScale = 0.3f;
    [Tooltip("Extra yaw so the item shows a nicer side (deg).")]
    public float holdYaw = -15f;

    [Header("Lag (position spring)")]
    public float stiffness = 90f;
    public float damping = 12f;

    [Header("Tilt")]
    [Tooltip("Degrees of roll per deg/s of turning.")]
    public float rollPerYawRate = 0.04f;
    [Tooltip("Degrees of tilt per m/s of sideways / forward movement.")]
    public float tiltPerSpeed = 10f;
    public float maxTilt = 25f;
    public float tiltStiffness = 60f;
    public float tiltDamping = 8f;

    Vector3 _pos, _vel;
    Vector2 _tilt, _tiltVel;
    float _lastYaw;
    Vector3 _lastCamPos;
    bool _init;

    void OnEnable() => _init = false;

    void LateUpdate()
    {
        Transform cam = viewCamera != null ? viewCamera : (Camera.main != null ? Camera.main.transform : null);
        if (cam == null) return;
        float dt = Time.deltaTime;
        transform.localScale = Vector3.one * holdScale;

        Vector3 target = cam.TransformPoint(holdOffset);
        float yaw = cam.eulerAngles.y;
        if (!_init || dt <= 0f)
        {
            _pos = target; _vel = Vector3.zero; _tilt = _tiltVel = Vector2.zero;
            _lastYaw = yaw; _lastCamPos = cam.position; _init = true;
        }
        else
        {
            Vector3 acc = (target - _pos) * stiffness - _vel * damping;
            _vel += acc * dt;
            _pos += _vel * dt;

            // tilt against the motion: roll from turning, pitch/roll from moving (camera frame)
            float yawRate = Mathf.DeltaAngle(_lastYaw, yaw) / dt;
            Vector3 camVel = Quaternion.Inverse(Quaternion.Euler(0f, yaw, 0f)) * ((cam.position - _lastCamPos) / dt);
            Vector2 tiltTarget = new Vector2(camVel.z * tiltPerSpeed, -camVel.x * tiltPerSpeed - yawRate * rollPerYawRate);
            tiltTarget = Vector2.ClampMagnitude(tiltTarget, maxTilt);
            Vector2 tacc = (tiltTarget - _tilt) * tiltStiffness - _tiltVel * tiltDamping;
            _tiltVel += tacc * dt;
            _tilt += _tiltVel * dt;
            _lastYaw = yaw; _lastCamPos = cam.position;
        }

        // upright in the camera's yaw frame (a bottle is held upright, not pitched with the view), plus the sway
        transform.rotation = Quaternion.Euler(0f, yaw + holdYaw, 0f) * Quaternion.Euler(_tilt.x, 0f, _tilt.y);
        transform.position = _pos;
    }
}
