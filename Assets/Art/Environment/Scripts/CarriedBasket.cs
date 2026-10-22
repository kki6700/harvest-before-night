using UnityEngine;

/// <summary>
/// Hand-carried prop without rigging: keeps the grip socket on the hand transform and lets the
/// basket swing like a pendulum about that grip from the hand's motion. Fruit stays parented
/// (baked poses, no physics). Values are my own, tuned by eye on 2026-10-13.
/// </summary>
[DisallowMultipleComponent]
public class CarriedBasket : MonoBehaviour
{
    public enum Mode { HandSocket, FirstPersonView }

    [Tooltip("HandSocket: grip follows a hand bone. FirstPersonView: held with both hands in front of the camera (no hands drawn).")]
    public Mode mode = Mode.FirstPersonView;

    [Header("First-person view model")]
    [Tooltip("Camera to hold the basket in front of. Empty = Camera.main.")]
    public Transform viewCamera;
    [Tooltip("Where the grip (handle top) sits relative to the camera: right, up, forward (m), in the camera's yaw frame.")]
    public Vector3 viewOffset = new Vector3(0f, -0.05f, 0.5f);
    [Tooltip("Uniform scale of the basket while held in view (the SD eye height is ~0.55 m, the basket is 1 m wide).")]
    public float viewScale = 0.55f;
    [Range(0f, 1f)] public float followPitch = 0.35f;
    [Tooltip("Layer drawn by the overlay viewmodel camera (depth cleared, so world geometry never pokes through). Empty = leave layers alone.")]
    public string viewmodelLayer = "Viewmodel";
    [Tooltip("Position lag spring when the camera moves or turns.")]
    public float lagStiffness = 70f;
    public float lagDamping = 10f;
    [Tooltip("Roll from turning (deg per deg/s of yaw rate) and pitch from vertical motion (deg per m/s).")]
    public float rollPerYawRate = 0.03f;
    public float pitchPerVerticalSpeed = 6f;

    [Header("Hand socket")]
    [Tooltip("Hand bone (or any transform) the grip follows. Leave empty to keep the basket where it is.")]
    public Transform hand;
    [Tooltip("Child transform at the top of the handle where the hand holds the basket.")]
    public Transform grip;
    [Tooltip("Character root used for facing and the sideways offset. Empty = hand.root.")]
    public Transform characterRoot;
    [Tooltip("Push the basket out from the body along the character's right axis (m). Negative for the left hand.")]
    public float sideOffset = 0.28f;
    [Tooltip("Yaw of the handle arch relative to the character's facing. 90 = arch runs front-to-back beside the leg.")]
    public float handleYaw = 90f;
    [Tooltip("Animator layer (on the character) with the arm 'holding a basket' pose; set to weight 1 while this basket is held. Empty = none.")]
    public string holdPoseLayer = "BasketHold";
    [Tooltip("Optional second animator layer for the free arm (e.g. lifted just clear of a flared coat), and its weight; below 1 keeps part of the walk swing.")]
    public string freeArmLayer = "BasketHoldR";
    [Range(0f, 1f)] public float freeArmWeight = 0.7f;
    [Tooltip("Scales both arm layers (0..1). A pick-up script ramps it up while the character stands up.")]
    [Range(0f, 1f)] public float holdPoseBlend = 1f;

    [Header("Swing (pendulum about the grip)")]
    [Range(0f, 1f)] public float swayAmount = 0.35f;
    [Tooltip("Degrees of tilt per m/s of hand speed.")]
    public float tiltPerSpeed = 12f;
    public float maxTilt = 18f;
    [Tooltip("Spring stiffness and damping of the swing.")]
    public float stiffness = 40f;
    public float damping = 6f;

    Vector3 _lastHandPos;
    Vector2 _tilt;      // x = pitch (forward/back), y = roll (sideways), degrees
    Vector2 _tiltVel;
    bool _hasLast;
    Vector3 _lagPos, _lagVel;
    float _lastYaw;
    Vector3 _lastCamPos;
    bool _viewInit;

    void OnValidate()
    {
        if (grip == null)
        {
            var g = transform.Find("GripSocket");
            if (g != null) grip = g;
        }
    }

    void OnEnable()
    {
        SetHoldPose(holdPoseBlend);
        if (mode != Mode.FirstPersonView || string.IsNullOrEmpty(viewmodelLayer)) return;
        int layer = LayerMask.NameToLayer(viewmodelLayer);
        if (layer < 0) return;
        foreach (var t in GetComponentsInChildren<Transform>(true)) t.gameObject.layer = layer;
    }

    void OnDisable() => SetHoldPose(0f);

