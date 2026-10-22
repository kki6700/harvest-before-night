using System.Collections;
using UnityEngine;

/// <summary>
/// A crop the cat can pick. Ripe crops can be harvested once; they regrow after a while.
/// Lantern fruit trees use their own Animator triggers ("Harvest" shrinks the fruit to buds,
/// "Regrow" swells them again). Other crops (mushroom flowers) shrink away and grow back by scale.
/// </summary>
public class RipeCrop : MonoBehaviour
{
    public enum Kind { LanternFruit, MushroomFlower }

    public Kind kind = Kind.LanternFruit;
    [Tooltip("How many fruits one harvest puts in the basket.")]
    public int yield = 3;
    [Tooltip("Seconds until the crop is ripe again after a harvest.")]
    public float regrowSeconds = 25f;
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
            StartCoroutine(ScaleTo(0.25f, 0.3f));
        StartCoroutine(RegrowAfterDelay());
        return yield;
    }

    IEnumerator RegrowAfterDelay()
    {
        yield return new WaitForSeconds(regrowSeconds);
        if (kind == Kind.LanternFruit && _animator != null)
            _animator.SetTrigger("Regrow");
        else
            yield return ScaleTo(1f, 1.2f);
        yield return new WaitForSeconds(kind == Kind.LanternFruit ? 1.8f : 0f);   // let the fruit swell before it counts as ripe
        IsRipe = true;
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

