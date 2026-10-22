using UnityEngine;
using UnityEngine.InputSystem;

/// <summary>
/// The player cat: WASD / arrow keys move relative to the camera, Shift runs.
/// Plays the SD cat's own Idle / Walk / Run states by name (the controller has no parameters).
/// Movement uses a CharacterController so the cat stays on the ground and slides along obstacles.
/// </summary>
[RequireComponent(typeof(CharacterController))]
public class CatController : MonoBehaviour
{
    [Header("Movement")]
    public float walkSpeed = 2.2f;
    public float runSpeed = 4.2f;
    [Tooltip("Degrees per second the cat turns toward the move direction.")]
    public float turnSpeed = 720f;
    public float gravity = 20f;

    [Header("References")]
    public Animator animator;
    [Tooltip("Camera the input is relative to. Empty = Camera.main.")]
    public Transform cameraTransform;

    /// <summary>Set by other systems (harvesting, game over) to freeze the cat for a moment.</summary>
    public bool inputLocked;

    CharacterController _cc;
    float _verticalSpeed;
    string _currentState;

    void Awake()
    {
        _cc = GetComponent<CharacterController>();
        if (animator == null) animator = GetComponentInChildren<Animator>();
        if (cameraTransform == null && Camera.main != null) cameraTransform = Camera.main.transform;
    }

    void Update()
    {
        Vector2 input = inputLocked ? Vector2.zero : ReadMoveInput();
        bool running = !inputLocked && Keyboard.current != null && Keyboard.current.leftShiftKey.isPressed;

        // move direction on the ground plane, relative to where the camera looks
        Vector3 forward = cameraTransform != null ? cameraTransform.forward : Vector3.forward;
        forward.y = 0f;
        forward.Normalize();
        Vector3 right = Vector3.Cross(Vector3.up, forward);
        Vector3 move = forward * input.y + right * input.x;
        if (move.sqrMagnitude > 1f) move.Normalize();

        float speed = running ? runSpeed : walkSpeed;
        Vector3 velocity = move * speed;

        // simple gravity so the cat follows the terrain
        _verticalSpeed = _cc.isGrounded ? -1f : _verticalSpeed - gravity * Time.deltaTime;
        velocity.y = _verticalSpeed;
        _cc.Move(velocity * Time.deltaTime);

        // turn toward the move direction
        if (move.sqrMagnitude > 0.0001f)
        {
            Quaternion target = Quaternion.LookRotation(move, Vector3.up);
            transform.rotation = Quaternion.RotateTowards(transform.rotation, target, turnSpeed * Time.deltaTime);
        }

        // animation: idle / walk / run
        string state = move.sqrMagnitude < 0.01f ? "SDCat_Idle" : (running ? "SDCat_Run" : "SDCat_Walk");
        PlayState(state);
    }

    static Vector2 ReadMoveInput()
    {
        var kb = Keyboard.current;
        if (kb == null) return Vector2.zero;
        float x = 0f, y = 0f;
        if (kb.aKey.isPressed || kb.leftArrowKey.isPressed) x -= 1f;
        if (kb.dKey.isPressed || kb.rightArrowKey.isPressed) x += 1f;
        if (kb.sKey.isPressed || kb.downArrowKey.isPressed) y -= 1f;
        if (kb.wKey.isPressed || kb.upArrowKey.isPressed) y += 1f;
        return new Vector2(x, y);
    }

    void PlayState(string state)
    {
        if (animator == null || state == _currentState) return;
        animator.CrossFadeInFixedTime(state, 0.15f);
        _currentState = state;
    }
}
