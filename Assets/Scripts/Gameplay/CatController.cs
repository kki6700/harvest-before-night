using UnityEngine;
using UnityEngine.InputSystem;

/// <summary>
/// The player cat: WASD / arrow keys move relative to the camera, Shift runs.
/// Plays the SD cat's own Idle / Walk / Run states by name (the controller has no parameters).
/// Movement uses a CharacterController so the cat stays on the ground and slides along obstacles.
/// </summary>
[RequireComponent(typeof(CharacterController))]
[DefaultExecutionOrder(-50)]   // hop offset is applied before the basket follows the mouth
public class CatController : MonoBehaviour
{
    [Header("Movement")]
    public float walkSpeed = 1.8f;
    public float runSpeed = 3.4f;
    [Tooltip("Degrees per second the cat turns toward the move direction.")]
    public float turnSpeed = 720f;
    public float gravity = 20f;

    [Header("Hop (the SD walk cycle only moves the feet ~6 cm, so the cat hops instead of sliding)")]
    [Tooltip("Rig root bone moved up and down by the hop (CTRL_root).")]
    public Transform hopBone;
    [Tooltip("Ground covered by one hop when walking / running (m).")]
    public float walkHopLength = 0.42f;
    public float runHopLength = 0.75f;
    public float walkHopHeight = 0.07f;
    public float runHopHeight = 0.12f;
    [Tooltip("Squash on landing (fraction of height) and forward lean while moving (degrees).")]
    public float landSquash = 0.12f;
    public float moveLean = 8f;
    [Tooltip("Walk / run animation playback speed when syncAnimToSpeed is off.")]
    public float walkAnimSpeed = 1.3f;
    public float runAnimSpeed = 1.9f;
    [Tooltip("Play the run cycle at move speed / pawGroundSpeed so planted paws do not slide.")]
    public bool syncAnimToSpeed = true;
    [Tooltip("How fast a planted paw moves back in SDCat_Run at 1x (m/s), measured on the imported clip.")]
    public float pawGroundSpeed = 0.76f;

    [Header("References")]
    public Animator animator;
    [Tooltip("Camera the input is relative to. Empty = Camera.main.")]
    public Transform cameraTransform;

    /// <summary>Set by other systems (harvesting) to freeze the cat for a moment.</summary>
    public bool inputLocked;
    /// <summary>Set by the GameDirector before the start and after the result; kept apart from inputLocked
    /// so a harvest that finishes after the round ends cannot unlock the cat again.</summary>
    [HideInInspector] public bool gameLocked;
    /// <summary>Test hook: a non-zero value drives the cat like held movement keys (used for recording).</summary>
    [HideInInspector] public Vector2 debugInput;
    /// <summary>Test / demo hook: run instead of walk.</summary>
    [HideInInspector] public bool debugRun;

    CharacterController _cc;
    float _verticalSpeed;
    string _currentState;
    float _hopPhase;       // 0..1 within the current hop
    float _moveAmount;     // 0..1, smoothed "is moving"
    float _planarSpeed;
    bool _running;

    void Awake()
    {
        _cc = GetComponent<CharacterController>();
        if (animator == null) animator = GetComponentInChildren<Animator>();
        // the hop adds to CTRL_root after the animation writes it; if the Animator culled itself
        // (cat off screen) the offsets would pile up frame after frame, so it must always animate
        if (animator != null) animator.cullingMode = AnimatorCullingMode.AlwaysAnimate;
        if (cameraTransform == null && Camera.main != null) cameraTransform = Camera.main.transform;
        if (hopBone == null)
            foreach (var t in GetComponentsInChildren<Transform>())
                if (t.name == "CTRL_root") { hopBone = t; break; }
    }

    void LateUpdate()
    {
        if (hopBone == null) return;
        // advance the hop by distance travelled, so faster movement = faster hops (no sliding)
        float hopLength = _running ? runHopLength : walkHopLength;
        if (_planarSpeed > 0.05f) _hopPhase += _planarSpeed * Time.deltaTime / hopLength;
        else _hopPhase = Mathf.MoveTowards(_hopPhase, Mathf.Ceil(_hopPhase), Time.deltaTime * 4f);   // finish the hop and land
        float p = _hopPhase - Mathf.Floor(_hopPhase);

        float height = (_running ? runHopHeight : walkHopHeight) * _moveAmount;
        float lift = Mathf.Sin(p * Mathf.PI) * height;                                   // parabola-like arc
        float squash = Mathf.Max(0f, 1f - p / 0.18f) * landSquash * _moveAmount;      // right after landing

        // The Animator does not rewrite a bone whose curve value did not change, so an offset added
        // here would pile up frame after frame (the cat flew off to y = 30 in testing). If the bone
        // still holds exactly what we wrote last frame, start again from the clean animated pose.
        if (_hasWritten && hopBone.localPosition == _writtenPos && hopBone.localRotation == _writtenRot && hopBone.localScale == _writtenScale)
        {
            hopBone.localPosition = _basePos;
            hopBone.localRotation = _baseRot;
            hopBone.localScale = _baseScale;
        }
        _basePos = hopBone.localPosition;
        _baseRot = hopBone.localRotation;
        _baseScale = hopBone.localScale;

        hopBone.position += transform.up * lift;
        hopBone.localScale = Vector3.Scale(_baseScale, new Vector3(1f + squash * 0.5f, 1f - squash, 1f + squash * 0.5f));
        hopBone.rotation = Quaternion.AngleAxis(moveLean * _moveAmount, transform.right) * hopBone.rotation;

        _writtenPos = hopBone.localPosition;
        _writtenRot = hopBone.localRotation;
        _writtenScale = hopBone.localScale;
        _hasWritten = true;
    }

    Vector3 _basePos, _baseScale, _writtenPos, _writtenScale;
    Quaternion _baseRot, _writtenRot;
    bool _hasWritten;

    void Update()
    {
        bool locked = inputLocked || gameLocked;
        Vector2 input = locked ? Vector2.zero : ReadMoveInput();
        if (!locked && debugInput != Vector2.zero) input = debugInput;
        bool running = !locked && ((Keyboard.current != null && Keyboard.current.leftShiftKey.isPressed) || debugRun);

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

        // animation: idle / walk / run, legs patter faster than the authored cycle
        bool moving = move.sqrMagnitude >= 0.01f;
        _running = running;
        _planarSpeed = moving ? speed * move.magnitude : 0f;
        _moveAmount = Mathf.MoveTowards(_moveAmount, moving ? 1f : 0f, Time.deltaTime * 6f);
        // the dash cycle (SDCat_Run) drives walking and running. Its planted paws push the ground back at
        // pawGroundSpeed at 1x, so playing it at (move speed / pawGroundSpeed) keeps a planted paw still on
        // the ground (user: "the feet keep sliding" - fixed rates of 1.6x / 2.2x slid 2.5-3.5 times too fast)
        string state = !moving ? "SDCat_Idle" : "SDCat_Run";
        PlayState(state);
        if (animator != null)
        {
            float synced = _planarSpeed / Mathf.Max(0.05f, pawGroundSpeed);
            animator.speed = !moving ? 1f : (syncAnimToSpeed ? Mathf.Max(0.5f, synced) : (running ? runAnimSpeed : walkAnimSpeed));
        }
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
