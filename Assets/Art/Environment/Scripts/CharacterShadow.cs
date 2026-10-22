using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
#if UNITY_EDITOR
using UnityEditor;
using UnityEditor.SceneManagement;
#endif

/// <summary>
/// Character shadow split (as in Wuthering Waves): the characters stop casting into URP's cascaded shadow map and
/// instead get their own high-resolution shadow map fitted tightly around them, seen from the main light.
/// Only the environment reads it (ToonTerrain / ToonFoliage via ToonCharacterShadow in ToonShadow.hlsl), so
/// characters have no self-shadow from it; they still receive the scene's shadows from the cascades.
/// Globals: _DSEWA_CharShadowMap (RFloat, distance along the light, cleared far), _DSEWA_CharShadowView,
/// _DSEWA_CharShadowRect = (minX, minY, 1/sizeX, 1/sizeY) in light space, _DSEWA_CharShadowParams =
/// (on, texel size uv, depth bias m, light shadow strength). Off (params.x = 0) whenever anything is missing.
/// Put it anywhere (e.g. on the Directional Light) and list the character roots.
/// </summary>
[ExecuteAlways]
public class CharacterShadow : MonoBehaviour
{
    [Tooltip("Character roots; every renderer under them is a caster")]
    public Transform[] characters;
    [Tooltip("Defaults to RenderSettings.sun, then the first directional light")]
    public Light sun;
    public int resolution = 2048;
    [Tooltip("Extra space around the characters, metres")]
    public float padding = 0.5f;
    [Tooltip("Receiver depth bias in metres (removes acne on the ground right under the feet)")]
    public float depthBias = 0.05f;
    [Tooltip("Stop the characters casting into URP's cascades, so their shadow is not drawn twice")]
    public bool removeFromSceneShadows = true;
    [Tooltip("Hidden/DSEWA/CharacterShadowDepth - referenced here so player builds include it")]
    public Shader casterShader;

    static readonly int MapId = Shader.PropertyToID("_DSEWA_CharShadowMap");
    static readonly int ViewId = Shader.PropertyToID("_DSEWA_CharShadowView");
    static readonly int RectId = Shader.PropertyToID("_DSEWA_CharShadowRect");
    static readonly int ParamsId = Shader.PropertyToID("_DSEWA_CharShadowParams");
    const string CasterShader = "Hidden/DSEWA/CharacterShadowDepth";
    const float FarClear = 1e6f;

    RenderTexture rt;
    CommandBuffer cmd;
    Material casterMat;
    readonly List<Renderer> casters = new List<Renderer>();
    readonly Dictionary<Renderer, ShadowCastingMode> savedModes = new Dictionary<Renderer, ShadowCastingMode>();
    readonly HashSet<Renderer> hadOverride = new HashSet<Renderer>();   // prefab instances whose cast-shadow was already overridden
    readonly HashSet<string> reported = new HashSet<string>();

    void OnEnable()
    {
#if UNITY_EDITOR
        AssemblyReloadEvents.beforeAssemblyReload += Release;
        EditorSceneManager.sceneSaving += OnSceneSaving;
        EditorSceneManager.sceneSaved += OnSceneSaved;
#endif
        Render();
    }

    void OnDisable()
    {
#if UNITY_EDITOR
        AssemblyReloadEvents.beforeAssemblyReload -= Release;
        EditorSceneManager.sceneSaving -= OnSceneSaving;
        EditorSceneManager.sceneSaved -= OnSceneSaved;
#endif
        Release();
    }

#if UNITY_EDITOR
    // never save the characters with their cascade shadows switched off (removing this component must give them back)
    void OnSceneSaving(UnityEngine.SceneManagement.Scene scene, string path) { if (scene == gameObject.scene) RestoreSceneShadows(); }
    void OnSceneSaved(UnityEngine.SceneManagement.Scene scene) { if (scene == gameObject.scene && isActiveAndEnabled) Render(); }
#endif

    void LateUpdate() => Render();   // after animation, so the shadow matches this frame's pose

    void Report(string key, string msg)
    {
        if (reported.Add(key)) Debug.LogWarning($"[CharacterShadow] {msg}", this);
    }

    static void PublishOff()
    {
        Shader.SetGlobalVector(ParamsId, Vector4.zero);
        Shader.SetGlobalTexture(MapId, Texture2D.whiteTexture);
    }

    void Release()
    {
        PublishOff();
        RestoreSceneShadows();
        cmd?.Release(); cmd = null;
        if (rt != null) { rt.Release(); DestroySafe(rt); rt = null; }
        DestroySafe(casterMat); casterMat = null;
    }

    static void DestroySafe(UnityEngine.Object o)
    {
        if (o == null) return;
        if (Application.isPlaying) Destroy(o); else DestroyImmediate(o);
    }

    void RestoreSceneShadows()
    {
        foreach (var kv in savedModes)
        {
            Renderer r = kv.Key;
            if (r == null) continue;
            r.shadowCastingMode = kv.Value;
#if UNITY_EDITOR
            // leave no prefab override behind for a value we only changed temporarily
            if (!hadOverride.Contains(r) && PrefabUtility.IsPartOfPrefabInstance(r))
            {
                var prop = new SerializedObject(r).FindProperty("m_CastShadows");
                if (prop != null && prop.prefabOverride) PrefabUtility.RevertPropertyOverride(prop, InteractionMode.AutomatedAction);
            }
#endif
        }
        savedModes.Clear();
        hadOverride.Clear();
    }

