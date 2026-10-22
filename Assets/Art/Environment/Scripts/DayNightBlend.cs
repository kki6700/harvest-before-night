using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// Time-of-day slider for a look-dev scene. Each preset (dawn, noon, evening, sunset, night ...) sits at an hour and
/// stores a snapshot of every numeric material property (colour, float, vector) of the listed materials, the sun /
/// moon light, CloudSunLight colours and the spore emission. The Hour slider (0..24, wraps around midnight) lerps
/// between the two presets around it. Post-processing: a night Volume whose weight = the blended preset Night Post.
///
/// Authoring: pick a preset in "Edit Preset" -> context menu "Go To Edit Preset" (slider jumps to its hour) ->
/// edit the materials / light until it looks right -> "Capture Edit Preset". Only properties that differ between
/// presets are driven. Note: the listed materials are assets, so moving the slider rewrites them (use scene copies).
/// </summary>
[ExecuteAlways]
public class DayNightBlend : MonoBehaviour
{
    [Range(0f, 24f)] public float hour = 22f;

    [Header("Targets")]
    public Material[] materials = Array.Empty<Material>();
    public Light sun;
    public CloudSunLight cloudLight;
    [Tooltip("Volume with the night profile; its weight follows the presets' Night Post")]
    public Volume nightVolume;
    public ParticleSystem spores;
    [Tooltip("Hidden when its blended material alpha is ~0 (e.g. godrays at night)")]
    public ParticleSystem godrays;

    [Serializable]
    public struct State
    {
        public Quaternion sunRotation;
        public Color sunColor;
        public float sunIntensity;
        public Color cloudSunLit, cloudSunShadow, cloudFarLit, cloudFarShadow;
        public float cloudSunBrightness, cloudFarBrightness;
        public float sporeRate;
    }

    [Serializable]
    public class Preset
    {
        public string name = "Preset";
        [Range(0f, 24f)] public float hour = 12f;
        [Tooltip("Weight of the night post-processing volume at this time")]
        [Range(0f, 1f)] public float nightPost;
        public State state;
    }

    [Serializable]
    public class PropEntry
    {
        public Material material;
        public string property;
        public int kind;               // 0 colour, 1 float, 2 vector
        public List<Vector4> values = new List<Vector4>();   // index = preset
        // legacy (two-snapshot version)
        public Vector4 day, night;
    }

    [Header("Presets (sorted by hour)")]
    public List<Preset> presets = new List<Preset>();
    [Tooltip("Preset index used by the Go To / Capture context menu items")]
    public int editPreset;

    [SerializeField, HideInInspector] List<PropEntry> entries = new List<PropEntry>();
    // legacy two-snapshot data, migrated into presets "Noon" and "Night"
    [SerializeField, HideInInspector] float night = 1f;
    [SerializeField, HideInInspector] State dayState, nightState;
    [SerializeField, HideInInspector] bool hasDay, hasNight;

    float applied = -1f;

    void OnEnable() { Migrate(); applied = -1f; }
    void OnValidate() { applied = -1f; }

    void Update()
    {
        if (Mathf.Abs(applied - hour) > 1e-5f) Apply();
    }

    void Migrate()
    {
        if (presets.Count > 0 || !hasDay || !hasNight) return;
        presets.Add(new Preset { name = "Noon", hour = 12f, nightPost = 0f, state = dayState });
        presets.Add(new Preset { name = "Night", hour = 22f, nightPost = 1f, state = nightState });
        foreach (var e in entries) e.values = new List<Vector4> { e.day, e.night };
        hour = Mathf.Lerp(12f, 22f, night);
        hasDay = hasNight = false;
    }

