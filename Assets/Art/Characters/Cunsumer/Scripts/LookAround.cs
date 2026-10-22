using UnityEngine;

/// <summary>
/// Idle "look around" layered on top of any Animator clip: the character picks a new look direction every few seconds,
/// the eyes dart there first, then the head turns after them (eyes lead, head follows). Runs in LateUpdate so it adds
/// to whatever pose the Animator produced this frame. Eyes are the rigid eyeball objects parented to the Head bone
/// (origin = sphere centre, local +Z = gaze), so rotating them is the gaze.
/// </summary>
[DisallowMultipleComponent]
public class LookAround : MonoBehaviour
{
    [Header("Targets")]
    public Animator animator;
    public Transform leftEye;
    public Transform rightEye;

    [Header("Head (degrees)")]
    [Range(0f, 80f)] public float headYawMax = 40f;
    [Range(0f, 40f)] public float headPitchMax = 12f;
    [Tooltip("How much of the look direction the head takes; the rest stays in the eyes")]
    [Range(0f, 1f)] public float headShare = 0.7f;
    public float headTurnSpeed = 3f;        // 1/s, exponential approach

    [Header("Eyes (degrees)")]
    [Range(0f, 40f)] public float eyeYawMax = 22f;
    [Range(0f, 25f)] public float eyePitchMax = 10f;
    public float eyeTurnSpeed = 14f;

    [Header("Timing (seconds)")]
    public float dwellMin = 1.2f;
    public float dwellMax = 3.5f;
    [Tooltip("Chance that the next target is straight ahead")]
    [Range(0f, 1f)] public float centreChance = 0.3f;
    public int seed = 0;

    Transform head;
    Vector2 target;      // yaw, pitch of the look direction (deg)
    Vector2 headCur;     // current head offset applied
    Vector2 eyeCur;      // current eye offset applied
    float nextPick;
    System.Random rng;

    void OnEnable()
    {
        if (animator == null) animator = GetComponent<Animator>();
        if (animator != null && animator.isHuman) head = animator.GetBoneTransform(HumanBodyBones.Head);
        if (head == null) head = FindDeep(transform, "Head");
        if (leftEye == null) leftEye = FindDeep(transform, "Cunsumer_Eye_L");
        if (rightEye == null) rightEye = FindDeep(transform, "Cunsumer_Eye_R");
        rng = new System.Random(seed == 0 ? GetInstanceID() : seed);
        nextPick = Time.time + 0.5f;
    }

    static Transform FindDeep(Transform t, string name)
    {
        if (t.name == name) return t;
        for (int i = 0; i < t.childCount; i++) { var r = FindDeep(t.GetChild(i), name); if (r != null) return r; }
        return null;
    }

    float Rand(float a, float b) { return a + (float)rng.NextDouble() * (b - a); }

    void LateUpdate()
    {
        if (head == null) return;
        if (Time.time >= nextPick)
        {
            if (rng.NextDouble() < centreChance) target = Vector2.zero;
            else target = new Vector2(Rand(-1f, 1f) * (headYawMax + eyeYawMax * (1f - headShare)), Rand(-0.6f, 1f) * headPitchMax);
            nextPick = Time.time + Rand(dwellMin, dwellMax);
        }
        float dt = Time.deltaTime;
        // eyes go first: aim at the full target minus what the head already covers, clamped to the eye range
        Vector2 headGoal = new Vector2(Mathf.Clamp(target.x * headShare, -headYawMax, headYawMax), Mathf.Clamp(target.y, -headPitchMax, headPitchMax));
        headCur = Vector2.Lerp(headCur, headGoal, 1f - Mathf.Exp(-headTurnSpeed * dt));
        Vector2 eyeGoal = new Vector2(Mathf.Clamp(target.x - headCur.x, -eyeYawMax, eyeYawMax), Mathf.Clamp(target.y - headCur.y, -eyePitchMax, eyePitchMax));
        eyeCur = Vector2.Lerp(eyeCur, eyeGoal, 1f - Mathf.Exp(-eyeTurnSpeed * dt));

        // head: rotate about world up (yaw) and the head's right axis (pitch), added after the Animator
        head.rotation = Quaternion.AngleAxis(headCur.x, Vector3.up) * Quaternion.AngleAxis(-headCur.y, head.right) * head.rotation;
        // eyes: local +Z is the gaze; yaw about local Y, pitch about local X. Rotating around the eye's own origin (sphere centre) = gaze
        Quaternion eye = Quaternion.Euler(-eyeCur.y, eyeCur.x, 0f);
        if (leftEye != null) leftEye.localRotation = baseL * eye;
        if (rightEye != null) rightEye.localRotation = baseR * eye;
    }

    Quaternion baseL = Quaternion.identity, baseR = Quaternion.identity;
    void Start()
    {
        if (leftEye != null) baseL = leftEye.localRotation;
        if (rightEye != null) baseR = rightEye.localRotation;
    }
}