    Light FindSun()
    {
        if (sun != null) return sun;
        if (RenderSettings.sun != null) return RenderSettings.sun;
        foreach (var l in FindObjectsByType<Light>(FindObjectsSortMode.None))
            if (l.type == LightType.Directional) return l;
        return null;
    }

    [ContextMenu("Render")]
    public void Render()
    {
        try
        {
            if (!RenderInternal()) PublishOff();
            else reported.Clear();
        }
        catch (Exception e)
        {
            PublishOff();
            Report("ex:" + e.GetType().Name, $"character shadow failed, characters fall back to no separate shadow: {e}");
        }
    }

    bool RenderInternal()
    {
        if (SystemInfo.graphicsDeviceType == GraphicsDeviceType.Null) return false;
        Light light = FindSun();
        if (light == null || !light.isActiveAndEnabled) { Report("sun", "no active directional light."); return false; }

        // collect casters (and take them out of URP's cascades once)
        casters.Clear();
        if (characters != null)
            foreach (Transform root in characters)
            {
                if (root == null || !root.gameObject.activeInHierarchy) continue;
                foreach (Renderer r in root.GetComponentsInChildren<Renderer>())
                    if (r.enabled && r.gameObject.activeInHierarchy && !(r is ParticleSystemRenderer)) casters.Add(r);
            }
        if (casters.Count == 0) { Report("none", "no character renderers."); RestoreSceneShadows(); return false; }
        if (removeFromSceneShadows)
        {
            foreach (Renderer r in casters)
                if (!savedModes.ContainsKey(r))
                {
                    savedModes[r] = r.shadowCastingMode;
#if UNITY_EDITOR
                    if (PrefabUtility.IsPartOfPrefabInstance(r))
                    {
                        var prop = new SerializedObject(r).FindProperty("m_CastShadows");
                        if (prop != null && prop.prefabOverride) hadOverride.Add(r);
                    }
#endif
                    r.shadowCastingMode = ShadowCastingMode.Off;
                }
        }
        else RestoreSceneShadows();

        if (casterMat == null)
        {
            Shader s = casterShader != null ? casterShader : Shader.Find(CasterShader);
            if (s == null || !s.isSupported) { Report("shader", $"shader {CasterShader} missing or unsupported."); return false; }
            casterMat = new Material(s) { hideFlags = HideFlags.HideAndDontSave };
        }
        if (!EnsureTarget()) return false;

        // light space: +z along the light; fit x/y to the casters' bounds
        Matrix4x4 view = Matrix4x4.TRS(Vector3.zero, light.transform.rotation, Vector3.one).inverse;
        Vector2 min = new Vector2(float.MaxValue, float.MaxValue), max = new Vector2(float.MinValue, float.MinValue);
        foreach (Renderer r in casters)
        {
            Bounds b = r.bounds;
            for (int i = 0; i < 8; i++)
            {
                Vector3 c = new Vector3((i & 1) == 0 ? b.min.x : b.max.x, (i & 2) == 0 ? b.min.y : b.max.y, (i & 4) == 0 ? b.min.z : b.max.z);
                Vector3 l = view.MultiplyPoint3x4(c);
                min = Vector2.Min(min, l); max = Vector2.Max(max, l);
            }
        }
        min -= Vector2.one * padding; max += Vector2.one * padding;
        Vector2 size = max - min;
        float side = Mathf.Max(size.x, size.y);                       // square texels
        Vector2 centre = (min + max) * 0.5f;
        min = centre - Vector2.one * side * 0.5f;
        Vector4 rect = new Vector4(min.x, min.y, 1f / side, 1f / side);

        Shader.SetGlobalMatrix(ViewId, view);
        Shader.SetGlobalVector(RectId, rect);

        cmd ??= new CommandBuffer { name = "DSEWA Character Shadow" };
        cmd.Clear();
        cmd.SetRenderTarget(rt);
        cmd.ClearRenderTarget(false, true, new Color(FarClear, 0, 0, 0));
        foreach (Renderer r in casters)
        {
            int subMeshes = r.sharedMaterials.Length;
            for (int i = 0; i < subMeshes; i++) cmd.DrawRenderer(r, casterMat, i, 0);
        }
        Graphics.ExecuteCommandBuffer(cmd);

        Shader.SetGlobalTexture(MapId, rt);
        Shader.SetGlobalVector(ParamsId, new Vector4(1f, 1f / rt.width, depthBias, light.shadowStrength));
        return true;
    }

    bool EnsureTarget()
    {
        int res = Mathf.Clamp(resolution, 64, Mathf.Max(64, SystemInfo.maxTextureSize));
        if (rt != null && rt.width == res && rt.IsCreated()) return true;
        if (rt != null) { rt.Release(); DestroySafe(rt); rt = null; }
        if (!SystemInfo.IsFormatSupported(GraphicsFormat.R32_SFloat, GraphicsFormatUsage.Render))
        {
            Report("fmt", "R32 float render targets are not supported on this device.");
            return false;
        }
        rt = new RenderTexture(res, res, GraphicsFormat.R32_SFloat, GraphicsFormat.None)
        {
            name = "_DSEWA_CharShadowMap",
            filterMode = FilterMode.Point,
            wrapMode = TextureWrapMode.Clamp,
            hideFlags = HideFlags.HideAndDontSave,
        };
        if (!rt.Create()) { Report("create", "could not create the character shadow map."); DestroySafe(rt); rt = null; return false; }
        return true;
    }
}
