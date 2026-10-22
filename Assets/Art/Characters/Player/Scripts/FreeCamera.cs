using UnityEngine;
using UnityEngine.InputSystem;

/// <summary>
/// Free-fly camera for walking the scene in Play mode (no body, no gravity, no collision).
/// Mouse: click in the Game view to lock the cursor and look around, Esc to free it; holding the right button also looks.
/// WASD = move along the view, E / Space = up, Q / Ctrl = down, Shift = fast, mouse wheel = change the base speed.
/// Uses the Input System directly (the project's active input handling is Input System only).
/// All defaults are my own starting values.
/// </summary>
[DisallowMultipleComponent]
public class FreeCamera : MonoBehaviour
{
    [Header("Look")]
    [Tooltip("Degrees per pixel of mouse movement")]
    public float mouseSensitivity = 0.12f;
    public float pitchMin = -85f;
    public float pitchMax = 85f;
    [Tooltip("Click locks the cursor (Esc frees it). Off = look only while the right mouse button is held.")]
    public bool lockCursorOnClick = true;

    [Header("Move (m/s)")]
    public float speed = 1.5f;
    public float fastMultiplier = 3f;
    [Tooltip("Smoothing of starts and stops (higher = snappier)")]
    public float smoothing = 10f;
    public float minSpeed = 0.2f;
    public float maxSpeed = 20f;

    float _yaw, _pitch;
    Vector3 _velocity;

    void OnEnable()
    {
        Vector3 e = transform.eulerAngles;
        _yaw = e.y;
        _pitch = Mathf.DeltaAngle(0f, e.x);
    }

    void OnDisable()
    {
        Cursor.lockState = CursorLockMode.None;
        Cursor.visible = true;
    }

    void Update()
    {
        var kb = Keyboard.current;
        var mouse = Mouse.current;
        float dt = Time.unscaledDeltaTime;

        if (mouse != null)
        {
            if (lockCursorOnClick && mouse.leftButton.wasPressedThisFrame && Cursor.lockState != CursorLockMode.Locked)
            {
                Cursor.lockState = CursorLockMode.Locked;
                Cursor.visible = false;
            }
            if (kb != null && kb.escapeKey.wasPressedThisFrame)
            {
                Cursor.lockState = CursorLockMode.None;
                Cursor.visible = true;
            }
            if (Cursor.lockState == CursorLockMode.Locked || mouse.rightButton.isPressed)
            {
                Vector2 d = mouse.delta.ReadValue() * mouseSensitivity;
                _yaw += d.x;
                _pitch = Mathf.Clamp(_pitch - d.y, pitchMin, pitchMax);
            }
            float scroll = mouse.scroll.ReadValue().y;
            if (Mathf.Abs(scroll) > 0.01f) speed = Mathf.Clamp(speed * (scroll > 0f ? 1.2f : 1f / 1.2f), minSpeed, maxSpeed);
        }
        transform.rotation = Quaternion.Euler(_pitch, _yaw, 0f);

        Vector3 input = Vector3.zero;
        bool fast = false;
        if (kb != null)
        {
            input.x = (kb.dKey.isPressed ? 1f : 0f) - (kb.aKey.isPressed ? 1f : 0f);
            input.z = (kb.wKey.isPressed ? 1f : 0f) - (kb.sKey.isPressed ? 1f : 0f);
            input.y = (kb.eKey.isPressed || kb.spaceKey.isPressed ? 1f : 0f) - (kb.qKey.isPressed || kb.leftCtrlKey.isPressed ? 1f : 0f);
            fast = kb.leftShiftKey.isPressed;
        }
        input = Vector3.ClampMagnitude(input, 1f);
        // forward/right follow the view, up/down stay world-vertical
        Vector3 wish = (transform.rotation * new Vector3(input.x, 0f, input.z) + Vector3.up * input.y) * speed * (fast ? fastMultiplier : 1f);
        _velocity = Vector3.Lerp(_velocity, wish, 1f - Mathf.Exp(-smoothing * dt));
        transform.position += _velocity * dt;
    }
}