    // the arm pose lives on the character's animator (avatar-masked layer), so characters without a basket keep
    // their normal arm swing; only the holder's layer is switched on
    Animator _holder;
    void SetHoldPose(float weight)
    {
        if (mode != Mode.HandSocket || hand == null || string.IsNullOrEmpty(holdPoseLayer)) return;
        if (_holder == null)
        {
            Transform root = characterRoot != null ? characterRoot : hand.root;
            _holder = root.GetComponentInChildren<Animator>();
        }
        if (_holder == null || _holder.runtimeAnimatorController == null) return;
        SetLayer(holdPoseLayer, weight);
        SetLayer(freeArmLayer, weight * freeArmWeight);
    }

    void SetLayer(string name, float weight)
    {
        if (string.IsNullOrEmpty(name)) return;
        int layer = _holder.GetLayerIndex(name);
        if (layer >= 0 && !Mathf.Approximately(_holder.GetLayerWeight(layer), weight)) _holder.SetLayerWeight(layer, weight);
    }

    void LateUpdate()
    {
        if (grip == null) return;
        float dt = Time.deltaTime;
        if (dt <= 0f) return;
        if (mode == Mode.FirstPersonView) { FirstPersonStep(dt); return; }
        if (hand == null) return;
        SetHoldPose(holdPoseBlend);   // the animator resets layer weights when it rebinds

        Transform root = characterRoot != null ? characterRoot : hand.root;
        Quaternion facing = Quaternion.Euler(0f, root.eulerAngles.y, 0f);

        // grip point: the hand, pushed sideways so the basket hangs beside the leg instead of through it
        Vector3 handPos = hand.position + facing * Vector3.right * sideOffset;

        // hand velocity in the character's frame -> target tilt (the basket lags behind the motion)
        Vector3 vel = _hasLast ? (handPos - _lastHandPos) / dt : Vector3.zero;
        _lastHandPos = handPos; _hasLast = true;
        Vector3 local = Quaternion.Inverse(facing) * vel;
        Vector2 target = new Vector2(-local.z, local.x) * tiltPerSpeed * swayAmount;
        target = Vector2.ClampMagnitude(target, maxTilt);

        // damped spring toward the target tilt
        Vector2 acc = (target - _tilt) * stiffness - _tiltVel * damping;
        _tiltVel += acc * dt;
        _tilt += _tiltVel * dt;

        // rotation about the grip: yaw follows the character (arch front-to-back), tilt is the swing
        Quaternion swing = Quaternion.Euler(_tilt.x, 0f, _tilt.y);
        Quaternion rot = facing * Quaternion.Euler(0f, handleYaw, 0f) * swing;
        Vector3 gripLocal = transform.InverseTransformPoint(grip.position);   // grip offset in basket space
        transform.rotation = rot;
        transform.position = handPos - rot * Vector3.Scale(gripLocal, transform.lossyScale);
    }

    /// <summary>Both hands on the handle, basket held low in front of the camera; it lags and tilts with the camera motion.</summary>
    void FirstPersonStep(float dt)
    {
        Transform cam = viewCamera != null ? viewCamera : (Camera.main != null ? Camera.main.transform : null);
        if (cam == null) return;
        transform.localScale = Vector3.one * viewScale;

        float yaw = cam.eulerAngles.y;
        float pitch = Mathf.DeltaAngle(0f, cam.eulerAngles.x) * followPitch;
        Quaternion frame = Quaternion.Euler(pitch, yaw, 0f);
        Vector3 target = cam.position + frame * viewOffset;

        if (!_viewInit) { _lagPos = target; _lagVel = Vector3.zero; _lastYaw = yaw; _lastCamPos = cam.position; _viewInit = true; }

        // position lag: damped spring toward the target, so the basket trails a little when moving / turning
        Vector3 acc = (target - _lagPos) * lagStiffness - _lagVel * lagDamping;
        _lagVel += acc * dt;
        _lagPos += _lagVel * dt;

        // tilt: roll against the turn, pitch from bobbing
        float yawRate = Mathf.DeltaAngle(_lastYaw, yaw) / dt; _lastYaw = yaw;
        float vSpeed = (cam.position.y - _lastCamPos.y) / dt; _lastCamPos = cam.position;
        Vector2 tiltTarget = new Vector2(-vSpeed * pitchPerVerticalSpeed, -yawRate * rollPerYawRate) * swayAmount;
        tiltTarget = Vector2.ClampMagnitude(tiltTarget, maxTilt);
        Vector2 tacc = (tiltTarget - _tilt) * stiffness - _tiltVel * damping;
        _tiltVel += tacc * dt;
        _tilt += _tiltVel * dt;

        // arch left-to-right: both hands on the handle in front of the chest
        Quaternion rot = frame * Quaternion.Euler(_tilt.x, 0f, _tilt.y);
        Vector3 gripLocal = transform.InverseTransformPoint(grip.position);
        transform.rotation = rot;
        transform.position = _lagPos - rot * Vector3.Scale(gripLocal, transform.lossyScale);
    }
}
