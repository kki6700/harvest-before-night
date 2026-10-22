using System.Collections;
using UnityEngine;
using UnityEngine.InputSystem;

/// <summary>
/// Prototype only (not for the team repo): stands in for the game's FarmGrid so SoilFX can be tried by hand.
/// Aim with the centre of the screen (FreeCamera on the camera):
///   Space - hoe hit (3 hits dig a cell)   F - plant   Q - water   R - reset every cell
/// Soil colours are FarmGrid's untilled / tilled / wet colours, written the same way (MaterialPropertyBlock _BaseColor).
/// </summary>
public class SoilFXDemo : MonoBehaviour
{
    public Camera Cam;
    [Tooltip("On play, put the camera here (looking at this object) so the bed is in view")] public bool MoveCameraOnStart = true;
    public int HitsToTill = 3;
    [Tooltip("Delay from key press to the blade touching the ground (the swing)")] public float ImpactDelay = 0.1f;
    public Color Untilled = new Color(0.024f, 0.086f, 0.122f);
    public Color Tilled = new Color(0.17f, 0.33f, 0.47f);
    public Color Wet = new Color(0.08f, 0.22f, 0.42f);
    [Tooltip("Watering can prefab with WaterFX (shown only while watering)")] public GameObject WateringCan;
    public float PourTime = 1.1f;

    SoilFX[] _cells;
    int[] _hits;
    bool[] _planted, _wet;
    MaterialPropertyBlock _block;
    GameObject _can;
    bool _pouring;

    void Start()
    {
        if (Cam == null) Cam = Camera.main;
        if (MoveCameraOnStart && Cam != null)
        {
            Cam.transform.position = transform.position + new Vector3(0f, 1.7f, -3.2f);
            Cam.transform.LookAt(transform.position + Vector3.up * 0.1f);
            foreach (var mb in Cam.GetComponents<MonoBehaviour>())          // FreeCamera reads its angles in OnEnable
                if (mb.GetType().Name == "FreeCamera") { mb.enabled = false; mb.enabled = true; }
        }
        _cells = FindObjectsByType<SoilFX>(FindObjectsSortMode.None);
        _hits = new int[_cells.Length]; _planted = new bool[_cells.Length]; _wet = new bool[_cells.Length];
        _block = new MaterialPropertyBlock();
        for (int i = 0; i < _cells.Length; i++) Paint(i);
    }

    void Update()
    {
        var kb = Keyboard.current;
        if (kb == null) return;
        if (kb.rKey.wasPressedThisFrame)
            for (int i = 0; i < _cells.Length; i++) { _hits[i] = 0; _planted[i] = _wet[i] = false; _cells[i].ResetSoil(); Paint(i); }
        if (!Aim(out int cell, out Vector3 point)) return;
        if (kb.spaceKey.wasPressedThisFrame && _hits[cell] < HitsToTill && !_planted[cell]) StartCoroutine(Hit(cell, point));
        if (kb.fKey.wasPressedThisFrame && _hits[cell] >= HitsToTill && !_planted[cell]) { _planted[cell] = true; _cells[cell].OnPlant(); }
        if (kb.qKey.wasPressedThisFrame && _hits[cell] >= HitsToTill && !_wet[cell] && !_pouring) StartCoroutine(Water(cell, point));
    }

    IEnumerator Hit(int cell, Vector3 point)
    {
        _hits[cell]++;
        float progress = (float)_hits[cell] / HitsToTill;
        yield return new WaitForSeconds(ImpactDelay);
        _cells[cell].OnTillHit(progress, point);
        Paint(cell);
    }

    IEnumerator Water(int cell, Vector3 point)
    {
        _pouring = true;
        if (_can == null && WateringCan != null) _can = Instantiate(WateringCan);
        if (_can == null) { _wet[cell] = true; Paint(cell); _pouring = false; yield break; }
        _can.SetActive(true);
        // hold the can beside the cell with its spout (local -X) toward the aim point, then tilt it down to pour
        Vector3 toPoint = point - Cam.transform.position; toPoint.y = 0f; toPoint.Normalize();
        Vector3 side = Vector3.Cross(Vector3.up, toPoint);
        Vector3 pos = point - toPoint * 0.15f + side * 0.35f + Vector3.up * 0.75f;
        Vector3 spoutDir = (point - pos); spoutDir.y = 0f; spoutDir.Normalize();
        Quaternion baseRot = Quaternion.FromToRotation(Vector3.left, spoutDir);
        _can.transform.position = pos;
        var fx = _can.GetComponent<WaterFX>();
        for (float t = 0f; t < 0.25f; t += Time.deltaTime) { _can.transform.rotation = baseRot * Quaternion.Euler(0f, 0f, 35f * t / 0.25f); yield return null; }
        _can.transform.rotation = baseRot * Quaternion.Euler(0f, 0f, 35f);
        if (fx != null) fx.Pour(PourTime);
        yield return new WaitForSeconds(0.35f);                 // first drops reach the soil
        _wet[cell] = true; Paint(cell);              // the game only switches to its wet colour
        yield return new WaitForSeconds(PourTime + 0.2f);
        for (float t = 0f; t < 0.25f; t += Time.deltaTime) { _can.transform.rotation = baseRot * Quaternion.Euler(0f, 0f, 35f * (1f - t / 0.25f)); yield return null; }
        yield return new WaitForSeconds(0.6f);
        _can.SetActive(false);
        _pouring = false;
    }

    // ---- scripted use (ProtoCapture): same as the keys, without aiming
    public int CellIndex(string name) { for (int i = 0; i < _cells.Length; i++) if (_cells[i].name == name) return i; return -1; }
    public Vector3 CellPoint(int cell, Vector2 offset) => _cells[cell].transform.position + new Vector3(offset.x, 0.1f, offset.y);
    public void DoHit(int cell, Vector3 point) { if (_hits[cell] < HitsToTill) StartCoroutine(Hit(cell, point)); }
    public void DoPlant(int cell) { if (_hits[cell] >= HitsToTill && !_planted[cell]) { _planted[cell] = true; _cells[cell].OnPlant(); } }
    public void DoWater(int cell, Vector3 point) { if (!_pouring) StartCoroutine(Water(cell, point)); }

    bool Aim(out int cell, out Vector3 point)
    {
        cell = -1; point = Vector3.zero;
        var ray = Cam.ViewportPointToRay(new Vector3(0.5f, 0.5f, 0f));
        if (!Physics.Raycast(ray, out var hit, 30f)) return false;
        var fx = hit.collider.GetComponentInParent<SoilFX>();
        if (fx == null) return false;
        cell = System.Array.IndexOf(_cells, fx); point = hit.point;
        return cell >= 0;
    }

    void Paint(int i)
    {
        var r = _cells[i].GetComponent<Renderer>();
        r.GetPropertyBlock(_block);
        Color c = _wet[i] ? Wet : Color.Lerp(Untilled, Tilled, (float)_hits[i] / HitsToTill);
        _block.SetColor("_BaseColor", c);
        r.SetPropertyBlock(_block);
    }

    void OnGUI()
    {
        GUI.Label(new Rect(Screen.width / 2 - 4, Screen.height / 2 - 10, 20, 20), "+");
        GUI.Label(new Rect(12, 12, 520, 22), "Space: hoe   F: plant   Q: water   R: reset   (aim with the + )");
    }
}
