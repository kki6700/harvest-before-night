using System.IO;
using UnityEditor;
using UnityEditor.Recorder;
using UnityEditor.Recorder.Encoder;
using UnityEditor.Recorder.Input;
using UnityEngine;

// Records the main camera to MP4 with Unity Recorder: enters Play Mode, records a fixed number of
// frames, then leaves Play Mode. Output goes to Art/SDCat/render/ (outside Assets, not imported).
[InitializeOnLoad]
public static class SDCatCapture
{
    const string PendingKey = "SDCatCapture.Pending";
    const string FramesKey = "SDCatCapture.Frames";
    static RecorderController controller;

    public static string RenderDir => Path.GetFullPath(Path.Combine(Application.dataPath, "..", "Art", "SDCat", "render"));

    static SDCatCapture()
    {
        EditorApplication.playModeStateChanged += OnPlayModeChanged;
    }

    /// <summary>Record <paramref name="frames"/> frames at 30 fps into render/<paramref name="fileName"/>.mp4.</summary>
    public static void RecordMovie(string fileName, int frames)
    {
        if (EditorApplication.isPlaying) { Debug.LogWarning("SDCatCapture: already playing"); return; }
        SessionState.SetString(PendingKey, fileName);
        SessionState.SetInt(FramesKey, frames);
        EditorApplication.isPlaying = true;
    }

    static void OnPlayModeChanged(PlayModeStateChange state)
    {
        if (state != PlayModeStateChange.EnteredPlayMode) return;
        var fileName = SessionState.GetString(PendingKey, "");
        if (string.IsNullOrEmpty(fileName)) return;
        SessionState.EraseString(PendingKey);
        int frames = SessionState.GetInt(FramesKey, 240);

        Directory.CreateDirectory(RenderDir);
        var settings = ScriptableObject.CreateInstance<RecorderControllerSettings>();
        var movie = ScriptableObject.CreateInstance<MovieRecorderSettings>();
        movie.name = fileName;
        movie.Enabled = true;
        movie.EncoderSettings = new CoreEncoderSettings
        {
            Codec = CoreEncoderSettings.OutputCodec.MP4,
            EncodingQuality = CoreEncoderSettings.VideoEncodingQuality.High
        };
        movie.ImageInputSettings = new CameraInputSettings
        {
            Source = ImageSource.MainCamera,
            OutputWidth = 1920,
            OutputHeight = 1080,
            CaptureUI = false
        };
        movie.OutputFile = Path.Combine(RenderDir, fileName);
        settings.AddRecorderSettings(movie);
        settings.SetRecordModeToFrameInterval(0, frames - 1);
        settings.FrameRatePlayback = FrameRatePlayback.Constant;
        settings.FrameRate = 30;
        settings.CapFrameRate = true;

        controller = new RecorderController(settings);
        controller.PrepareRecording();
        controller.StartRecording();
        Debug.Log($"SDCatCapture: recording {frames} frames to {movie.OutputFile}.mp4");
        EditorApplication.update += WatchRecording;
    }

    static void WatchRecording()
    {
        if (controller != null && controller.IsRecording()) return;
        EditorApplication.update -= WatchRecording;
        controller = null;
        Debug.Log("SDCatCapture: done");
        EditorApplication.isPlaying = false;
    }

    /// <summary>Render the main camera supersampled (2x) and save a 1920x1080 PNG into render/.</summary>
    public static string SaveStill(string fileName)
    {
        Directory.CreateDirectory(RenderDir);
        var cam = Camera.main;
        var big = RenderTexture.GetTemporary(3840, 2160, 24, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB);
        var small = RenderTexture.GetTemporary(1920, 1080, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB);
        var prev = cam.targetTexture;
        cam.targetTexture = big; cam.Render(); cam.targetTexture = prev;
        Graphics.Blit(big, small);
        var active = RenderTexture.active; RenderTexture.active = small;
        var tex = new Texture2D(1920, 1080, TextureFormat.RGB24, false);
        tex.ReadPixels(new Rect(0, 0, 1920, 1080), 0, 0); tex.Apply();
        RenderTexture.active = active;
        var path = Path.Combine(RenderDir, fileName + ".png");
        File.WriteAllBytes(path, tex.EncodeToPNG());
        Object.DestroyImmediate(tex);
        RenderTexture.ReleaseTemporary(big); RenderTexture.ReleaseTemporary(small);
        return path;
    }
}
