using System.Collections;
using System.IO;
using UnityEngine;

/// <summary>
/// Development helper: renders a camera into PNG frames for a few seconds (used to check animation and
/// to make the portfolio GIFs). Created and started from the editor; does nothing in a normal play-through.
/// </summary>
public class FrameRecorder : MonoBehaviour
{
    public Camera source;
    public string folder;
    public float seconds = 2f;
    public int fps = 20;
    public int width = 640, height = 480;
    [Tooltip("Optional: keep the camera at this offset from the target, looking at it (side view).")]
    public Transform follow;
    public Vector3 followOffset = new Vector3(1.6f, 0.7f, 0f);
    public Vector3 lookOffset = new Vector3(0f, 0.4f, 0f);
    public bool Done { get; private set; }

    public void Begin() => StartCoroutine(Record());

    IEnumerator Record()
    {
        Directory.CreateDirectory(folder);
        var rt = new RenderTexture(width, height, 24);
        var tex = new Texture2D(width, height, TextureFormat.RGB24, false);
        int frames = Mathf.RoundToInt(seconds * fps);
        for (int i = 0; i < frames; i++)
        {
            yield return new WaitForEndOfFrame();
            if (follow != null)
            {
                source.transform.position = follow.position + followOffset;
                source.transform.LookAt(follow.position + lookOffset);
            }
            var prev = source.targetTexture;
            source.targetTexture = rt;
            source.Render();
            source.targetTexture = prev;
            RenderTexture.active = rt;
            tex.ReadPixels(new Rect(0, 0, width, height), 0, 0);
            tex.Apply();
            RenderTexture.active = null;
            File.WriteAllBytes(Path.Combine(folder, $"f{i:000}.png"), tex.EncodeToPNG());
            yield return new WaitForSeconds(1f / fps);
        }
        rt.Release();
        Done = true;
    }
}
