using UnityEngine;

/// <summary>
/// Sloshing for DSEWA/ToonLiquid: when the container moves or turns, the liquid surface tilts against the motion and
/// rocks back to level (damped sine). Writes _WobbleX / _WobbleZ / _Fill through a MaterialPropertyBlock, so every
/// bottle keeps its own state on a shared material.
/// Put it on the liquid's MeshRenderer (child of the bottle). Gameplay sets <see cref="Fill"/> (e.g. lower it on use).
/// All defaults are my own starting values.
/// </summary>
[ExecuteAlways]
[RequireComponent(typeof(Renderer))]
public class LiquidWobble : MonoBehaviour
{
    [Range(0f, 1f)] public float Fill = 0.75f;

    [Tooltip("Largest surface slope (height change per metre across the bottle)")]
    public float MaxWobble = 0.6f;
    [Tooltip("How strongly movement (m/s) tips the surface")]
    public float MoveResponse = 0.25f;
    [Tooltip("How strongly turning (deg/s) tips the surface")]
    public float TurnResponse = 0.0025f;
    [Tooltip("Rocking speed (swings per second)")]
    public float WobbleSpeed = 2.2f;
    [Tooltip("How fast the rocking dies down")]
    public float Recovery = 2.5f;

    static readonly int FillId = Shader.PropertyToID("_Fill");
    static readonly int WobbleXId = Shader.PropertyToID("_WobbleX");
    static readonly int WobbleZId = Shader.PropertyToID("_WobbleZ");
    static readonly int LiquidBoxId = Shader.PropertyToID("_LiquidBox");

    Renderer _renderer;
    MaterialPropertyBlock _block;
    Vector3 _lastPos;
    Quaternion _lastRot;
    float _amountX, _amountZ, _time;

    void OnEnable()
    {
        _renderer = GetComponent<Renderer>();
        _block = new MaterialPropertyBlock();
        _lastPos = transform.position;
        _lastRot = transform.rotation;
        _amountX = _amountZ = 0f;
        Apply(0f, 0f);
    }

    void Update()
    {
        float dt = Application.isPlaying ? Time.deltaTime : 0f;
        if (dt <= 0f) { Apply(0f, 0f); return; }

        _time += dt;
        _amountX = Mathf.Lerp(_amountX, 0f, dt * Recovery);
        _amountZ = Mathf.Lerp(_amountZ, 0f, dt * Recovery);

        Vector3 velocity = (_lastPos - transform.position) / dt;
        Vector3 turn = (transform.rotation * Quaternion.Inverse(_lastRot)).eulerAngles;
        turn = new Vector3(Mathf.DeltaAngle(0f, turn.x), Mathf.DeltaAngle(0f, turn.y), Mathf.DeltaAngle(0f, turn.z)) / dt;

        _amountX = Mathf.Clamp(_amountX + velocity.x * MoveResponse + turn.z * TurnResponse, -MaxWobble, MaxWobble);
        _amountZ = Mathf.Clamp(_amountZ + velocity.z * MoveResponse - turn.x * TurnResponse, -MaxWobble, MaxWobble);

        float wave = Mathf.Sin(_time * WobbleSpeed * 2f * Mathf.PI);
        Apply(_amountX * wave, _amountZ * wave);

        _lastPos = transform.position;
        _lastRot = transform.rotation;
    }

    void Apply(float x, float z)
    {
        if (_renderer == null) return;
        _renderer.GetPropertyBlock(_block);
        _block.SetFloat(FillId, Fill);
        _block.SetFloat(WobbleXId, x);
        _block.SetFloat(WobbleZId, z);
        Bounds b = _renderer.bounds;
        _block.SetVector(LiquidBoxId, new Vector4(b.center.x, b.center.z, b.min.y, b.max.y));
        _renderer.SetPropertyBlock(_block);
    }
}
