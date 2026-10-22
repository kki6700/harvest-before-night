using System;
using System.Collections;
using UnityEngine;

/// <summary>
/// The alien customer at the shop door. Customers keep coming one after another: each walks out of the shop door
/// in new clothes, asks for a number of fruits, takes what the cat hands over (only what the order still needs),
/// pays when the order is full (price per fruit + a bonus for a full order), walks back in, and the next one comes.
/// The same character is reused; only the coat / shirt / trousers colours change (MaterialPropertyBlock tint on the
/// ToonCharacter lit / shadow colours). Order sizes, prices, colours and timings are my own values.
/// </summary>
public class DeliveryPoint : MonoBehaviour
{
    public enum Phase { Away, Arriving, Waiting, Paying, Leaving }

    [Tooltip("How close the cat must come (m).")]
    public float radius = 2.2f;
    public Animator customerAnimator;
    public string receiveTrigger = "PickUp";
    public string walkBool = "Walk";

    [Header("Orders")]
    public int minOrder = 4;
    public int maxOrder = 9;
    public int pricePerFruit = 10;
    [Tooltip("Paid on top when an order is filled.")]
    public int orderBonus = 20;

    [Header("Coming and going")]
    [Tooltip("Where customers come out of and go back into (the shop door). Empty = 3 m behind the stand point.")]
    public Transform door;
    public float walkSpeed = 1.3f;
    public float turnSpeed = 360f;
    [Tooltip("Seconds between one customer leaving and the next one coming out.")]
    public float gap = 1.2f;

    [Header("Clothes")]
    public Renderer coat, shirt, pants;
    [Tooltip("Coat, shirt, trousers tint per customer (multiplied on the material colours).")]
    public Color[] coatColors =
    {
        new Color(1.00f, 1.00f, 1.00f), new Color(1.00f, 0.62f, 0.55f), new Color(0.62f, 0.95f, 0.80f),
        new Color(1.00f, 0.88f, 0.45f), new Color(0.75f, 0.70f, 1.00f), new Color(0.55f, 0.82f, 1.00f),
    };
    public Color[] shirtColors =
    {
        new Color(1.00f, 1.00f, 1.00f), new Color(1.00f, 0.95f, 0.70f), new Color(1.00f, 0.75f, 0.85f),
        new Color(0.70f, 0.90f, 1.00f), new Color(0.85f, 1.00f, 0.75f), new Color(1.00f, 0.85f, 0.65f),
    };
    public Color[] pantsColors =
    {
        new Color(1.00f, 1.00f, 1.00f), new Color(0.55f, 0.60f, 0.85f), new Color(0.75f, 0.55f, 0.50f),
        new Color(0.50f, 0.70f, 0.60f), new Color(0.70f, 0.60f, 0.80f), new Color(0.60f, 0.60f, 0.65f),
    };

    public Phase Current { get; private set; } = Phase.Away;
    public bool IsReady => Current == Phase.Waiting;
    public int Order { get; private set; }
    public int Filled { get; private set; }
    /// <summary>Fruits handed over in total.</summary>
    public int Delivered { get; private set; }
    public int Coins { get; private set; }
    public int Served { get; private set; }

    /// <summary>Raised with the new total whenever fruit is delivered.</summary>
    public event Action<int> DeliveredChanged;
    /// <summary>Raised when a customer pays: (total coins, coins just earned).</summary>
    public event Action<int, int> Paid;

    Vector3 _standPos;
    Quaternion _standRot;
    Renderer[] _renderers;
    MaterialPropertyBlock _mpb;
    int _look = -1;
    static readonly int LitId = Shader.PropertyToID("_LitColor"), ShadowId = Shader.PropertyToID("_ShadowColor");

    void Awake()
    {
        _standPos = transform.position;
        _standRot = transform.rotation;
        _renderers = GetComponentsInChildren<Renderer>(true);
        _mpb = new MaterialPropertyBlock();
        if (customerAnimator == null) customerAnimator = GetComponentInChildren<Animator>();
        if (coat == null) coat = FindPart("Coat");
        if (shirt == null) shirt = FindPart("Shirt");
        if (pants == null) pants = FindPart("Pants");
    }

    void Start()
    {
        // the first customer is already standing at the door when the round starts
        NewLook();
        NewOrder();
        Current = Phase.Waiting;
    }

    Renderer FindPart(string suffix)
    {
        foreach (var r in _renderers) if (r.name.EndsWith(suffix)) return r;
        return null;
    }

    /// <summary>Hand fruits over. Returns how many the customer took (only what the order still needs).</summary>
    public int Receive(int amount)
    {
        if (!IsReady || amount <= 0) return 0;
        int take = Mathf.Min(amount, Order - Filled);
        Filled += take;
        Delivered += take;
        if (customerAnimator != null && !string.IsNullOrEmpty(receiveTrigger)) customerAnimator.SetTrigger(receiveTrigger);
        DeliveredChanged?.Invoke(Delivered);
        if (Filled >= Order) StartCoroutine(PayAndLeave());
        return take;
    }