    // two presets around the hour (cyclic over 24 h) and the blend factor between them
    bool Bracket(float h, out int a, out int b, out float t)
    {
        a = b = -1; t = 0f;
        int n = presets.Count;
        if (n == 0) return false;
        if (n == 1) { a = b = 0; return true; }
        var order = new List<int>();
        for (int i = 0; i < n; i++) order.Add(i);
        order.Sort((x, y) => presets[x].hour.CompareTo(presets[y].hour));
        for (int k = 0; k < n; k++)
        {
            int i = order[k], j = order[(k + 1) % n];
            float h0 = presets[i].hour, h1 = presets[j].hour;
            if (k == n - 1) h1 += 24f;                 // wrap: last preset -> first preset of the next day
            float hh = h < h0 ? h + 24f : h;
            if (hh >= h0 && hh <= h1)
            {
                a = i; b = j; t = h1 > h0 ? (hh - h0) / (h1 - h0) : 0f;
                t = t * t * (3f - 2f * t);             // ease in / out around each preset
                return true;
            }
        }
        a = b = order[0];
        return true;
    }

    public void Apply()
    {
        applied = hour;
        if (!Bracket(hour, out int a, out int b, out float t)) return;

        foreach (var e in entries)
        {
            if (e.material == null || e.values == null || a >= e.values.Count || b >= e.values.Count) continue;
            if (IsDerived(e.property)) continue;
            Vector4 va = e.values[a], vb = e.values[b];
            bool varies = false;
            for (int i = 1; i < e.values.Count && !varies; i++) varies = e.values[i] != e.values[0];
            if (!varies) continue;
            Vector4 v = Vector4.Lerp(va, vb, t);
            switch (e.kind)
            {
                case 0: e.material.SetColor(e.property, v); break;
                case 1: e.material.SetFloat(e.property, v.x); break;
                default: e.material.SetVector(e.property, v); break;
            }
        }
        foreach (var m in materials) UpdateParticleFadeParams(m);

        State sa = presets[a].state, sb = presets[b].state;
        if (sun)
        {
            sun.transform.rotation = Quaternion.Slerp(sa.sunRotation, sb.sunRotation, t);
            sun.color = Color.Lerp(sa.sunColor, sb.sunColor, t);
            sun.intensity = Mathf.Lerp(sa.sunIntensity, sb.sunIntensity, t);
        }
        if (cloudLight)
        {
            cloudLight.sunSideLit = Color.Lerp(sa.cloudSunLit, sb.cloudSunLit, t);
            cloudLight.sunSideShadow = Color.Lerp(sa.cloudSunShadow, sb.cloudSunShadow, t);
            cloudLight.farSideLit = Color.Lerp(sa.cloudFarLit, sb.cloudFarLit, t);
            cloudLight.farSideShadow = Color.Lerp(sa.cloudFarShadow, sb.cloudFarShadow, t);
            cloudLight.sunSideBrightness = Mathf.Lerp(sa.cloudSunBrightness, sb.cloudSunBrightness, t);
            cloudLight.farSideBrightness = Mathf.Lerp(sa.cloudFarBrightness, sb.cloudFarBrightness, t);
        }
        if (nightVolume) nightVolume.weight = Mathf.Lerp(presets[a].nightPost, presets[b].nightPost, t);
        if (spores)
        {
            var em = spores.emission;
            em.rateOverTimeMultiplier = Mathf.Lerp(sa.sporeRate, sb.sporeRate, t);
        }
        if (godrays)
        {
            var r = godrays.GetComponent<ParticleSystemRenderer>();
            Material m = r ? r.sharedMaterial : null;
            bool visible = m == null || !m.HasProperty("_BaseColor") || m.GetColor("_BaseColor").a > 0.005f;
            if (r) r.enabled = visible;
        }
    }

    // URP particle shaders: these vectors are computed by the material inspector from other properties
    // (disabled fading stores Infinity, and lerping Infinity gives NaN = invisible particles), so never blend them;
    // they are rebuilt from the blended distances below.
    static bool IsDerived(string property) => property == "_CameraFadeParams" || property == "_SoftParticleFadeParams";

