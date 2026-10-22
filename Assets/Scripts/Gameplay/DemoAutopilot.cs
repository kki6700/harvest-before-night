using UnityEngine;

/// <summary>
/// Demo mode for recording the play video: started with the command-line flag "-demo" (GameDirector adds it).
/// Presses start after a short pause, then plays like a player would: runs to the nearest ripe crop, picks it,
/// carries a full basket (or whatever it has when nothing is ripe) to the customer, and repeats until the round
/// ends. Steering goes through CatController.debugInput in camera space, actions through CatHarvester.PressAction,
/// so the cat moves and animates exactly as with the keyboard. Timings are my own values.
/// </summary>
public class DemoAutopilot : MonoBehaviour
{
    public float startDelay = 3f;
    public float resultHold = 6f;

    GameDirector _director;
    CatController _cat;
    CatHarvester _harvester;
    RipeCrop[] _crops;
    float _t, _pressCooldown;
    Vector3 _lastPos;
    float _stuckT;
    Vector3 _sidestep;

    void Start()
    {
        _director = FindAnyObjectByType<GameDirector>();
        _cat = FindAnyObjectByType<CatController>();
        _harvester = FindAnyObjectByType<CatHarvester>();
        _crops = FindObjectsByType<RipeCrop>(FindObjectsSortMode.None);
    }

    void Update()
    {
        if (_director == null || _cat == null || _harvester == null) return;
        _t += Time.unscaledDeltaTime;
        _pressCooldown -= Time.deltaTime;
        switch (_director.Current)
        {
            case GameDirector.State.Ready:
                if (_t > startDelay) _director.Begin();
                return;
            case GameDirector.State.Playing:
                Drive();
                return;
            default:
                _cat.debugInput = Vector2.zero;
                return;
        }
    }

    void Drive()
    {
        var dp = _director.delivery;
        RipeCrop crop = NearestRipe();
        bool deliver = _harvester.Carried > 0 && (_harvester.IsFull || crop == null);
        Vector3 target = deliver && dp != null ? dp.transform.position : crop != null ? crop.transform.position : _cat.transform.position;

        Vector3 to = target - _cat.transform.position; to.y = 0f;
        float stop = deliver ? 1.4f : 0.9f;
        bool arrived = to.magnitude < stop;

        // action: the harvester shows a prompt when something is in reach
        if (arrived || _harvester.Prompt.StartsWith("E"))
        {
            _cat.debugInput = Vector2.zero;
            _cat.debugRun = false;
            if (_pressCooldown <= 0f && (!deliver || (dp != null && dp.IsReady)))
            {
                _harvester.PressAction();
                _pressCooldown = 0.6f;
            }
            if (arrived) return;
        }

        // unstick: if barely moving for a while, step sideways for a moment
        float moved = (_cat.transform.position - _lastPos).magnitude;
        _lastPos = _cat.transform.position;
        _stuckT = moved < 0.01f ? _stuckT + Time.deltaTime : 0f;
        if (_stuckT > 0.5f) { _sidestep = Vector3.Cross(Vector3.up, to.normalized) * (Random.value < 0.5f ? 1f : -1f); _stuckT = -0.6f; }
        Vector3 dir = to.normalized;
        if (_stuckT < 0f) dir = (_sidestep + dir * 0.3f).normalized;

        // world direction -> input relative to the camera (what CatController expects)
        Transform cam = _cat.cameraTransform != null ? _cat.cameraTransform : Camera.main.transform;
        Vector3 f = cam.forward; f.y = 0f; f.Normalize();
        Vector3 r = cam.right; r.y = 0f; r.Normalize();
        _cat.debugInput = new Vector2(Vector3.Dot(dir, r), Vector3.Dot(dir, f));
        _cat.debugRun = to.magnitude > 3f;
    }

    RipeCrop NearestRipe()
    {
        RipeCrop best = null; float bd = float.MaxValue;
        foreach (var c in _crops)
        {
            if (c == null || !c.IsRipe) continue;
            float d = (c.transform.position - _cat.transform.position).sqrMagnitude;
            if (d < bd) { bd = d; best = c; }
        }
        return best;
    }
}
