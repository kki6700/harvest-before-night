using UnityEngine;

/// <summary>
/// Floating crystal fragment: bobs up and down only (no rotation, no sideways drift) around where it was placed.
/// Each fragment gets its own phase from its position, so a group never moves in step.
/// Amplitude / period are my own starting values.
/// </summary>
public class CrystalFloat : MonoBehaviour
{
    [Tooltip("Height of the bob above and below the rest position (m).")]
    public float amplitude = 0.12f;
    [Tooltip("Seconds for one full up-and-down.")]
    public float period = 4f;

    Vector3 _rest;
    float _phase;

    void OnEnable()
    {
        _rest = transform.localPosition;
        Vector3 p = transform.position;
        _phase = Mathf.Repeat(p.x * 0.73f + p.z * 1.37f, 1f) * Mathf.PI * 2f;
    }

    void OnDisable() => transform.localPosition = _rest;

    void Update()
    {
        float y = Mathf.Sin(Time.time * Mathf.PI * 2f / Mathf.Max(period, 0.01f) + _phase) * amplitude;
        transform.localPosition = _rest + new Vector3(0f, y, 0f);
    }
}
