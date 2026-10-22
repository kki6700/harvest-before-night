using System;
using System.Collections;
using UnityEngine;
using UnityEngine.InputSystem;

/// <summary>
/// The cat carries a basket by its handle in its mouth. Walking up to a ripe crop and pressing E
/// (or Space) picks it: the cat stops, faces the crop, nods down and the fruit hops into the basket.
/// Also hands the basket's fruit over at a delivery point (the alien customer).
/// </summary>
[RequireComponent(typeof(CatController))]
public class CatHarvester : MonoBehaviour
{
    [Header("Basket")]
    public BasketFill basket;
    [Tooltip("Most fruits the basket holds before it must be delivered.")]
    public int capacity = 12;

    [Header("Reach")]
    [Tooltip("How far in front of the cat a crop can be picked (m).")]
    public float reach = 1.6f;
    [Tooltip("Cat's head bone: nods down while picking.")]
    public Transform head;
    [Tooltip("Model used for the fruit that hops into the basket (lantern fruit / mushroom).")]
    public GameObject lanternFruitPiece;
    public GameObject mushroomPiece;

    public int Carried { get; private set; }
    public bool IsFull => Carried >= capacity;
    /// <summary>Text for the on-screen hint ("E 수확" etc.), empty when there is nothing to do.</summary>
    public string Prompt { get; private set; } = "";
    /// <summary>Raised whenever the carried count changes (UI listens).</summary>
    public event Action<int> CarriedChanged;

    CatController _controller;
    RipeCrop[] _crops;
    DeliveryPoint[] _deliveryPoints;
    bool _busy;
    float _nod;          // 0..1, head nod amount while picking

    void Awake()
    {
        _controller = GetComponent<CatController>();
    }

    void Start()
    {
        _crops = FindObjectsByType<RipeCrop>(FindObjectsSortMode.None);
        _deliveryPoints = FindObjectsByType<DeliveryPoint>(FindObjectsSortMode.None);
        UpdateBasket();
    }

    void Update()
    {
        if (_busy) return;
        if (_controller.gameLocked) { Prompt = ""; return; }

        DeliveryPoint delivery = NearestDelivery();
        RipeCrop crop = delivery == null ? NearestRipeCrop() : null;

        if (delivery != null)
            Prompt = !delivery.IsReady ? "다음 손님이 오는 중이에요"
                   : Carried > 0 ? string.Format("E  납품하기  (주문 {0} / {1})", delivery.Filled, delivery.Order)
                   : "바구니가 비었어요";
        else if (crop != null)
            Prompt = IsFull ? "바구니가 가득 찼어요 — 손님에게 가져가요" : "E  수확하기";
        else
            Prompt = "";

        if (!PressedAction() || _controller.inputLocked) return;
        if (delivery != null && delivery.IsReady && Carried > 0) StartCoroutine(DeliverRoutine(delivery));
        else if (crop != null && !IsFull) StartCoroutine(HarvestRoutine(crop));
    }

    void LateUpdate()
    {
        // head nod on top of the animation (the cat lowers its head to the fruit)
        if (head != null && _nod > 0f)
            head.localRotation *= Quaternion.Euler(28f * _nod, 0f, 0f);
    }

    static bool PressedAction()
    {
        var kb = Keyboard.current;
        return kb != null && (kb.eKey.wasPressedThisFrame || kb.spaceKey.wasPressedThisFrame);
    }

    RipeCrop NearestRipeCrop()
    {
        RipeCrop best = null;
        float bestDist = reach;
        Vector3 front = transform.position + transform.forward * 0.4f;
        foreach (var c in _crops)
        {
            if (c == null || !c.IsRipe) continue;
            Vector3 d = c.transform.position - front;
            d.y = 0f;
            float dist = d.magnitude;
            if (dist < bestDist) { bestDist = dist; best = c; }
        }
        return best;
    }

    DeliveryPoint NearestDelivery()
    {
        foreach (var d in _deliveryPoints)
        {
            if (d == null) continue;
            Vector3 v = d.transform.position - transform.position;
            v.y = 0f;
            if (v.magnitude < d.radius) return d;
        }
        return null;
    }

    IEnumerator HarvestRoutine(RipeCrop crop)
    {
        _busy = true;
        _controller.inputLocked = true;
        Prompt = "";

        // face the crop
        Vector3 to = crop.transform.position - transform.position;
        to.y = 0f;
        Quaternion from = transform.rotation, target = Quaternion.LookRotation(to.normalized, Vector3.up);
        for (float t = 0f; t < 0.2f; t += Time.deltaTime)
        {
            transform.rotation = Quaternion.Slerp(from, target, t / 0.2f);
            yield return null;
        }

        // nod down, pick, nod up
        yield return Nod(0f, 1f, 0.18f);
        Vector3 start = crop.PickPosition;
        int got = crop.Harvest();
        GameObject piece = crop.kind == RipeCrop.Kind.LanternFruit ? lanternFruitPiece : mushroomPiece;
        yield return FlyIntoBasket(piece, start, Mathf.Min(got, 3));
        Carried = Mathf.Min(capacity, Carried + got);
        UpdateBasket();
        yield return Nod(1f, 0f, 0.18f);

        _controller.inputLocked = false;
        _busy = false;
    }

    IEnumerator DeliverRoutine(DeliveryPoint delivery)
    {
        _busy = true;
        _controller.inputLocked = true;
        Prompt = "";
        yield return Nod(0f, 1f, 0.2f);
        int took = delivery.Receive(Carried);      // the customer takes only what the order still needs
        Carried -= took;
        UpdateBasket();
        yield return Nod(1f, 0f, 0.2f);
        _controller.inputLocked = false;
        _busy = false;
    }

    IEnumerator Nod(float a, float b, float seconds)
    {
        for (float t = 0f; t < seconds; t += Time.deltaTime)
        {
            _nod = Mathf.SmoothStep(a, b, t / seconds);
            yield return null;
        }
        _nod = b;
    }

    /// <summary>A few small fruit copies hop from the crop into the basket along an arc.</summary>
    IEnumerator FlyIntoBasket(GameObject prefab, Vector3 start, int count)
    {
        if (prefab == null || basket == null) yield break;
        var pieces = new GameObject[count];
        for (int i = 0; i < count; i++)
        {
            pieces[i] = Instantiate(prefab, start, Quaternion.identity);
            foreach (var c in pieces[i].GetComponentsInChildren<Collider>()) Destroy(c);
        }
        const float duration = 0.45f;
        for (float t = 0f; t < duration + 0.1f * count; t += Time.deltaTime)
        {
            Vector3 end = basket.transform.position + Vector3.up * 0.08f;
            for (int i = 0; i < count; i++)
            {
                float k = Mathf.Clamp01((t - 0.1f * i) / duration);
                Vector3 p = Vector3.Lerp(start, end, k) + Vector3.up * Mathf.Sin(k * Mathf.PI) * 0.5f;
                pieces[i].transform.position = p;
                pieces[i].transform.localScale = prefab.transform.localScale * Mathf.Lerp(1f, 0.5f, k);
            }
            yield return null;
        }
        foreach (var p in pieces) Destroy(p);
    }

    void UpdateBasket()
    {
        if (basket != null) basket.SetFill((float)Carried / capacity);
        CarriedChanged?.Invoke(Carried);
    }
}