    // same formulas as URP's ParticleGUI (SetupMaterialWithSoftParticles / camera fading)
    static void UpdateParticleFadeParams(Material m)
    {
        if (m == null) return;
        if (m.HasProperty("_CameraFadeParams") && m.HasProperty("_CameraFadingEnabled"))
        {
            bool on = m.GetFloat("_CameraFadingEnabled") >= 0.5f;
            float near = Mathf.Max(0f, m.GetFloat("_CameraNearFadeDistance"));
            float far = Mathf.Max(near + 0.01f, m.GetFloat("_CameraFarFadeDistance"));
            m.SetVector("_CameraFadeParams", on ? new Vector4(near, 1f / (far - near), 0, 0) : new Vector4(0, float.PositiveInfinity, 0, 0));
            if (on) m.EnableKeyword("_FADING_ON");
        }
        if (m.HasProperty("_SoftParticleFadeParams") && m.HasProperty("_SoftParticlesEnabled"))
        {
            bool on = m.GetFloat("_SoftParticlesEnabled") >= 0.5f;
            float near = Mathf.Max(0f, m.GetFloat("_SoftParticlesNearFadeDistance"));
            float far = Mathf.Max(near + 0.01f, m.GetFloat("_SoftParticlesFarFadeDistance"));
            m.SetVector("_SoftParticleFadeParams", on ? new Vector4(near, 1f / (far - near), 0, 0) : Vector4.zero);
        }
    }

    [ContextMenu("Go To Edit Preset")]
    public void GoToEditPreset()
    {
        if (editPreset < 0 || editPreset >= presets.Count) return;
        hour = presets[editPreset].hour; Apply();
    }

    [ContextMenu("Capture Edit Preset")]
    public void CaptureEditPreset() => Capture(editPreset);

    /// <summary>Adds a preset (values copied from the current blended state) and returns its index.</summary>
    public int AddPreset(string presetName, float presetHour, float nightPost)
    {
        presets.Add(new Preset { name = presetName, hour = presetHour, nightPost = nightPost });
        int idx = presets.Count - 1;
        Capture(idx);
        return idx;
    }

    public void Capture(int index)
    {
        if (index < 0 || index >= presets.Count) return;
        int n = presets.Count;
        foreach (var m in materials)
        {
            if (m == null) continue;
            Shader s = m.shader;
            for (int i = 0; i < s.GetPropertyCount(); i++)
            {
                var type = s.GetPropertyType(i);
                int kind = type == ShaderPropertyType.Color ? 0
                         : type == ShaderPropertyType.Float || type == ShaderPropertyType.Range ? 1
                         : type == ShaderPropertyType.Vector ? 2 : -1;
                if (kind < 0) continue;
                string name = s.GetPropertyName(i);
                if (IsDerived(name)) continue;
                Vector4 v = kind == 0 ? (Vector4)m.GetColor(name) : kind == 1 ? new Vector4(m.GetFloat(name), 0, 0, 0) : m.GetVector(name);
                PropEntry e = entries.Find(x => x.material == m && x.property == name);
                if (e == null) { e = new PropEntry { material = m, property = name, kind = kind }; entries.Add(e); }
                while (e.values.Count < n) e.values.Add(v);   // new property / new preset: start from the current value
                e.values[index] = v;
            }
        }

        var st = new State();
        if (sun) { st.sunRotation = sun.transform.rotation; st.sunColor = sun.color; st.sunIntensity = sun.intensity; }
        if (cloudLight)
        {
            st.cloudSunLit = cloudLight.sunSideLit; st.cloudSunShadow = cloudLight.sunSideShadow;
            st.cloudFarLit = cloudLight.farSideLit; st.cloudFarShadow = cloudLight.farSideShadow;
            st.cloudSunBrightness = cloudLight.sunSideBrightness; st.cloudFarBrightness = cloudLight.farSideBrightness;
        }
        if (spores) st.sporeRate = spores.emission.rateOverTimeMultiplier;
        presets[index].state = st;
        applied = -1f;
    }
}
