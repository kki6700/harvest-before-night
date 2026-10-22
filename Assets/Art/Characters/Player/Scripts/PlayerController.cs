using UnityEngine;
using UnityEngine.InputSystem;

/// <summary>
/// First-person player: mouse look, WASD walk, Shift run, Space jump, gravity on a CharacterController, light head bob.
/// The body (this transform) turns left/right; the camera child only tilts up/down, at eye height.
/// Mouse: click in the Game view to lock the cursor and look around, Esc to free it; holding the right button also looks.
/// Uses the Input System directly (the project's active input handling is Input System only).
/// All defaults are my own starting values (SD alien scale: eyes at ~0.55 m).
/// </summary>
[DisallowMultipleComponent]
[RequireComponent(typeof(CharacterController))]
public class PlayerController : MonoBehaviour
{
    [Header("View")]
    [Tooltip("Camera that tilts up/down; it is kept at eye height above this object. Empty = Camera.main.")]
    public Transform viewCamera;
    public float eyeHeight = 0.55f;
    [Tooltip("Degrees per pixel of mouse movement")]
    public float mouseSensitivity = 0.12f;
    public float pitchMin = -80f;
    public float pitchMax = 80f;
    [Tooltip("Click locks the cursor (Esc frees it). Off = look only while the right mouse button is held.")]
    public bool lockCursorOnClick = true;

    [Header("Movement (m/s)")]
    public float walkSpeed = 1.6f;
    public float runSpeed = 3.0f;
    [Tooltip("How fast the speed reaches the target (m/s per second)")]
    public float acceleration = 12f;
    public float gravity = -15f;
    public float jumpHeight = 0.35f;

    [Header("Head bob")]
    public float bobHeight = 0.012f;
    [Tooltip("Steps per second at walking speed")]
    public float bobStepsPerSecond = 1.9f;

    CharacterController _cc;
    Vector3 _planar;      // horizontal velocity
    float _vertical;      // vertical velocity
    float _yaw, _pitch;
    float _bobPhase, _bob;

    public Vector3 Velocity => _planar + Vector3.up * _vertical;

    void OnEnable()
    {
        _cc = GetComponent<CharacterController>();
        if (viewCamera == null && Camera.main != null) viewCamera = Camera.main.transform;
        _yaw = transform.eulerAngles.y;
        if (viewCamera != null) _pitch = Mathf.DeltaAngle(0f, viewCamera.localEulerAngles.x);
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
        float dt = Time.deltaTime;

        // ---- look
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
        }
        transform.rotation = Quaternion.Euler(0f, _yaw, 0f);

        // ---- move
        Vector2 input = Vector2.zero;
        bool run = false, jump = false;
        if (kb != null)
        {
            input.x = (kb.dKey.isPressed ? 1f : 0f) - (kb.aKey.isPressed ? 1f : 0f);
            input.y = (kb.wKey.isPressed ? 1f : 0f) - (kb.sKey.isPressed ? 1f : 0f);
            run = kb.leftShiftKey.isPressed;
            jump = kb.spaceKey.wasPressedThisFrame;
        }
        input = Vector2.ClampMagnitude(input, 1f);
        Vector3 wish = transform.rotation * new Vector3(input.x, 0f, input.y) * (run ? runSpeed : walkSpeed);
        _planar = Vector3.MoveTowards(_planar, wish, acceleration * dt);

        bool grounded = _cc.isGrounded;
        if (grounded && _vertical < 0f) _vertical = -2f;           // keep pressed onto slopes
        if (grounded && jump) _vertical = Mathf.Sqrt(2f * -gravity * jumpHeight);
        _vertical += gravity * dt;
        _cc.Move((_planar + Vector3.up * _vertical) * dt);

        // ---- head bob (only while walking on the ground)
        float speed01 = _planar.magnitude / Mathf.Max(walkSpeed, 0.01f);
        if (grounded && speed01 > 0.1f)
        {
            _bobPhase += dt * bobStepsPerSecond * Mathf.Min(speed01, 1.6f) * Mathf.PI;
            _bob = Mathf.Abs(Mathf.Sin(_bobPhase)) * bobHeight * Mathf.Min(speed01, 1.5f);
        }
        else
        {
            _bob = Mathf.Lerp(_bob, 0f, 1f - Mathf.Exp(-10f * dt));
        }

        if (viewCamera != null)
        {
            viewCamera.localPosition = new Vector3(0f, eyeHeight + _bob, 0f);
            viewCamera.localRotation = Quaternion.Euler(_pitch, 0f, 0f);
        }
    }
}