    IEnumerator PayAndLeave()
    {
        Current = Phase.Paying;
        int gained = Order * pricePerFruit + orderBonus;
        Coins += gained;
        Served++;
        Paid?.Invoke(Coins, gained);
        // let the pick-up animation play out before walking (walking off mid-clip slid a bent-over customer away)
        yield return new WaitForSeconds(0.3f);
        for (float t = 0f; t < 4f && customerAnimator != null; t += Time.deltaTime)
        {
            var st = customerAnimator.GetCurrentAnimatorStateInfo(0);
            if (!customerAnimator.IsInTransition(0) && !st.IsName(receiveTrigger)) break;
            yield return null;
        }
        yield return new WaitForSeconds(0.3f);

        Current = Phase.Leaving;
        Vector3 exit = DoorPos();
        yield return WalkTo(exit);
        SetVisible(false);
        Current = Phase.Away;
        yield return new WaitForSeconds(gap);

        NewLook();
        NewOrder();
        transform.position = exit;
        SetVisible(true);
        Current = Phase.Arriving;
        yield return WalkTo(_standPos);
        for (float t = 0f; t < 0.6f && Quaternion.Angle(transform.rotation, _standRot) > 1f; t += Time.deltaTime)
        {
            transform.rotation = Quaternion.RotateTowards(transform.rotation, _standRot, turnSpeed * Time.deltaTime);
            yield return null;
        }
        transform.rotation = _standRot;
        Current = Phase.Waiting;
    }

    Vector3 DoorPos()
    {
        Vector3 p = door != null ? door.position : _standPos - _standRot * Vector3.forward * 3f;
        p.y = _standPos.y;
        return p;
    }

    // Walking is driven by the clips' own root motion (OnAnimatorMove): the body moves exactly as far as the feet
    // push, so WalkStart (2.9 s, slow first steps) no longer slides at full speed. Code only steers.
    Vector3 _walkTarget;
    bool _walking;

    IEnumerator WalkTo(Vector3 target)
    {
        _walkTarget = target;
        _walking = true;
        if (customerAnimator != null) customerAnimator.SetBool(walkBool, true);
        float safety = 0f;
        while (true)
        {
            Vector3 d = _walkTarget - transform.position; d.y = 0f;
            if (d.magnitude < 0.05f) break;
            transform.rotation = Quaternion.RotateTowards(transform.rotation, Quaternion.LookRotation(d), turnSpeed * Time.deltaTime);
            // fallback when there is no animator / root motion: plain steady walk
            if (customerAnimator == null) transform.position += d.normalized * Mathf.Min(walkSpeed * Time.deltaTime, d.magnitude);
            safety += Time.deltaTime;
            if (safety > 12f) { transform.position = new Vector3(_walkTarget.x, transform.position.y, _walkTarget.z); break; }
            yield return null;
        }
        _walking = false;
        if (customerAnimator != null) customerAnimator.SetBool(walkBool, false);
    }

    void OnAnimatorMove()
    {
        if (customerAnimator == null || !_walking) return;
        // root motion distance this frame, applied along the path and never past the target
        float step = customerAnimator.deltaPosition.magnitude;
        Vector3 d = _walkTarget - transform.position; d.y = 0f;
        Vector3 fwd = transform.forward; fwd.y = 0f;
        if (Vector3.Dot(fwd.normalized, d.normalized) < 0.3f) step *= 0.3f;     // mostly turning: small steps
        transform.position += d.normalized * Mathf.Min(step, d.magnitude);
    }

    void SetVisible(bool on)
    {
        foreach (var r in _renderers) if (r != null) r.enabled = on;
    }

    void NewOrder()
    {
        Order = UnityEngine.Random.Range(minOrder, maxOrder + 1);
        Filled = 0;
    }

    void NewLook()
    {
        int n = Mathf.Min(coatColors.Length, Mathf.Min(shirtColors.Length, pantsColors.Length));
        if (n == 0) return;
        int pick = _look < 0 ? 0 : UnityEngine.Random.Range(1, n);          // first customer wears the original clothes
        if (pick == _look) pick = (pick + 1) % n;
        _look = pick;
        Tint(coat, coatColors[pick]);
        Tint(shirt, shirtColors[pick]);
        Tint(pants, pantsColors[pick]);
    }

    void Tint(Renderer r, Color c)
    {
        if (r == null || r.sharedMaterial == null) return;
        var m = r.sharedMaterial;
        r.GetPropertyBlock(_mpb);
        if (m.HasProperty(LitId)) _mpb.SetColor(LitId, m.GetColor(LitId) * c);
        if (m.HasProperty(ShadowId)) _mpb.SetColor(ShadowId, m.GetColor(ShadowId) * c);
        r.SetPropertyBlock(_mpb);
    }
}
