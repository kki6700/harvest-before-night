using System.Collections;
using UnityEngine;

/// <summary>
/// A crop the cat can pick. Ripe crops can be harvested once; they regrow after a while.
/// Lantern fruit trees use their own Animator triggers ("Harvest" shrinks the fruit to buds,
/// "Regrow" swells them again). Mushroom flowers disappear when picked and grow back out of the soil by scale.
/// </summary>
public class RipeCrop : MonoBehaviour
{
    public enum Kind { LanternFruit, MushroomFlower }

    public Kind kind = Kind.LanternFruit;
    [Tooltip("How many fruits one harvest puts in the basket.")]
    public int yield = 3;
    [Tooltip("Seconds until the crop is ripe again after a harvest.")]
    public float regrowSeconds = 25f;
    [Tooltip("Mushroom flowers: seconds the regrowth takes at the end of regrowSeconds (from nothing to full size).")]
    public float growSeconds = 3f;
    [Tooltip("Where the picked fruit flies from (the fruit cluster). Empty = 1 m above the crop.")]
    public Transform pickPoint;

    public bool IsRipe { get; private set; } = true;

    Animator _animator;
    Transform _visual;
    Vector3 _visualScale;

    void Awake()
    {
        _animator = GetComponent<Animator>();
        _visual = transform.Find("Grow");
        if (_visual == null) _visual = transform;
        _visualScale = _visual.localScale;
    }

    /// <summary>World position the fruit leaves from when picked.</summary>
    public Vector3 PickPosition => pickPoint != null ? pickPoint.position : transform.position + Vector3.up * (kind == Kind.LanternFruit ? 1.2f : 0.35f);

    /// <summary>Harvest the crop. Returns the number of fruits picked (0 if it was not ripe).</summary>
    public int Harvest()
    {
        if (!IsRipe) return 0;
        IsRipe = false;
        if (kind == Kind.LanternFruit && _animator != null)
            _animator.SetTrigger("Harvest");
        else
            StartCoroutine(PickAway());
        StartCoroutine(RegrowAfterDelay());
        return yield;
    }

    // mushroom flower (user: "removed when harvested, then grows back"): a small squash, then it shrinks to
    // nothing and is hidden; near the end of regrowSeconds it pushes up out of the soil with a little overshoot
    IEnumerator PickAway()
    {
        yield return ScaleTo(1.12f, 0.08f);
        yield return ScaleTo(0f, 0.22f);
        SetShown(false);
    }

    IEnumerator RegrowAfterDelay()
    {
        if (kind == Kind.LanternFruit && _animator != null)
        {
            yield return new WaitForSeconds(regrowSeconds);
            _animator.SetTrigger("Regrow");
            yield return new WaitForSeconds(1.8f);       // let the fruit swell before it counts as ripe
        }
        else
        {
            yield return new WaitForSeconds(Mathf.Max(0.5f, regrowSeconds - growSeconds));
            _visual.localScale = Vector3.zero;
            SetShown(true);
            yield return ScaleTo(1.08f, growSeconds * 0.8f);
            yield return ScaleTo(1f, growSeconds * 0.2f);
        }
        IsRipe = true;
    }

    void SetShown(bool on)
    {
        foreach (var r in _visual.GetComponentsInChildren<Renderer>(true)) r.enabled = on;
    }

    IEnumerator ScaleTo(float factor, float seconds)
    {
        Vector3 from = _visual.localScale, to = _visualScale * factor;
        for (float t = 0f; t < seconds; t += Time.deltaTime)
        {
            float k = Mathf.SmoothStep(0f, 1f, t / seconds);
            _visual.localScale = Vector3.LerpUnclamped(from, to, k);
            yield return null;
        }
        _visual.localScale = to;
    }
}

