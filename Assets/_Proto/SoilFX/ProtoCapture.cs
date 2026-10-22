using System.Collections;
using System.IO;
using UnityEngine;

/// <summary>
/// Prototype only: plays a fixed sequence on the SoilFXDemo (3 hoe hits, plant, water) at a fixed frame rate and saves
/// every frame of its own camera as PNG (Project/Temp/SoilCapture). Turn it on, press Play, wait for "done" in the log.
/// </summary>
public class ProtoCapture : MonoBehaviour
{
    public SoilFXDemo Demo;
    public Camera Cam;
    public string CellName = "Cell1";
    public int FrameRate = 24;
    public Vector2Int Size = new Vector2Int(960, 540);
    public float Length = 8.5f;

    RenderTexture _rt;
    Texture2D _read;
    string _dir;
    int _frame;
    bool _recording;

    IEnumerator Start()
    {
        _dir = Path.Combine(Application.dataPath, "../Temp/SoilCapture");
        if (Directory.Exists(_dir)) Directory.Delete(_dir, true);
        Directory.CreateDirectory(_dir);
        _rt = new RenderTexture(Size.x, Size.y, 24, RenderTextureFormat.ARGB32);
        _read = new Texture2D(Size.x, Size.y, TextureFormat.RGB24, false);
        Time.captureFramerate = FrameRate;
        yield return null;                                       // let the demo paint its cells first

        int cell = Demo.CellIndex(CellName);
        _recording = true;
        yield return new WaitForSeconds(0.6f);
        Demo.DoHit(cell, Demo.CellPoint(cell, new Vector2(-0.3f, 0.25f)));
        yield return new WaitForSeconds(0.75f);
        Demo.DoHit(cell, Demo.CellPoint(cell, new Vector2(0.3f, -0.2f)));
        yield return new WaitForSeconds(0.75f);
        Demo.DoHit(cell, Demo.CellPoint(cell, new Vector2(0.05f, 0.4f)));
        yield return new WaitForSeconds(1.1f);
        Demo.DoPlant(cell);
        yield return new WaitForSeconds(1.3f);
        Demo.DoWater(cell, Demo.CellPoint(cell, Vector2.zero));
        yield return new WaitForSeconds(Length - 4.5f);
        _recording = false;
        Time.captureFramerate = 0;
        Debug.Log($"ProtoCapture done: {_frame} frames in {_dir}");
    }

    void LateUpdate()
    {
        if (!_recording) return;
        // slow drift around the bed so the relief reads
        float t = _frame / (float)FrameRate;
        Vector3 c = Demo.CellPoint(Demo.CellIndex(CellName), Vector2.zero);
        float a = Mathf.Lerp(-35f, -15f, t / Length) * Mathf.Deg2Rad;
        Cam.transform.position = c + new Vector3(Mathf.Sin(a) * 2.3f, 1.35f, -Mathf.Cos(a) * 2.3f);
        Cam.transform.LookAt(c + Vector3.up * 0.25f);
        StartCoroutine(Grab());
    }

    IEnumerator Grab()
    {
        yield return new WaitForEndOfFrame();
        var prev = Cam.targetTexture;
        Cam.targetTexture = _rt; Cam.Render(); Cam.targetTexture = prev;
        RenderTexture.active = _rt;
        _read.ReadPixels(new Rect(0, 0, Size.x, Size.y), 0, 0); _read.Apply();
        RenderTexture.active = null;
        File.WriteAllBytes(Path.Combine(_dir, $"f{_frame:0000}.png"), _read.EncodeToPNG());
        _frame++;
    }
}
