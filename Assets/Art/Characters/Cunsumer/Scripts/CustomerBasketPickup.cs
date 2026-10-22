using UnityEngine;

/// <summary>
/// Customer picks a basket up off the ground: walk to it, play the PickUp state, and at the grab moment hand the
/// basket over to CarriedBasket (HandSocket mode), easing it from where it lies into the hand and fading the
/// "holding" arm layers in while the character stands up.
///
/// The basket starts on the ground at <see cref="basketSpot"/> (or wherever it is placed); the character stops so that
/// its left hand at the grab key lands on the handle (<see cref="handOffset"/> = hand position at the grab key in the
/// character's root space, measured from the PickUp clip). Swap the clip for a Mixamo take later: only the PickUp
/// state's motion, <see cref="grabNormalizedTime"/> and <see cref="handOffset"/> change.
/// Values are my own starting values.
/// </summary>
public class CustomerBasketPickup : MonoBehaviour
{
    public CarriedBasket basket;
    public Animator animator;
    [Tooltip("Where the basket lies on the ground (world). Empty = the basket's position at start.")]
    public Transform basketSpot;
    public bool playOnStart = true;

    [Header("Walk")]
    public float walkSpeed = 0.9f;
    public float turnSpeed = 360f;
    public string walkBool = "Walk";

    [Header("Pick up")]
    public string pickUpTrigger = "PickUp";
    public string pickUpState = "PickUp";
    [Tooltip("Grab moment if the clip has no OnItemTake event (normalized time of the PickUp state).")]
    [Range(0f, 1f)] public float grabNormalizedTime = 0.45f;
    [Tooltip("Left hand at the grab key, in the character root's space (x right, y up, z forward).")]
    public Vector3 handOffset = new Vector3(-0.3f, 0.23f, 0.35f);
    [Tooltip("Seconds to ease the basket from the ground into the hand.")]
    public float attachTime = 0.18f;

    enum Phase { Idle, Walking, Turning, Picking, Holding }
    Phase phase;
    Vector3 standPoint;
    Quaternion standFacing;
    Vector3 restPos; Quaternion restRot;
    float attachT;
    bool attached;

    void Start()
    {
        if (!animator) animator = GetComponentInChildren<Animator>();
        if (basket) basket.enabled = false;
        if (basket && basketSpot) { basket.transform.position = basketSpot.position; basket.transform.rotation = basketSpot.rotation; }
        if (playOnStart) Begin();
    }

    /// <summary>Start walking to the basket and pick it up.</summary>
    public void Begin()
    {
        if (!basket) return;
        restPos = basket.transform.position; restRot = basket.transform.rotation;
        Vector3 grip = basket.grip ? basket.grip.position : restPos;
        // face the basket from where we stand now, then stand where the grab-key hand meets the grip
        Vector3 to = grip - transform.position; to.y = 0f;
        standFacing = to.sqrMagnitude > 1e-4f ? Quaternion.LookRotation(to) : transform.rotation;
        Vector3 handFlat = new Vector3(handOffset.x, 0f, handOffset.z);
        standPoint = new Vector3(grip.x, transform.position.y, grip.z) - standFacing * handFlat;
        phase = Phase.Walking;
        animator.SetBool(walkBool, true);
    }

    void Update()
    {
        switch (phase)
        {
            case Phase.Walking:
            {
                Vector3 d = standPoint - transform.position; d.y = 0f;
                if (d.magnitude < 0.03f) { animator.SetBool(walkBool, false); phase = Phase.Turning; break; }
                Quaternion face = Quaternion.LookRotation(d);
                transform.rotation = Quaternion.RotateTowards(transform.rotation, face, turnSpeed * Time.deltaTime);
                transform.position += d.normalized * Mathf.Min(walkSpeed * Time.deltaTime, d.magnitude);
                break;
            }
            case Phase.Turning:
                transform.rotation = Quaternion.RotateTowards(transform.rotation, standFacing, turnSpeed * Time.deltaTime);
                if (Quaternion.Angle(transform.rotation, standFacing) < 1f)
                {
                    animator.SetTrigger(pickUpTrigger);
                    phase = Phase.Picking;
                }
                break;
            case Phase.Picking:
            {
                var st = animator.GetCurrentAnimatorStateInfo(0);
                if (!st.IsName(pickUpState)) break;
                if (!attached && st.normalizedTime >= grabNormalizedTime) Attach();   // fallback if the clip has no event
                if (attached)
                {
                    // arm layers fade in over the stand-up part of the clip
                    float k = Mathf.InverseLerp(grabNormalizedTime, 1f, st.normalizedTime);
                    basket.holdPoseBlend = Mathf.SmoothStep(0f, 1f, k);
                }
                if (st.normalizedTime >= 1f) { basket.holdPoseBlend = 1f; phase = Phase.Holding; }
                break;
            }
        }
    }

    // animation event on anim_customer_pick_basket (the moment the hand closes on the handle)
    void OnItemTake()
    {
        if (phase == Phase.Picking && !attached) Attach();
    }

    void Attach()
    {
        attached = true; attachT = 0f;
        basket.holdPoseBlend = 0f;
        basket.enabled = true;          // follows the hand from now on (LateUpdate)
    }

    void LateUpdate()
    {
        // ease from the ground pose into the hand right after the grab (CarriedBasket has already placed it)
        if (!attached || attachT >= 1f) return;
        attachT += Time.deltaTime / Mathf.Max(attachTime, 1e-3f);
        float k = Mathf.SmoothStep(0f, 1f, Mathf.Clamp01(attachT));
        basket.transform.position = Vector3.Lerp(restPos, basket.transform.position, k);
        basket.transform.rotation = Quaternion.Slerp(restRot, basket.transform.rotation, k);
    }
}
