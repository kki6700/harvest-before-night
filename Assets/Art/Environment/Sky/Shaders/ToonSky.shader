// Toon sky sphere (Notion "하늘·구름" page) — the Unity counterpart of SurvivalKit's BP_Sky_Sphere /
// M_Sky_Panning_Clouds2: zenith/horizon colours by view direction, a sun, and a far layer of panning clouds.
// Used as the skybox material: Unity draws it as an infinitely far sphere, so no mesh, depth or camera-follow.
// Stylized pass (Notion "하늘·구름" step 10): 3-stop gradient horizon -> mid -> zenith + a bright horizon band +
// toon sun (hard disc, flat halo ring, soft glow). Palette picked from the user's painted T_CloudCard_Color
// (cloud shadows carry the sky colour in that style). Tiny dither hides 8-bit banding in the smooth gradient.
// Research values (stylized-shading-research, SurvivalKit_Shader_Analysis_KO "하늘 구체와 구름") are set on
// M_Sky_Toon: Zenith/Horizon/Overall colour, Cloud Color, Cloud Opacity 1.2157 (> 1 extrapolates like UE's Lerp),
// Cloud speed 1, Sun brightness 50. The original cloud/sky textures are not in the clone, so the cloud layer is
// procedural noise. Extras that are not in the original (halo ring, glow, two-tone cloud split, below-horizon
// colour) default to off / neutral.
Shader "DSEWA/ToonSky"
{
    Properties
    {
        [Header(Sky Gradient)]
        _ZenithColor ("Zenith", Color) = (0.31, 0.56, 0.91, 1)
        _HorizonColor ("Horizon", Color) = (0.80, 0.92, 1.0, 1)
        _MidColor ("Mid", Color) = (0.64, 0.86, 0.96, 1)
        _MidHeight ("Mid Height (0 horizon .. 1 zenith)", Range(0.02, 0.98)) = 0.25
        _OverallColor ("Overall Colour (multiply)", Color) = (1, 1, 1, 1)
        _GroundColor ("Below Horizon", Color) = (0.66, 0.79, 0.54, 1)
        _GradientPower ("Gradient Power", Range(0.1, 4)) = 0.6
        _GroundFade ("Below Horizon Fade", Range(1, 50)) = 12
        [Header(Horizon Band)]
        _BandColor ("Band Colour", Color) = (0.93, 0.98, 0.99, 1)
        _BandHeight ("Band Height", Range(0.005, 0.5)) = 0.08
        _BandAmount ("Band Amount", Range(0, 1)) = 0.8
        _Dither ("Gradient Dither", Range(0, 4)) = 1
        [Header(Sunset Glow (horizon towards the sun))]
        _SunsetColor ("Sunset Colour (outer)", Color) = (1, 0.62, 0.43, 1)
        _SunsetHotColor ("Sunset Colour (at horizon)", Color) = (1, 0.79, 0.54, 1)
        _SunsetAmount ("Sunset Amount", Range(0, 1)) = 0
        _SunsetHeight ("Sunset Height", Range(0.01, 1)) = 0.25
        _SunsetSpread ("Sunset Azimuth Falloff (higher = narrower)", Range(0.5, 16)) = 3
        [Header(Volumetric Cloud Layer (toon raymarch overhead))]
        _VolAmount ("Volumetric Amount", Range(0, 1)) = 0
        _VolBottom ("Layer Bottom (m)", Float) = 1200
        _VolTop ("Layer Top (m)", Float) = 1900
        _VolScale ("Noise Scale (1/m)", Float) = 0.0012
        _VolCoverage ("Coverage Threshold (higher = fewer)", Range(0, 1)) = 0.42
        _VolDensity ("Density", Float) = 6
        _VolSteps ("Steps", Range(4, 32)) = 12
        _VolWind ("Wind (xz m/s)", Vector) = (8, 3, 0, 0)
        _VolHorizonFade ("Horizon Fade (start, end elevation)", Vector) = (0.06, 0.25, 0, 0)
        _VolSunSideFade ("Sun Side Fade (start, end elevation, arc deg, feather deg) - painted cards fill this arc", Vector) = (0.06, 0.2, 60, 30)
        _VolLightStep ("Light Sample Distance (m)", Float) = 180
        _VolLightAbsorb ("Light Absorption", Range(0, 8)) = 2.5
        _VolErode ("Puff Erosion (cauliflower edges)", Range(0, 0.6)) = 0.3
        _VolShadeThreshold ("Toon Shade Threshold", Range(0, 1)) = 0.5
        _VolEdge ("Silhouette Softness", Range(0.001, 0.3)) = 0.04
        _VolLitSun ("Lit (sun side)", Color) = (1, 0.83, 0.63, 1)
        _VolShadowSun ("Shadow (sun side)", Color) = (0.78, 0.50, 0.66, 1)
        _VolLitFar ("Lit (far side)", Color) = (0.96, 0.87, 0.94, 1)
        _VolShadowFar ("Shadow (far side)", Color) = (0.56, 0.46, 0.76, 1)
        _VolSideFalloff ("Sun Side Falloff", Range(0.5, 8)) = 2
        _VolStepLength ("Step Length (m, low angles get more steps)", Float) = 60
        _VolMaxSteps ("Max Steps", Range(8, 96)) = 64
        _VolJitter ("Start Jitter (hides step bands)", Range(0, 1)) = 1
        _VolLightSteps ("Light Steps", Range(1, 4)) = 3
        _VolPowder ("Powder (darker thin edges away from the sun)", Range(0, 1)) = 0.5
        _VolSilver ("Silver Lining (rim towards the sun)", Range(0, 2)) = 1
        _VolSilverG ("Silver Lining Focus (HG g)", Range(0, 0.95)) = 0.6
        _VolRimColor ("Silver Lining Colour", Color) = (1, 0.86, 0.6, 1)
        _VolMorph ("Shape Morph Speed", Float) = 0.015
        _VolLobeSize ("Outline Lobe Size (m)", Float) = 160
        _VolScallop ("Outline Lobes (cauliflower edge)", Range(0, 1)) = 0.45
        _VolInnerScallop ("Inner Shade Lobes (dots when the underside is evenly lit)", Range(0, 1)) = 0
        _VolSkin ("Dome Skin Thickness (m, > step length)", Float) = 80
        _VolHaze ("Horizon Haze (far clouds melt into the sky)", Vector) = (0.03, 0.16, 0.85, 0)
        [Toggle] _VolDebugMask ("Debug: cloud silhouette only (white on black)", Float) = 0

        [Header(Sun)]
        [Header(Stars (night))]
        _StarAmount ("Star Amount (0 day .. 1 night)", Range(0, 1)) = 0
        [HDR] _StarColor ("Star Colour", Color) = (0.9, 0.94, 1, 1)
        _StarScale ("Star Grid (higher = smaller, more)", Float) = 160
        _StarDensity ("Star Density (fraction of cells)", Range(0, 0.3)) = 0.05
        _StarTwinkle ("Twinkle", Range(0, 1)) = 0.4
        _StarFar ("Far Layer: Grid, Density, Size Min, Size Max", Vector) = (360, 0, 0.12, 0.22)
        _StarNear ("Near Layer: Grid, Density, Size Min, Size Max", Vector) = (70, 0, 0.035, 0.06)
        _StarBright ("Layer Brightness: Far, Mid, Near, Sparkle Arm Length", Vector) = (0.35, 1, 1.4, 0.25)
        _StarWarm ("Warm Star Tint", Color) = (1, 0.78, 0.6, 1)
        _StarCool ("Cool Star Tint", Color) = (0.62, 0.75, 1, 1)
        _StarTintAmount ("Star Colour Variety", Range(0, 1)) = 0
        _StarBlink ("Twinkle: Speed Min, Speed Max (rad/s), Blinking Share, Blink Depth", Vector) = (1, 4, 0, 0)
        _StarBandBoost ("More Stars near the Galaxy Band", Range(0, 4)) = 0

        [Header(Galaxy band (night))]
        _GalaxyPlane ("Galaxy Band Circle Normal (xyz world), w = half width (deg)", Vector) = (0.5, 0.6, 0.6, 12)
        _GalaxyAmount ("Galaxy Band Amount (0 off)", Range(0, 1)) = 0
        [NoScaleOffset] _GalaxyMap ("Galaxy Maps (R spiral, G flocculent, B clumps, A dust lanes; GalaxyMaps.sbs)", 2D) = "black" {}
        _GalaxyCore ("Band / Galaxy Core Colour", Color) = (0.85, 0.7, 0.95, 1)
        _GalaxyEdge ("Band / Galaxy Edge Colour", Color) = (0.35, 0.4, 0.85, 1)
        _GalaxyTile ("Band: Clump Repeat, Dust Repeat, Clump Mix, Dust Darkening", Vector) = (3, 2, 0.5, 0.7)
        _GalaxyBright ("Band Brightness", Range(0, 2)) = 0.4
        _GalaxyToon ("Toon Steps (0 smooth .. 1 hard)", Range(0, 1)) = 0.6
        _GalaxySteps ("Toon Step Count", Range(2, 6)) = 3
        _GalaxyDrift ("Motion: Clump Drift, Dust Drift (per s, along the band), Clump Shimmer, Galaxy Spin (rad/s)", Vector) = (0, 0, 0, 0)

        [Header(Galaxies (night))]
        _GalBig ("Big Galaxy: Dir (xyz world), Size (rad)", Vector) = (0.3, 0.6, 0.7, 0.25)
        _GalBigShape ("Big Galaxy: Roll (rad), Tilt (1 face-on .. 0.1 edge-on), Type (0 spiral, 1 flocculent), Brightness", Vector) = (0.4, 0.45, 0, 0)
        _GalGroup ("Galaxy Group: Centre Dir (xyz world), Spread (rad)", Vector) = (0.2, 0.7, 0.7, 0.2)
        _GalGroupCfg ("Galaxy Group: Count (0..6), Size Min, Size Max (rad), Brightness", Vector) = (0, 0.012, 0.035, 0.6)

        [Header(Planet (alien sky))]
        _PlanetAmount ("Planet Amount (0 off)", Range(0, 1)) = 0
        _PlanetSkyDraw ("Draw Ringed Planet + Moons 2, 4 Here (0 = 3D meshes by SkyRingedPlanet)", Range(0, 1)) = 1
        _PlanetDir ("Planet Direction (world)", Vector) = (0.3, 0.45, 0.85, 0)
        _PlanetSize ("Planet Radius (rad)", Range(0.01, 0.4)) = 0.13
        _PlanetLit ("Planet Lit", Color) = (0.91, 0.78, 1, 1)
        _PlanetShadow ("Planet Shadow", Color) = (0.23, 0.17, 0.48, 1)
        _PlanetBand ("Planet Band Colour", Color) = (0.62, 0.52, 0.94, 1)
        _PlanetBands ("Band Count", Float) = 7
        _PlanetBandAmount ("Band Amount", Range(0, 1)) = 0.45
        _PlanetRim ("Atmosphere Rim", Color) = (0.8, 0.74, 1, 1)
        _PlanetRimWidth ("Atmosphere Rim Width (radii)", Range(0, 0.3)) = 0.07
        _RingColor ("Ring Colour", Color) = (0.93, 0.87, 1, 1)
        _RingInnerOuter ("Ring Inner / Outer (radii), Tilt (rad), Squash", Vector) = (1.35, 2.1, 0.35, 0.22)
        _RingAmount ("Ring Amount", Range(0, 1)) = 0.75
        _Moon2Dir ("Small Moon Direction (world)", Vector) = (0.55, 0.32, 0.77, 0)
        _Moon2Size ("Small Moon Radius (rad)", Range(0, 0.15)) = 0.03
        _Moon2Lit ("Small Moon Lit", Color) = (1, 0.9, 0.95, 1)
        _Moon2Shadow ("Small Moon Shadow", Color) = (0.29, 0.23, 0.5, 1)
        _Moon3Dir ("Moon 3 Direction (world)", Vector) = (-0.2, 0.2, 0.96, 0)
        _Moon3Size ("Moon 3 Radius (rad, 0 off)", Range(0, 0.15)) = 0
        _Moon4Dir ("Moon 4 Direction (world)", Vector) = (0.35, 0.65, 0.67, 0)
        _Moon4Size ("Moon 4 Radius (rad, 0 off)", Range(0, 0.15)) = 0
        _BodyMid ("Bodies: Mid Tone (3rd toon step, 0 off)", Range(0, 1)) = 0
        _BodyLimb ("Bodies: Limb Darkening", Range(0, 1)) = 0
        _BodyHaze ("Bodies: Atmospheric Perspective (sky colour over them)", Range(0, 1)) = 0
        _BodyHazeLow ("Bodies: Extra Haze Near the Horizon", Range(0, 1)) = 0

        [Header(Giant Planet (rising from the horizon))]
        _GiantAmount ("Giant Amount (0 off)", Range(0, 1)) = 0
        _GiantDir ("Giant Direction (world)", Vector) = (-0.6, 0.03, 0.8, 0)
        _GiantSize ("Giant Radius (rad)", Range(0.05, 1.2)) = 0.5
        _GiantLit ("Giant Lit", Color) = (0.5, 0.65, 0.94, 1)
        _GiantShadow ("Giant Shadow", Color) = (0.12, 0.16, 0.42, 1)
        _GiantBand ("Giant Band Colour", Color) = (0.8, 0.85, 1.1, 1)
        _GiantBands ("Giant Band Count", Float) = 11
        _GiantBandAmount ("Giant Band Amount", Range(0, 1)) = 0.35
        _GiantRim ("Giant Atmosphere Rim", Color) = (0.6, 0.75, 1, 1)
        _GiantRimWidth ("Giant Rim Width (radii)", Range(0, 0.3)) = 0.04
        _GiantAxis ("Giant Spin Axis (tilt to viewer, roll on screen; rad)", Vector) = (0.35, -0.2, 0, 0)
        _PlanetAxisSign ("Ringed Planet Axis Side (1 or -1, matches the ring)", Float) = 1
        [Header(Motion (our planet stays still and the others turn))]
        _GiantSpin ("Giant Spin (rad per s)", Float) = 0
        _GiantStorm ("Giant Storm Spot (shows the spin)", Range(0, 1)) = 0
        _StormColor ("Storm Spot Colour", Color) = (0.95, 0.55, 0.75, 1)
        _PlanetSpin ("Ringed Planet Spin (rad per s)", Float) = 0
        _RingSpin ("Ring Turn (rad per s)", Float) = 0
        _Moon2Orbit ("Moon 2 Orbit round the ringed planet (radius rad, period s, flatten, phase)", Vector) = (0, 90, 0.3, 0)
        _Moon3Orbit ("Moon 3 Orbit round the giant (radius rad, period s, flatten, phase)", Vector) = (0, 220, 0.25, 4)
        _Moon4Orbit ("Moon 4 Orbit round the ringed planet (radius rad, period s, flatten, phase)", Vector) = (0, 160, 0.35, 2)

        [Header(Aurora Curtains)]
        _AuroraAmount ("Aurora Amount (0 off)", Range(0, 2)) = 0
        _AuroraMain ("Aurora Main Mask (curtain silhouette)", 2D) = "black" {}
        _AuroraDetail ("Aurora Detail Noise (vertical streaks)", 2D) = "white" {}
        _AuroraFlow ("Aurora Distortion / Flow (RG)", 2D) = "gray" {}
        _AuroraBand ("Aurora Band Mask (big bright bands)", 2D) = "white" {}
        _AuroraArc ("Curtain Bottom, Top (deg: elevation, or off the band circle)", Vector) = (8, 60, 0, 0)
        _AuroraBandPlane ("Band Circle Normal (xyz world, w 1 = hang on this circle)", Vector) = (0, 0.5, -0.86, 0)
        _AuroraRepeat ("Curtain Repeats round the sky", Float) = 3
        _AuroraDetailTile ("Detail Tiling (x)", Float) = 2
        _AuroraFlowAmount ("Flow Wobble", Range(0, 0.3)) = 0.06
        _AuroraFlowSpeed ("Flow Speed", Float) = 0.01
        _AuroraTwist ("Noise Twist (bends and curls the curtain)", Range(0, 1)) = 0
        _AuroraFlowStrength ("Flow Map Strength (advection distance per cycle)", Range(0, 0.5)) = 0
        _AuroraFlowRate ("Flow Map Cycle Rate (per s)", Float) = 0.08
        _AuroraPulse ("Pulse: Breathing Amount", Range(0, 1)) = 0
        _AuroraPulseSpeed ("Pulse: Breathing Speed (rad per s)", Float) = 0.6
        _AuroraWave ("Pulse: Surges along the Curtain", Range(0, 2)) = 0
        _AuroraWaveSpeed ("Pulse: Surge Speed (rad per s)", Float) = 0.8
        _AuroraFlicker ("Pulse: Local Flicker", Range(0, 1)) = 0
        _AuroraSegments ("Segments: Side Offset, Side Half Width, Centre Amount, Centre Half Width (rad)", Vector) = (0.8, 0.55, 0.3, 0.3)
        _AuroraTaper ("Tail Lobe: Amount, Width Scale, Top (v), Side Sign (+1 / -1)", Vector) = (1, 1, 1.2, 1)
        _AuroraLengthVar ("Curtain Length Variation (bottom edge up / down)", Range(0, 0.6)) = 0
        _AuroraCentreCyan ("Centre Cyan (gradient input scale)", Range(0, 1)) = 1
        _AuroraSway ("Curtain Sway (up / down along the sky)", Range(0, 0.4)) = 0.15
        _AuroraUndulate ("Undulation: Amplitude (v), Waves along the Curtain, Speed (rad/s), Even Twist (0 fans out .. 1 even)", Vector) = (0, 3, 0.6, 0)
        _AuroraLevels ("Levels: In Low, In High, Gamma, Out High", Vector) = (0.05, 0.8, 0.8, 1)
        _AuroraGrad0 ("Gradient Map 0 (dim)", Color) = (0.25, 0.12, 0.45, 1)
        _AuroraGrad1 ("Gradient Map 1", Color) = (0.25, 0.4, 0.95, 1)
        _AuroraGrad2 ("Gradient Map 2", Color) = (0.3, 0.9, 1, 1)
        _AuroraGrad3 ("Gradient Map 3 (bright)", Color) = (0.85, 1, 0.95, 1)
        _AuroraGradHeight ("Gradient Input: Mask (0) .. Height (1)", Range(0, 1)) = 0.25
        _AuroraHSL ("HSL: Hue Shift (deg), Saturation x, Lightness +", Vector) = (0, 1, 0, 0)
        _AuroraLow ("Colour Low (bottom edge)", Color) = (0.25, 1, 0.75, 1)
        _AuroraHigh ("Colour High (top)", Color) = (0.65, 0.35, 1, 1)
        _AuroraRays ("Vertical Rays", Range(0, 1)) = 0.5
        _AuroraPatches ("Brightness Patches", Range(0, 1)) = 0.6
        _AuroraSpeed ("Drift Speed (repeats / s)", Float) = 0.004
        _AuroraStream ("Stream: Direction (+1 / -1 along the curtain), Speed (turns / s), Wander (0 one way .. 1 noise field), -", Vector) = (-1, 0, 1, 0)
        _AuroraToon ("Toon Steps (0 smooth)", Range(0, 6)) = 3
        _AuroraHorizon ("Horizon Fade (view elevation sin: start, end)", Vector) = (0.02, 0.18, 0, 0)
        _AuroraFocus ("Focus (world dir xyz, w = radius rad; w 0 = whole sky)", Vector) = (0, 0.5, 1, 0)
        _AuroraGlow ("Horizon Glow under the aurora (lights the scene)", Range(0, 1)) = 0


        _SunColor ("Sun Colour", Color) = (1, 0.97, 0.85, 1)
        _SunBrightness ("Sun Brightness", Float) = 1
        _SunSize ("Sun Radius (rad)", Range(0.005, 0.2)) = 0.045
        _HaloSize ("Halo Ring Radius (rad)", Range(0.01, 0.5)) = 0.11
        _HaloAmount ("Halo Ring Amount", Range(0, 1)) = 0.3
        _GlowPower ("Glow Falloff", Range(1, 64)) = 10
        _GlowAmount ("Glow Amount", Range(0, 1)) = 0.25

        [Header(Far Clouds)]
        _CloudLitColor ("Cloud Lit", Color) = (1, 1, 1, 1)
        _CloudShadowColor ("Cloud Shadow", Color) = (0.72, 0.76, 0.92, 1)
        _CloudScale ("Cloud Scale", Float) = 1.2
        _CloudCurve ("Dome Curve (lower = flatter near horizon)", Range(0.05, 1)) = 0.3
        _CloudCoverage ("Coverage Threshold (higher = fewer)", Range(0, 1)) = 0.56
        _CloudEdge ("Extra Edge Softness", Range(0, 0.05)) = 0.001
        _CloudLightOffset ("Light Sample Offset", Range(0, 0.5)) = 0.12
        _CloudLitBias ("Lit Bias", Range(-0.2, 0.2)) = 0.02
        _CloudWind ("Wind (xy per second)", Vector) = (0.012, 0.004, 0, 0)
        _CloudSpeed ("Cloud Speed (multiplies Wind)", Float) = 1
        _CloudHorizonFade ("Horizon Fade Height", Range(0.01, 0.5)) = 0.12
        _CloudOpacity ("Opacity (> 1 extrapolates)", Range(0, 2)) = 1
    }

    SubShader
    {
        Tags { "Queue" = "Background" "RenderType" = "Background" "PreviewType" = "Skybox" "RenderPipeline" = "UniversalPipeline" }
        Cull Off ZWrite Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"   // RgbToHsv / HsvToRgb (aurora HSL)

            CBUFFER_START(UnityPerMaterial)
                half4 _ZenithColor, _HorizonColor, _GroundColor;
                half _GradientPower, _GroundFade;
                half4 _OverallColor;
                half4 _MidColor, _BandColor;
                half _MidHeight, _BandHeight, _BandAmount, _Dither;
                half4 _SunsetColor, _SunsetHotColor;
                half _SunsetAmount, _SunsetHeight, _SunsetSpread;
                float _VolAmount, _VolBottom, _VolTop, _VolScale, _VolCoverage, _VolDensity, _VolSteps;
                float4 _VolWind, _VolHorizonFade, _VolSunSideFade;
                float _VolLightStep, _VolLightAbsorb, _VolErode, _VolShadeThreshold, _VolEdge, _VolSideFalloff;
                half4 _VolLitSun, _VolShadowSun, _VolLitFar, _VolShadowFar;
                float _VolStepLength, _VolMaxSteps, _VolJitter, _VolLightSteps, _VolPowder, _VolSilver, _VolSilverG, _VolMorph;
                float _VolLobeSize, _VolScallop, _VolInnerScallop, _VolSkin, _VolDebugMask;
                float4 _VolHaze;
                half4 _VolRimColor;
                half4 _SunColor;
                half _SunBrightness;
                half _SunSize, _HaloSize, _HaloAmount, _GlowPower, _GlowAmount;
                half _PlanetAmount, _PlanetSize, _PlanetBands, _PlanetBandAmount, _PlanetRimWidth, _RingAmount, _Moon2Size;
                half _PlanetSkyDraw;
                float4 _PlanetDir, _RingInnerOuter, _Moon2Dir;
                half4 _PlanetLit, _PlanetShadow, _PlanetBand, _PlanetRim, _RingColor, _Moon2Lit, _Moon2Shadow;
                float4 _Moon3Dir, _Moon4Dir, _GiantDir, _GiantAxis;
                half _PlanetAxisSign;
                float _GiantSpin, _PlanetSpin, _RingSpin, _GiantStorm;
                half4 _StormColor;
                float4 _Moon2Orbit, _Moon3Orbit, _Moon4Orbit;
                float4 _AuroraHorizon, _AuroraFocus, _AuroraArc, _AuroraBandPlane;
                half _AuroraRepeat, _AuroraDetailTile, _AuroraFlowAmount, _AuroraFlowSpeed, _AuroraSway, _AuroraGradHeight;
                float4 _AuroraUndulate, _AuroraStream;
                half _AuroraTwist, _AuroraFlowStrength, _AuroraFlowRate;
                half _AuroraPulse, _AuroraPulseSpeed, _AuroraWave, _AuroraWaveSpeed, _AuroraFlicker;
                float4 _AuroraSegments, _AuroraTaper;
                half _AuroraLengthVar, _AuroraCentreCyan;
                float4 _AuroraLevels, _AuroraHSL;
                half4 _AuroraGrad0, _AuroraGrad1, _AuroraGrad2, _AuroraGrad3;
                half _AuroraGlow;
                half _AuroraAmount, _AuroraRays, _AuroraPatches, _AuroraSpeed, _AuroraToon;
                half4 _AuroraLow, _AuroraHigh;
                half _Moon3Size, _Moon4Size, _BodyMid, _BodyLimb, _BodyHaze, _BodyHazeLow;
                half _GiantAmount, _GiantSize, _GiantBands, _GiantBandAmount, _GiantRimWidth;
                half4 _GiantLit, _GiantShadow, _GiantBand, _GiantRim;
                half _StarAmount, _StarDensity, _StarTwinkle;
                float4 _StarFar, _StarNear, _StarBright, _GalaxyPlane;
                half4 _StarWarm, _StarCool;
                half _StarTintAmount, _StarBandBoost;
                float4 _StarBlink, _GalaxyDrift;
                half _GalaxyAmount, _GalaxyBright, _GalaxyToon, _GalaxySteps;
                half4 _GalaxyCore, _GalaxyEdge;
                float4 _GalaxyTile, _GalBig, _GalBigShape, _GalGroup, _GalGroupCfg;
                half4 _StarColor;
                float _StarScale;
                half4 _CloudLitColor, _CloudShadowColor;
                float _CloudScale, _CloudCurve, _CloudCoverage, _CloudEdge, _CloudLightOffset, _CloudLitBias;
                float4 _CloudWind;
                float _CloudSpeed;
                half _CloudHorizonFade, _CloudOpacity;
            CBUFFER_END

            // authored cloud shapes (SkyCloudShapes): baked signed distance, up to 4 shapes in RGBA
            TEXTURE3D(_DSEWA_SkyShapeTex); SAMPLER(sampler_DSEWA_SkyShapeTex);
            TEXTURE2D(_AuroraMain); SAMPLER(sampler_AuroraMain);
            TEXTURE2D(_AuroraDetail); SAMPLER(sampler_AuroraDetail);
            TEXTURE2D(_AuroraFlow); SAMPLER(sampler_AuroraFlow);
            TEXTURE2D(_AuroraBand); SAMPLER(sampler_AuroraBand);
            TEXTURE2D(_GalaxyMap); SAMPLER(sampler_GalaxyMap);

            // art direction: keep the aurora in one part of the sky (around a focus direction), soft edge
            float AuroraFocusMask(float3 dir)
            {
                if (_AuroraFocus.w <= 0) return 1;
                float a = acos(clamp(dot(dir, normalize(_AuroraFocus.xyz)), -1, 1));
                return 1 - smoothstep(_AuroraFocus.w * 0.45, _AuroraFocus.w, a);
            }

            // Aurora curtains wrapped round the sky (Aurora_* maps from Art/Environment/Sky/AuroraMaps.sbs):
            // u = azimuth (the maps tile sideways), v = elevation between Arc bottom and top. Flow (RG) wobbles the
            // uv, MainMask is the curtain silhouette, DetailNoise the torn vertical streaks, BandMask big bright and dim
            // bands drifting along. Low cyan -> high lavender, brightness cut into toon steps. Additive emission.
            half3 AuroraLayer(float3 dir, float2 unused)
            {
                float up = dir.y;
                float fade = smoothstep(_AuroraHorizon.x, _AuroraHorizon.y, up) * AuroraFocusMask(dir);
                if (fade <= 0 || _AuroraAmount <= 0) return 0;
                float t = _Time.y;
                // curtain coordinates: band mode (_AuroraBand.w > 0.5) hangs the curtain on a tilted great circle -
                // u runs along the circle, e is the angle off it towards the band normal, so the rays stay parallel even
                // high in the sky; otherwise u = azimuth and e = elevation (curtain wrapped round the horizon)
                float uw, e, uwC;
                float3 fdir = normalize(_AuroraFocus.xyz);
                if (_AuroraBandPlane.w > 0.5)
                {
                    float3 nb = normalize(_AuroraBandPlane.xyz);
                    float3 t1 = normalize(cross(nb, float3(0, 1, 0)) + float3(1e-5, 0, 0));
                    float3 t2 = cross(nb, t1);
                    uw = atan2(dot(dir, t2), dot(dir, t1)) * 0.15915494;
                    uwC = atan2(dot(fdir, t2), dot(fdir, t1)) * 0.15915494;
                    e = asin(clamp(dot(dir, nb), -1, 1));
                }
                else
                {
                    uw = atan2(dir.x, dir.z) * 0.15915494;
                    uwC = atan2(fdir.x, fdir.z) * 0.15915494;
                    e = asin(saturate(up));
                }
                // position along the curtain relative to the focus (ringed planet), radians, wrapped
                float along = (frac(uw - uwC + 0.5) - 0.5) * 6.2831853;
                // measure along the curtain from the focus: the atan2 seam (uw = +-0.5) moves to the far side of the
                // sky, away from the visible curtain (the non-integer noise lookups below jumped there)
                uw = along * 0.15915494;
                // stream: everything that moves along the curtain (pattern, flow map, undulation, surges) travels the
                // same way (_AuroraStream.x = +1 / -1 along the band circle), so the whole curtain flows towards one end
                float sdir = _AuroraStream.x >= 0 ? 1 : -1;
                float u = uw * _AuroraRepeat - sdir * t * (_AuroraSpeed + _AuroraStream.y * _AuroraRepeat);
                float v = (e - radians(_AuroraArc.x)) / max(radians(_AuroraArc.y - _AuroraArc.x), 1e-3);
                // the whole curtain sways along its length (big S curves instead of a flat band)
                v += (sin(uw * 6.2831853 * 2 + 1.3) * 0.6 + sin(uw * 6.2831853 * 5 + t * 0.05) * 0.4) * _AuroraSway;
                // undulation: waves run along the curtain and lift / drop it as a whole (bottom and top together),
                // two wave trains at different lengths and speeds so the heave never repeats exactly
                float und = sin(uw * 6.2831853 * _AuroraUndulate.y - sdir * t * _AuroraUndulate.z) * 0.65
                          + sin(uw * 6.2831853 * _AuroraUndulate.y * 2.3 - sdir * t * _AuroraUndulate.z * 1.37 + 2.1) * 0.35;
                v += und * _AuroraUndulate.x;
                // curtains of different lengths: shift the bottom edge up / down along the curtain with noise
                half lenN = SAMPLE_TEXTURE2D_LOD(_AuroraBand, sampler_AuroraBand, float2(uw * 2.3 + 0.17, 0.5), 0).r;
                half lenN2 = SAMPLE_TEXTURE2D_LOD(_AuroraFlow, sampler_AuroraFlow, float2(uw * 5.1, 0.73), 0).r;
                v += ((lenN - 0.5) * 1.4 + (lenN2 - 0.5) * 0.6) * _AuroraLengthVar;
                float inArc = smoothstep(0, 0.04, v) * (1 - smoothstep(0.96, 1, v));
                if (inArc <= 0) return 0;
                // mip from v only (continuous; u jumps at the atan2 seam)
                float lod = max(log2(fwidth(v) * 1024 + 1e-4), 0);
                // flow / noise field (Aurora_Distortion RG, -1..1), drifting slowly
                half2 fl = SAMPLE_TEXTURE2D_LOD(_AuroraFlow, sampler_AuroraFlow, float2(u * 0.5, v * 0.5) + t * _AuroraFlowSpeed * float2(lerp(0, -sdir, _AuroraStream.z), 0.4), 0).rg * 2 - 1;
                // 1) noise twist: bend the curtain sideways, more towards its top -> folds and curls
                float2 uv = float2(u, v);
                // (the bend no longer grows towards the top: that fanned the rays out radially)
                uv.x += fl.x * _AuroraTwist * lerp(0.25 + v, 0.5, _AuroraUndulate.w);
                uv.y += fl.y * _AuroraTwist * 0.15;
                uv += fl * _AuroraFlowAmount * float2(1, 0.5);
                // 2) flow map: advect the curtain along the field, two phases half a cycle apart, cross-faded
                //    (the stretch of each phase resets while the other one shows -> endless flow, no smearing)
                float ph = t * _AuroraFlowRate;
                float p0 = frac(ph), p1 = frac(ph + 0.5);
                float fw = abs(p0 * 2 - 1);                                          // 1 when phase 0 resets -> show phase 1
                // advection mostly along the stream, the noise field only adds a little wander (_AuroraStream.z)
                float2 adv = lerp(float2(sdir, 0), fl * float2(1, 0.35), _AuroraStream.z) * _AuroraFlowStrength;
                float2 uv0 = uv - adv * p0, uv1 = uv - adv * p1;
                uv1.x += 0.37;                                                       // sideways offset hides the repeat
                uv0.y = saturate(uv0.y); uv1.y = saturate(uv1.y);
                half m = lerp(SAMPLE_TEXTURE2D_LOD(_AuroraMain, sampler_AuroraMain, uv0, lod).r,
                              SAMPLE_TEXTURE2D_LOD(_AuroraMain, sampler_AuroraMain, uv1, lod).r, fw);
                half det = lerp(SAMPLE_TEXTURE2D_LOD(_AuroraDetail, sampler_AuroraDetail, float2(uv0.x * _AuroraDetailTile, uv0.y), lod).r,
                                SAMPLE_TEXTURE2D_LOD(_AuroraDetail, sampler_AuroraDetail, float2(uv1.x * _AuroraDetailTile, uv1.y), lod).r, fw);
                half band = SAMPLE_TEXTURE2D_LOD(_AuroraBand, sampler_AuroraBand, float2(u * 0.7, v), lod).r;
                // 1) grayscale aurora mask
                float val = m * lerp(1, 0.4 + 0.8 * det, _AuroraRays) * lerp(1, 0.5 + 0.8 * band, _AuroraPatches) * inArc;
                // intensity pulse (before levels / gradient map, so a surge also shifts the colour towards the bright end):
                // breathing of the whole curtain, bright surges running along it, and a fast local flicker
                // sines alone tick like a metronome: multiply them by noise (drifting in time and varying along the curtain)
                half2 nT = SAMPLE_TEXTURE2D_LOD(_AuroraFlow, sampler_AuroraFlow, float2(t * 0.013, t * 0.0071 + 0.31), 0).rg;   // 1D-ish time noise
                half nS = SAMPLE_TEXTURE2D_LOD(_AuroraBand, sampler_AuroraBand, float2(u * 0.35 - sdir * t * 0.02, 0.5), 0).r;      // along the curtain
                float sine = 0.6 * sin(t * _AuroraPulseSpeed) + 0.4 * sin(t * _AuroraPulseSpeed * 2.37 + 1.7);
                float breathe = 1 + _AuroraPulse * sine * (0.3 + 1.4 * nT.x) * (0.5 + nS);
                float surge = smoothstep(0.55, 1, 0.5 + 0.5 * sin(uw * 6.2831853 * 3 - sdir * t * _AuroraWaveSpeed + v * 2.5 + nS * 3));
                surge *= saturate(nT.y * 1.6 - 0.2) * (0.4 + 1.2 * nS);
                half flick = SAMPLE_TEXTURE2D_LOD(_AuroraBand, sampler_AuroraBand, float2(u * 1.3 - sdir * t * 0.07, v * 0.5 - t * 0.12), lod).r;
                val *= max(breathe, 0) * (1 + _AuroraWave * surge) * (1 + _AuroraFlicker * (flick * 2 - 1));
                // segments: big lobes left and right of the focus, a weak thin layer in the centre (behind the planet)
                // asymmetric lobes: the lead lobe is full, the tail lobe (_AuroraTaper) is weaker, narrower and shorter
                float sa = along * (_AuroraTaper.w < 0 ? -1 : 1);
                float hwT = _AuroraSegments.y * _AuroraTaper.y;
                float lead = 1 - smoothstep(_AuroraSegments.y * 0.4, _AuroraSegments.y, abs(sa + _AuroraSegments.x));
                float tail = 1 - smoothstep(hwT * 0.2, hwT, abs(sa - _AuroraSegments.x));
                tail *= 1 - smoothstep(0.2, 1, (sa - _AuroraSegments.x) / max(hwT, 1e-3));           // fades out towards its far end
                tail *= _AuroraTaper.x * (1 - smoothstep(_AuroraTaper.z - 0.15, _AuroraTaper.z, v));
                float side = max(lead, tail);
                float centre = 1 - smoothstep(_AuroraSegments.w * 0.5, _AuroraSegments.w, abs(along));
                float thin = 1 - smoothstep(0.42, 0.6, v);                               // centre keeps only its lower layer
                val *= max(side, centre * _AuroraSegments.z * thin);
                // 2) levels: in low / in high / gamma / out high (soften the contrast)
                float g = saturate((val - _AuroraLevels.x) / max(_AuroraLevels.y - _AuroraLevels.x, 1e-3));
                g = pow(g, _AuroraLevels.z) * _AuroraLevels.w;
                // 3) gradient map: 4 stops by mask value (optionally mixed with the height in the curtain)
                float gp = saturate(lerp(g, saturate(v), _AuroraGradHeight));
                gp *= lerp(_AuroraCentreCyan, 1, side);                                  // bright cyan mostly on the side lobes
                half3 c = gp < 0.333 ? lerp(_AuroraGrad0.rgb, _AuroraGrad1.rgb, gp * 3)
                        : gp < 0.666 ? lerp(_AuroraGrad1.rgb, _AuroraGrad2.rgb, gp * 3 - 1)
                                     : lerp(_AuroraGrad2.rgb, _AuroraGrad3.rgb, gp * 3 - 2);
                // 4) HSL tuning: hue shift (deg), saturation multiplier, lightness offset
                half3 hsv = RgbToHsv(c);
                hsv.x = frac(hsv.x + _AuroraHSL.x / 360.0);
                hsv.y = saturate(hsv.y * _AuroraHSL.y);
                c = HsvToRgb(hsv);
                c = saturate(c + _AuroraHSL.z);
                half3 acc = c * g;
                if (_AuroraToon > 0.5)
                {
                    float lum = max(max(acc.r, acc.g), acc.b);
                    float q = floor(lum * _AuroraToon + 0.35) / _AuroraToon;
                    acc *= q / max(lum, 1e-4);
                }
                return acc * fade * _AuroraAmount;
            }
            float4 _DSEWA_SkyShapeBox[16];      // world centre xyz, cube edge (m)
            float4 _DSEWA_SkyShapeRot[16];      // cos yaw, sin yaw, vertical stretch, channel + density / 8
            float4 _DSEWA_SkyShapeParams;       // count, procedural cut (0 keep .. 1 remove), lowest / highest world y

            struct Attributes { float4 positionOS : POSITION; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; float3 dir : TEXCOORD0; UNITY_VERTEX_OUTPUT_STEREO };

            Varyings vert(Attributes input)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                o.dir = input.positionOS.xyz;
                return o;
            }

            float Hash21(float2 p)
            {
                p = frac(p * float2(123.34, 456.21));
                p += dot(p, p + 45.32);
                return frac(p.x * p.y);
            }

            float ValueNoise2(float2 p)
            {
                float2 i = floor(p), f = frac(p);
                f = f * f * (3 - 2 * f);
                return lerp(lerp(Hash21(i), Hash21(i + float2(1, 0)), f.x),
                            lerp(Hash21(i + float2(0, 1)), Hash21(i + float2(1, 1)), f.x), f.y);
            }

            // Puffy fbm: big round lumps first, small detail weak so the toon edge stays clean
            float CloudDensity(float2 p)
            {
                return ValueNoise2(p) * 0.55 + ValueNoise2(p * 2.03 + 7.1) * 0.28 + ValueNoise2(p * 4.11 + 13.7) * 0.12
                     + ValueNoise2(p * 8.3 + 29.3) * 0.05;
            }

            // ---- Toon volumetric layer: value-noise volume between two heights, few march steps, toon-cut result
            float Hash31(float3 p)
            {
                p = frac(p * 0.1031);
                p += dot(p, p.zyx + 31.32);
                return frac((p.x + p.y) * p.z);
            }

            float ValueNoise3(float3 p)
            {
                float3 i = floor(p), f = frac(p);
                f = f * f * (3 - 2 * f);
                float a = lerp(Hash31(i), Hash31(i + float3(1, 0, 0)), f.x);
                float b = lerp(Hash31(i + float3(0, 1, 0)), Hash31(i + float3(1, 1, 0)), f.x);
                float c = lerp(Hash31(i + float3(0, 0, 1)), Hash31(i + float3(1, 0, 1)), f.x);
                float d = lerp(Hash31(i + float3(0, 1, 1)), Hash31(i + float3(1, 1, 1)), f.x);
                return lerp(lerp(a, b, f.y), lerp(c, d, f.y), f.z);
            }

            // Cellular (Worley) puffs: 1 at a feature point, 0 one cell away -> round lobes like cumulus
            float Puffs(float3 p)
            {
                float3 i = floor(p), f = frac(p);
                float d = 1;
                [unroll] for (int z = -1; z <= 1; z++)
                [unroll] for (int y = -1; y <= 1; y++)
                [unroll] for (int x = -1; x <= 1; x++)
                {
                    float3 o = float3(x, y, z);
                    float3 h = float3(Hash31(i + o), Hash31(i + o + 17.3), Hash31(i + o + 41.7));
                    d = min(d, length(o + h - f));
                }
                return 1 - saturate(d);
            }

            // 2D cellular lobes: 1 at a cell's feature point, 0 one cell away (round bumps, dents between them)
            float Lobes2D(float2 p)
            {
                float2 i = floor(p), f = frac(p);
                float d = 1;
                [unroll] for (int y = -1; y <= 1; y++)
                [unroll] for (int x = -1; x <= 1; x++)
                {
                    float2 o = float2(x, y);
                    float2 h = float2(Hash21(i + o), Hash21(i + o + 23.7));
                    d = min(d, length(o + h - f));
                }
                return 1 - saturate(d);
            }

            // ---- Cumulus as a union of domes (design v3) -------------------------------------------------------
            // Seen from below a cumulus outline is a union of circles (round lobes, sharp dents between them);
            // thresholding smooth noise always gives smooth curves, so the shape is built from domes instead:
            // a 2D cover noise says where clouds are, each grid cell plants one dome (random spot / radius / height),
            // cells near the edge of the cover get smaller, lower domes; a half-size grid adds small lobes.

            // where clouds are (plan view, metres, drifting with the wind); same 0..1 range as before
            float CloudCover2D(float2 x)
            {
                float2 q = x * _VolScale;
                return ValueNoise2(q) * 0.62 + ValueNoise2(q * 2.03 + 7.1) * 0.38;
            }

            // height (m above the layer bottom) of the highest dome over plan position x; 0 outside every dome
            float DomeField(float2 x, float cell, float minR, float maxR, float coverBias, float seed)
            {
                float2 g = x / cell;
                float2 i = floor(g);
                float best = 0;
                float thick = _VolTop - _VolBottom;
                [unroll] for (int y = -1; y <= 1; y++)
                [unroll] for (int xo = -1; xo <= 1; xo++)
                {
                    float2 c0 = i + float2(xo, y) + seed;
                    float2 c = (i + float2(xo, y) + float2(Hash21(c0), Hash21(c0 + 23.7)) * 0.8 + 0.1) * cell;
                    float k = saturate((CloudCover2D(c) - _VolCoverage + coverBias) * 5);   // 0 outside the cloud area
                    float r = cell * lerp(minR, maxR, Hash21(c0 + 51.3)) * sqrt(k);
                    float dd = length(x - c) / max(r, 1e-3);
                    float top = thick * lerp(0.45, 1.0, Hash21(c0 + 77.7)) * k;
                    best = max(best, dd < 1 ? top * sqrt(1 - dd * dd) : 0);
                }
                return best;
            }

            float PlanPos(float3 p, out float2 x) { x = p.xz - _VolWind.xy * _Time.y; return p.y - _VolBottom; }

            // metres inside the nearest authored shape (negative outside); p is camera-relative like the march
            float ShapeInside(float3 p, out float dens)
            {
                float best = -1e5; dens = 0;
                int n = (int)_DSEWA_SkyShapeParams.x;
                float3 pw = p + _WorldSpaceCameraPos;
                [loop] for (int i = 0; i < n; i++)
                {
                    float4 b = _DSEWA_SkyShapeBox[i];
                    float4 r = _DSEWA_SkyShapeRot[i];
                    float3 q = (pw - b.xyz) / b.w;
                    q.y /= r.z;
                    q.xz = float2(r.x * q.x - r.y * q.z, r.y * q.x + r.x * q.z);   // undo the yaw
                    if (any(abs(q) > 0.5)) continue;
                    int ch = (int)floor(r.w);
                    float4 s = SAMPLE_TEXTURE3D_LOD(_DSEWA_SkyShapeTex, sampler_DSEWA_SkyShapeTex, q + 0.5, 0);
                    float sd = ch == 0 ? s.r : ch == 1 ? s.g : ch == 2 ? s.b : s.a;
                    float inside = -sd * b.w * min(1, r.z);
                    if (inside > best) { best = inside; dens = frac(r.w) * 8; }
                }
                return best;
            }

            // cheap version for the sun samples: big domes only
            float VolDensityCoarse(float3 p)
            {
                float2 x; float hgt = PlanPos(p, x);
                float dome = DomeField(x, _VolLobeSize, 0.7, 1.15, 0, 0);
                float d = saturate((dome - hgt) / _VolSkin) * saturate(hgt / 30) * (1 - _DSEWA_SkyShapeParams.y);
                if (_DSEWA_SkyShapeParams.x > 0)
                {
                    float sdens; float sin_ = ShapeInside(p, sdens);
                    d = max(d, saturate(sin_ / _VolSkin) * sdens);
                }
                return d;
            }

            float VolDensity(float3 p, float skin)
            {
                float2 x; float hgt = PlanPos(p, x);
                float big = DomeField(x, _VolLobeSize, 0.7, 1.15, 0, 0);
                float small = DomeField(x, _VolLobeSize * 0.45, 0.6, 1.0, _VolScallop * 0.1, 17.0) * 0.75;
                float dome = max(big, small);
                // a little 3D erosion on the dome skin keeps the tops from looking like perfect spheres
                float erode = (1 - Puffs(float3(x.x, p.y, x.y) * _VolScale * 6)) * _VolErode * 60;
                dome -= erode;
                // soft skin must be thicker than a march step, or the ray skips the surface between steps (streaks);
                // the caller passes max(_VolSkin, step) so long low-angle rays get a softer skin instead of stripes
                float d = saturate((dome - hgt) / skin) * saturate(hgt / max(30, skin * 0.5))   // flat base ramp follows the step too
                        * (1 - _DSEWA_SkyShapeParams.y);
                if (_DSEWA_SkyShapeParams.x > 0)
                {
                    // authored shapes: same skin + erosion, no flat base (they can float)
                    float sdens; float sin_ = ShapeInside(p, sdens);
                    d = max(d, saturate((sin_ - erode) / skin) * sdens);
                }
                return d;
            }

            float HenyeyGreenstein(float cosT, float g)
            {
                float g2 = g * g;
                return (1 - g2) / (4 * PI * pow(max(1 + g2 - 2 * g * cosT, 1e-4), 1.5));
            }

            // returns rgb = toon colour, a = coverage (already toon-cut)
            half4 VolumetricLayer(float3 dir, float3 L, float2 px)
            {
                float up = dir.y;
                // towards the sun the painted cloud cards own the horizon, so the volumetrics stop higher there
                float sunCos = dot(normalize(dir.xz + 1e-5), normalize(L.xz + 1e-5));
                float arcIn = cos(radians(_VolSunSideFade.z)), arcOut = cos(radians(min(_VolSunSideFade.z + _VolSunSideFade.w, 180)));
                float sunSide = smoothstep(arcOut, arcIn, sunCos);
                float2 fadeRange = lerp(_VolHorizonFade.xy, _VolSunSideFade.xy, sunSide);
                float fade = smoothstep(fadeRange.x, fadeRange.y, up);
                if (fade <= 0 || _VolAmount <= 0) return 0;
                // authored shapes may reach above / below the layer: march their height range too
                float bottomH = _VolBottom, topH = _VolTop;
                if (_DSEWA_SkyShapeParams.x > 0)
                {
                    bottomH = max(min(bottomH, _DSEWA_SkyShapeParams.z - _WorldSpaceCameraPos.y), 1);
                    topH = max(topH, _DSEWA_SkyShapeParams.w - _WorldSpaceCameraPos.y);
                }
                float t0 = bottomH / up, t1 = topH / up;
                // more steps when the ray crosses the layer at a low angle (long path) -> no step bands near the horizon
                int steps = (int)clamp(ceil((t1 - t0) / max(_VolStepLength, 1)), _VolSteps, _VolMaxSteps);
                float dt = (t1 - t0) / steps;
                // interleaved gradient noise: low-grain per-pixel start offset, the toon cut hides what is left
                float ign = frac(52.9829189 * frac(dot(px, float2(0.06711056, 0.00583715))));
                float jitter = lerp(0.5, ign, _VolJitter);
                float cosT = dot(dir, L);
                float powderW = _VolPowder * (0.5 - 0.5 * cosT);                    // powder only when looking away from the sun
                int lSteps = (int)_VolLightSteps;
                float trans = 1, litSum = 0, aSum = 0;
                [loop] for (int k = 0; k < 96; k++)
                {
                    if (k >= steps || trans < 0.02) break;
                    float3 p = dir * (t0 + (k + jitter) * dt);
                    float d = VolDensity(p, max(_VolSkin, dt * 1.6));
                    if (d <= 0) continue;
                    float dl = 0;
                    [loop] for (int j = 1; j <= 4; j++)
                    {
                        if (j > lSteps) break;
                        dl += VolDensityCoarse(p + L * (_VolLightStep * j));
                    }
                    float beer = exp(-dl * _VolLightAbsorb / lSteps * 1.5);
                    float powder = 1 - exp(-d * 4);
                    float light = beer * lerp(1, powder, powderW);
                    float a = 1 - exp(-d * dt * 0.004);
                    litSum += trans * a * light;
                    aSum += trans * a;
                    trans *= 1 - a;
                }
                float cover = 1 - trans;
                // mid-plane coordinates (metres, drifting with the wind) for the optional inner shade lobes
                float2 plane = dir.xz * ((_VolBottom + _VolTop) * 0.5 / up) - _VolWind.xy * _Time.y;
                float2 lp = plane / max(_VolLobeSize, 1);
                float coverS = cover;   // outline lobes are carved in VolDensity (columns); offsetting the projected
                                        // cover here barely moved the edge because cover jumps 0 -> 1 within a few pixels
                // toon cuts: crisp silhouette and two-tone shading, like the painted cards
                float w = fwidth(coverS) + _VolEdge;
                float alpha = smoothstep(0.5 - w, 0.5 + w, coverS);
                float lit = aSum > 1e-4 ? litSum / aSum : 1;
                // lobed shadow boundary inside: only near the light/shadow edge (applied everywhere it printed dots
                // wherever a lobe peak crossed the threshold on a flat-lit area)
                float bandL = 1 - smoothstep(0.06, 0.25, abs(lit - _VolShadeThreshold));
                lit += (Lobes2D(lp * 1.45 + 5.1) - 0.45) * _VolInnerScallop * bandL;
                float wl = fwidth(lit) + 0.02;
                lit = smoothstep(_VolShadeThreshold - wl, _VolShadeThreshold + wl, lit);
                // same colour rule as CloudSunLight: warm towards the sun's azimuth, cool on the far side
                float side = pow(saturate(dot(normalize(dir.xz + 1e-5), normalize(L.xz + 1e-5)) * 0.5 + 0.5), _VolSideFalloff);
                half3 litCol = lerp(_VolLitFar.rgb, _VolLitSun.rgb, side);
                half3 shadowCol = lerp(_VolShadowFar.rgb, _VolShadowSun.rgb, side);
                half3 col = lerp(shadowCol, litCol, lit);
                // silver lining: the thin rim of clouds seen towards the sun (HG forward scattering), cut as a toon band
                float hg = HenyeyGreenstein(cosT, _VolSilverG) / HenyeyGreenstein(1, _VolSilverG);
                float rim = (1 - smoothstep(0.62 - w, 0.62 + w, coverS)) * alpha;   // outer band of the silhouette
                col = lerp(col, _VolRimColor.rgb, saturate(rim * hg * _VolSilver * 4));
                return half4(col, alpha * fade * _VolAmount);
            }

            // Toon celestial body: disc of angular radius `size` around direction P, lit by L (2-tone, crisp
            // terminator), optional gas-giant bands, atmosphere rim and a tilted ring. Returns rgb + coverage.
            half4 CelestialBody(float3 dir, float3 L, float3 P, float size, half3 litCol, half3 shadowCol,
                                half3 bandCol, half3 rimCol, half bandAmount, half bands, half rimWidth, half ringAmount,
                                float2 axisTiltRoll, float spin, half spot)
            {
                P = normalize(P);
                float3 right = normalize(cross(float3(0, 1, 0), P));
                float3 upv = cross(P, right);
                float s = sin(size);
                float2 q = float2(dot(dir, right), dot(dir, upv)) / s;   // planet radii, small-angle disc
                float front = step(0, dot(dir, P));                       // only the hemisphere around P
                float r = length(q);
                float aa = fwidth(r) * 1.5;
                half4 o = 0;
                // ring (squashed ellipse, tilted); the back half is drawn first and hidden by the disc
                float ringA = 0, ringFront = 0;
                if (ringAmount > 0)
                {
                    float c = cos(_RingInnerOuter.z), sn = sin(_RingInnerOuter.z);
                    float2 rq = float2(c * q.x + sn * q.y, -sn * q.x + c * q.y);
                    float e = length(float2(rq.x, rq.y / max(_RingInnerOuter.w, 0.05)));
                    float ew = fwidth(e) * 1.5;
                    ringA = smoothstep(_RingInnerOuter.x - ew, _RingInnerOuter.x + ew, e) * (1 - smoothstep(_RingInnerOuter.y - ew, _RingInnerOuter.y + ew, e));
                    ringA *= 0.75 + 0.25 * step(0.5, frac(e * 6));            // a couple of flat toon gaps
                    // the ring turns: brighter / dimmer clumps and faint spokes travel round it
                    float th = atan2(rq.y / max(_RingInnerOuter.w, 0.05), rq.x);
                    float tr = _Time.y * _RingSpin;
                    // toon clumps: crisp-edged dim patches along the ring (they read even on a small ring)
                    float clump = sin(th * 4 - tr + e * 5) + 0.5 * sin(th * 9 - tr * 1.3 - e * 3);
                    float cw = fwidth(clump) + 0.05;
                    ringA *= lerp(1, 0.45, smoothstep(0.35 - cw, 0.35 + cw, clump)) * (0.9 + 0.1 * sin(th * 17 - tr * 2.0));
                    ringFront = rq.y < 0 ? 1 : 0;
                    o = half4(_RingColor.rgb, ringA * ringAmount * (1 - ringFront));
                }
                // atmosphere rim just outside the disc
                float rim = (1 - smoothstep(1, 1 + rimWidth, r)) * smoothstep(1 - aa, 1 + aa, r);
                o.rgb = lerp(o.rgb, rimCol, rim * 0.8);
                o.a = max(o.a, rim * 0.8);
                // disc
                float disc = 1 - smoothstep(1 - aa, 1 + aa, r);
                // derivatives outside the branch (divergent control flow)
                float z = sqrt(saturate(1 - r * r));
                float3 n = normalize(q.x * right + q.y * upv - z * P + 1e-5);     // surface facing the viewer
                float ndl = dot(n, L);
                float w = fwidth(ndl) + 0.02;
                if (disc > 0)
                {
                    float lit = smoothstep(-0.05 - w, -0.05 + w, ndl);
                    half3 col = lerp(shadowCol, litCol, lit);
                    // optional third toon step: a mid band just inside the terminator (rounder body)
                    float lit2 = smoothstep(0.35 - w, 0.35 + w, ndl);
                    col = lerp(col, lerp(lerp(shadowCol, litCol, 0.55), litCol, lit2), lit * _BodyMid);
                    if (bandAmount > 0)
                    {
                        // bands follow latitude on the sphere: the spin axis is rolled on screen and tipped towards the
                        // viewer, so the bands curve round the ball instead of running as flat screen lines
                        float3 axis = normalize(cos(axisTiltRoll.y) * upv - sin(axisTiltRoll.y) * right);   // roll matches the ring (CCW on screen)
                        axis = normalize(axis * cos(axisTiltRoll.x) - P * sin(axisTiltRoll.x));
                        float lat = dot(n, axis);
                        // longitude angle about the spin axis (e2 points at the viewer: no seam on the visible side);
                        // spin turns it, so the band waves and storms drift across the ball
                        float3 e1 = normalize(cross(axis, P) + 1e-5);
                        float3 e2 = normalize(-P - axis * dot(-P, axis) + 1e-5);
                        float phi = atan2(dot(n, e1), dot(n, e2)) + spin;
                        float b = sin((lat + 0.05 * sin(phi * 3.0 + lat * 5.0) + 0.025 * sin(phi * 7.0 - lat * 11.0)) * bands * 3.14159);
                        col = lerp(col, col * bandCol * 1.3, step(0.35, b) * bandAmount);
                        if (spot > 0)
                        {
                            // storm spot on the northern belt (the giant sits on the horizon): rides the spin across the disc
                            float dp = atan2(sin(phi), cos(phi));                   // longitude from the spot, wrapped
                            float sd = length(float2(dp / 0.5, (lat - 0.62) / 0.1));
                            float sw = fwidth(sd) + 0.02;
                            float core = 1 - smoothstep(0.62 - sw, 0.62 + sw, sd);
                            float ring = (1 - smoothstep(1 - sw, 1 + sw, sd)) - core;
                            col = lerp(col, col * bandCol * 1.45, ring * spot);
                            col = lerp(col, _StormColor.rgb * lerp(0.45, 1, lit), core * spot);
                        }
                    }
                    // limb darkening: the edge of a sphere turns away -> darker, reads as a ball, not a disc
                    col *= 1 - _BodyLimb * pow(saturate(r), 6) * 0.5;
                    // thin bright limb on the lit side
                    col = lerp(col, rimCol, smoothstep(0.86, 0.97, r) * lit * 0.6);
                    o.rgb = lerp(o.rgb, col, disc);
                    o.a = max(o.a, disc);
                }
                if (ringFront > 0)
                {
                    o.rgb = lerp(o.rgb, _RingColor.rgb * lerp(0.75, 1, saturate(dot(L, upv) * 0.5 + 0.5)), ringA * ringAmount);
                    o.a = max(o.a, ringA * ringAmount);
                }
                o.a *= front;
                return o;
            }

            // how close to the galaxy band circle (1 on the circle, gaussian falloff over the half width)
            float GalaxyBandMask(float3 dir)
            {
                float e = asin(clamp(dot(dir, normalize(_GalaxyPlane.xyz)), -1, 1));
                float x = e / radians(max(_GalaxyPlane.w, 0.1));
                return exp(-x * x);
            }

            // soft value cut into a few flat steps (toon), blended by amount
            float ToonSteps(float x, float steps, float amount)
            {
                float q = floor(saturate(x) * steps + 0.5) / steps;
                return lerp(x, q, amount);
            }

            // Galaxy band (milky way seen edge-on): a soft glow along a great circle, broken into clumps (B) and
            // crossed by dark dust lanes near its spine (A). Returns rgb to add.
            half3 GalaxyBand(float3 dir)
            {
                if (_GalaxyAmount <= 0) return 0;
                float3 nb = normalize(_GalaxyPlane.xyz);
                float3 t1 = normalize(cross(nb, float3(0, 1, 0)) + float3(1e-5, 0, 0));
                float3 t2 = cross(nb, t1);
                float u = atan2(dot(dir, t2), dot(dir, t1)) * 0.15915494;
                float x = asin(clamp(dot(dir, nb), -1, 1)) / radians(max(_GalaxyPlane.w, 0.1));
                if (abs(x) > 3) return 0;
                // the band breathes in width and brightness along its length
                half along = SAMPLE_TEXTURE2D_LOD(_GalaxyMap, sampler_GalaxyMap, float2(u * 1.7, 0.23), 0).b;
                float w = lerp(0.75, 1.3, along);
                float glow = exp(-(x * x) / (w * w));
                float tg = _Time.y;
                half clump0 = SAMPLE_TEXTURE2D_LOD(_GalaxyMap, sampler_GalaxyMap, float2(u * _GalaxyTile.x + tg * _GalaxyDrift.x, x * 0.12 + 0.5), 0).b;
                half clump1 = SAMPLE_TEXTURE2D_LOD(_GalaxyMap, sampler_GalaxyMap, float2(u * _GalaxyTile.x * 1.37 - tg * _GalaxyDrift.x * 0.6 + 0.41, x * 0.15 + 0.31), 0).b;
                // two clump layers drifting apart, cross-faded in waves running along the band -> the glow churns
                half clump = lerp(clump0, clump1, _GalaxyDrift.z * (0.5 + 0.5 * sin(tg * 0.3 + u * 9)));
                glow *= lerp(1, 0.35 + clump * 1.1, _GalaxyTile.z) * lerp(0.55, 1.2, along);
                // dust lanes hug the spine (the map repeats 3 times vertically: stay inside one period)
                half dust = SAMPLE_TEXTURE2D_LOD(_GalaxyMap, sampler_GalaxyMap, float2(u * _GalaxyTile.y + tg * _GalaxyDrift.y, x * 0.09 + 0.5), 0).a;
                glow *= 1 - dust * _GalaxyTile.w * exp(-x * x * 2.5);
                glow = ToonSteps(glow, _GalaxySteps, _GalaxyToon);
                half3 col = lerp(_GalaxyEdge.rgb, _GalaxyCore.rgb, saturate(glow * 1.3 - 0.2));
                return col * glow * _GalaxyBright * _GalaxyAmount;
            }

            // one galaxy sprite: the R (spiral) or G (flocculent) map laid on the sky around P, rolled and squashed by
            // its tilt, plus a bright bulge. Returns brightness in .x and the bulge share in .y.
            float2 GalaxySprite(float3 dir, float3 P, float size, float roll, float tilt, float type)
            {
                P = normalize(P);
                if (dot(dir, P) < 0.9) return 0;
                float3 right = normalize(cross(float3(0, 1, 0), P) + 1e-5);
                float3 upv = cross(P, right);
                float2 q = float2(dot(dir, right), dot(dir, upv)) / max(size, 1e-4);
                float c = cos(roll), sn = sin(roll);
                q = float2(c * q.x + sn * q.y, -sn * q.x + c * q.y);
                q.y /= max(tilt, 0.05);
                // slow spin in the galaxy's own plane (after the tilt is undone)
                float sa = _Time.y * _GalaxyDrift.w, cs = cos(sa), ss = sin(sa);
                q = float2(cs * q.x - ss * q.y, ss * q.x + cs * q.y);
                float r2 = dot(q, q);
                if (r2 > 1.2) return 0;
                half4 m = SAMPLE_TEXTURE2D_LOD(_GalaxyMap, sampler_GalaxyMap, q * 0.5 + 0.5, 0);
                float arms = lerp(m.r, m.g * 0.8, step(0.5, type)) * (1 - smoothstep(0.6, 1.1, r2));
                float bulge = exp(-r2 * 28) * 1.2 + exp(-r2 * 6) * 0.25;
                float total = arms * 0.8 + bulge;
                return float2(total, saturate(bulge / max(total, 1e-3)));
            }

            // all galaxies: one big neighbour + a small group scattered by hash around a centre direction
            half3 Galaxies(float3 dir)
            {
                half3 sum = 0;
                if (_GalBigShape.w > 0)
                {
                    float2 g = GalaxySprite(dir, _GalBig.xyz, _GalBig.w, _GalBigShape.x, _GalBigShape.y, _GalBigShape.z);
                    float b = ToonSteps(g.x * 0.8, _GalaxySteps + 1, _GalaxyToon);
                    sum += lerp(_GalaxyEdge.rgb, _GalaxyCore.rgb, g.y) * b * _GalBigShape.w;
                }
                int n = (int)_GalGroupCfg.x;
                if (n > 0)
                {
                    float3 C = normalize(_GalGroup.xyz);
                    if (dot(dir, C) > cos(_GalGroup.w + _GalGroupCfg.z * 2))
                    {
                        float3 cr = normalize(cross(float3(0, 1, 0), C) + 1e-5);
                        float3 cu = cross(C, cr);
                        [loop] for (int i = 0; i < 6; i++)
                        {
                            if (i >= n) break;
                            float fi = i + 1.37;
                            float h1 = frac(sin(fi * 12.9898) * 43758.5453), h2 = frac(sin(fi * 78.233) * 43758.5453);
                            float h3 = frac(sin(fi * 39.425) * 43758.5453), h4 = frac(sin(fi * 93.989) * 43758.5453);
                            float a = h1 * 6.2831853, rr = sqrt(h2) * _GalGroup.w;
                            float3 P = normalize(C + (cr * cos(a) + cu * sin(a)) * rr);
                            float size = lerp(_GalGroupCfg.y, _GalGroupCfg.z, h3 * h3);
                            float2 g = GalaxySprite(dir, P, size, h4 * 6.28, lerp(0.25, 0.95, h2), step(0.5, h3));
                            float b = ToonSteps(g.x * 0.8, _GalaxySteps, _GalaxyToon);
                            sum += lerp(_GalaxyEdge.rgb, _GalaxyCore.rgb, g.y) * b * _GalGroupCfg.w * lerp(0.5, 1, h4);
                        }
                    }
                }
                return sum;
            }

            // one star layer: a random dot per occupied cell of a 3D grid around the sky (crisp, toon), optional
            // 4-point sparkle arms for the near layer. Returns brightness in .x, the cell hash in .y (colour pick).
            float2 StarLayer(float3 dir, float4 cfg, float density, float arm, float seed)
            {
                float3 sp = dir * cfg.x + seed;
                float3 cell = floor(sp), f = frac(sp);
                float h = Hash31(cell);
                if (h <= 1 - density) return 0;
                float3 c = float3(Hash31(cell + 7.1), Hash31(cell + 13.7), Hash31(cell + 29.3)) * 0.5 + 0.25;
                float size = lerp(cfg.z, cfg.w, Hash31(cell + 3.3));
                float3 d3 = f - c;
                float d = length(d3);
                float dw = fwidth(d);
                float star = 1 - smoothstep(size - dw, size + dw, d);
                if (arm > 0)
                {
                    // sparkle: thin cross in the sky's local frame (horizontal / vertical on screen)
                    float3 rt = normalize(cross(float3(0, 1, 0), dir) + 1e-5);
                    float3 uv3 = cross(dir, rt);
                    float ox = dot(d3, rt), oy = dot(d3, uv3);
                    float th = size * 0.22 + dw;
                    float len = arm * lerp(0.5, 1, Hash31(cell + 5.9));
                    float lx = (1 - smoothstep(0, len, abs(ox))) * (1 - smoothstep(th * 0.5, th, abs(oy)));
                    float ly = (1 - smoothstep(0, len, abs(oy))) * (1 - smoothstep(th * 0.5, th, abs(ox)));
                    star = max(star, max(lx, ly) * 0.8);
                }
                // each star twinkles on its own: own speed, phase and depth (the cell hash h is ~1 for every lit
                // cell, so it cannot drive this), two sines beating against each other + a rare deep blink
                float hs = Hash31(cell + 19.1), hp = Hash31(cell + 23.7) * 6.2831853, hd = Hash31(cell + 31.9);
                float sp1 = lerp(_StarBlink.x, _StarBlink.y, hs);
                float wob = 0.6 * sin(_Time.y * sp1 + hp) + 0.4 * sin(_Time.y * sp1 * 2.31 + hp * 1.7);
                float blink = pow(saturate(0.5 + 0.5 * sin(_Time.y * sp1 * 0.21 + hp * 3.1)), 24) * step(1 - _StarBlink.z, hd);
                float tw = saturate(1 - _StarTwinkle * lerp(0.4, 1, hd) * (0.5 + 0.5 * wob) - blink * _StarBlink.w);
                return float2(star * tw, Hash31(cell + 11.3));
            }

            // moon on a tilted elliptical orbit round a parent body (orb: radius rad, period s, flatten, phase rad);
            // radius 0 keeps the fixed direction. front = 1 on the near half (drawn over the parent), 0 behind it.
            float3 OrbitDir(float3 fixedDir, float3 parent, float4 orb, float roll, out float front)
            {
                front = 1;
                if (orb.x <= 0) return normalize(fixedDir);
                float3 P = normalize(parent);
                float3 right = normalize(cross(float3(0, 1, 0), P));
                float3 upv = cross(P, right);
                float a = orb.w + 6.2831853 * _Time.y / max(orb.y, 1);
                float2 o = float2(cos(a), sin(a) * orb.z) * orb.x;
                float c = cos(roll), sn = sin(roll);
                float2 q = float2(c * o.x - sn * o.y, sn * o.x + c * o.y);   // same tilt as the ring
                front = sin(a) < 0 ? 1 : 0;
                return normalize(P + right * q.x + upv * q.y);
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 dir = normalize(i.dir);
                float3 L = normalize(_MainLightPosition.xyz);
                float up = dir.y;

                // Gradient: horizon -> zenith above, horizon -> ground-tinted haze below (hides the ground plane edge)
                // 3-stop gradient: horizon -> mid (at Mid Height) -> zenith; Gradient Power shapes the elevation
                float t = pow(saturate(up), _GradientPower);
                half3 color = t < _MidHeight
                    ? lerp(_HorizonColor.rgb, _MidColor.rgb, smoothstep(0, 1, t / _MidHeight))
                    : lerp(_MidColor.rgb, _ZenithColor.rgb, smoothstep(0, 1, (t - _MidHeight) / (1 - _MidHeight)));
                if (up < 0) color = lerp(_HorizonColor.rgb, _GroundColor.rgb, saturate(-up * _GroundFade));
                // Bright haze band hugging the horizon (both sides, so it also hides the ground's far edge)
                color = lerp(color, _BandColor.rgb, (1 - smoothstep(0, _BandHeight, abs(up))) * _BandAmount);

                // Sunset glow: warm horizon only on the sun's side of the sky, hotter right at the horizon.
                // Uses the sun's azimuth (not its height), so it works with the sun low over the horizon.
                float az = saturate(dot(normalize(dir.xz + 1e-5), normalize(L.xz + 1e-5)) * 0.5 + 0.5);
                float azMask = pow(az, _SunsetSpread);
                float hMask = 1 - smoothstep(0, _SunsetHeight, up > 0 ? up : -up * 4);
                half3 sunset = lerp(_SunsetColor.rgb, _SunsetHotColor.rgb, hMask * azMask);
                color = lerp(color, sunset, saturate(hMask * azMask * _SunsetAmount));
                color *= _OverallColor.rgb;

                half3 skyBase = color;   // sky without stars: the haze colour for the bodies (no stars through the giant)
                // Stars: one random dot per occupied grid cell around the sky sphere, crisp (toon) with a slow
                // twinkle; fade out towards the horizon band. Clouds drawn later cover them.
                // Three depth layers: far = dense, tiny and dim; mid = the old field; near = sparse, bigger, with sparkle
                // arms. Far and mid crowd towards the galaxy band. Each star gets a warm or cool tint.
                if (_StarAmount > 0 && up > 0)
                {
                    float boost = 1 + _StarBandBoost * GalaxyBandMask(dir);
                    float2 sf = StarLayer(dir, _StarFar, _StarFar.y * boost, 0, 17.3);
                    float2 sm = StarLayer(dir, float4(_StarScale, _StarDensity, 0.05, 0.13), _StarDensity * lerp(1, boost, 0.5), 0, 0);
                    float2 sn = StarLayer(dir, _StarNear, _StarNear.y, _StarBright.w, 41.7);
                    float fadeUp = _StarAmount * smoothstep(0.03, 0.25, up);
                    half3 tf = lerp(_StarColor.rgb, sf.y > 0.5 ? _StarWarm.rgb : _StarCool.rgb, _StarTintAmount * abs(sf.y * 2 - 1));
                    half3 tm = lerp(_StarColor.rgb, sm.y > 0.5 ? _StarWarm.rgb : _StarCool.rgb, _StarTintAmount * abs(sm.y * 2 - 1));
                    half3 tn = lerp(_StarColor.rgb, sn.y > 0.5 ? _StarWarm.rgb : _StarCool.rgb, _StarTintAmount * abs(sn.y * 2 - 1));
                    color += (tf * sf.x * _StarBright.x + tm * sm.x * _StarBright.y + tn * sn.x * _StarBright.z) * fadeUp;
                }

                // galaxy band and galaxies: behind the planets, faded at the horizon like the stars
                if (_StarAmount > 0 && up > 0)
                {
                    float gFade = _StarAmount * smoothstep(0.02, 0.2, up);
                    color += (GalaxyBand(dir) + Galaxies(dir)) * gFade;
                }

                // Alien sky, far to near: a giant planet rising from the horizon, small moons, then the ringed planet
                // (behind the clouds, in front of the stars).
                // Atmospheric perspective: every body takes some of the sky colour behind it, more near the horizon.
                half3 skyBehind = skyBase;
                float bodyHaze = saturate(_BodyHaze + (1 - smoothstep(0, 0.35, up)) * _BodyHazeLow);
                float horizonFade = smoothstep(-0.02, 0.08, up);
                // moons: orbiting the ringed planet (2, 4) and the giant (3); behind their parent first, in front after
                float f2, f3, f4;
                float3 d2 = OrbitDir(_Moon2Dir.xyz, _PlanetDir.xyz, _Moon2Orbit, _RingInnerOuter.z, f2);
                float3 d3 = OrbitDir(_Moon3Dir.xyz, _GiantDir.xyz, _Moon3Orbit, 0.15, f3);
                float3 d4 = OrbitDir(_Moon4Dir.xyz, _PlanetDir.xyz, _Moon4Orbit, _RingInnerOuter.z, f4);
                half4 m2 = 0, m3 = 0, m4 = 0;
                if (_PlanetAmount > 0 && up > -0.05)
                {
                    m2 = CelestialBody(dir, L, d2, max(_Moon2Size, 1e-3), _Moon2Lit.rgb, _Moon2Shadow.rgb, _PlanetBand.rgb, _PlanetRim.rgb, 0, 0, 0.05, 0, float2(0, 0), 0, 0);
                    m3 = CelestialBody(dir, L, d3, max(_Moon3Size, 1e-3), _Moon2Lit.rgb * 0.85, _Moon2Shadow.rgb, _PlanetBand.rgb, _PlanetRim.rgb, 0, 0, 0.05, 0, float2(0, 0), 0, 0);
                    m4 = CelestialBody(dir, L, d4, max(_Moon4Size, 1e-3), _Moon2Lit.rgb * 0.95, _Moon2Shadow.rgb * 1.1, _PlanetBand.rgb, _PlanetRim.rgb, 0, 0, 0.05, 0, float2(0, 0), 0, 0);
                }
                float k = _PlanetAmount * horizonFade;
                float a2 = m2.a * k * step(1e-3, _Moon2Size) * _PlanetSkyDraw, a3 = m3.a * k * step(1e-3, _Moon3Size), a4 = m4.a * k * step(1e-3, _Moon4Size) * _PlanetSkyDraw;
                half3 c2 = lerp(m2.rgb, skyBehind, bodyHaze), c3 = lerp(m3.rgb, skyBehind, bodyHaze), c4 = lerp(m4.rgb, skyBehind, bodyHaze);

                color = lerp(color, c3, a3 * (1 - f3));
                if (_GiantAmount > 0 && up > -0.05)
                {
                    half4 gi = CelestialBody(dir, L, _GiantDir.xyz, _GiantSize, _GiantLit.rgb, _GiantShadow.rgb,
                                             _GiantBand.rgb, _GiantRim.rgb, _GiantBandAmount, _GiantBands, _GiantRimWidth, 0, _GiantAxis.xy,
                                             _Time.y * _GiantSpin, _GiantStorm);
                    gi.rgb = lerp(gi.rgb, skyBehind, bodyHaze);
                    // stars must not show through the giant's disc
                    color = lerp(color, gi.rgb, gi.a * _GiantAmount * smoothstep(-0.03, 0.04, up));
                }
                color = lerp(color, c3, a3 * f3);
                color = lerp(color, c2, a2 * (1 - f2));
                color = lerp(color, c4, a4 * (1 - f4));
                // the ringed planet and moons 2 / 4 are 3D meshes when SkyRingedPlanet is on (_PlanetSkyDraw = 0)
                if (_PlanetAmount > 0 && up > -0.05 && _PlanetSkyDraw > 0.5)
                {
                    half4 pl = CelestialBody(dir, L, _PlanetDir.xyz, _PlanetSize, _PlanetLit.rgb, _PlanetShadow.rgb,
                                             _PlanetBand.rgb, _PlanetRim.rgb, _PlanetBandAmount, _PlanetBands, _PlanetRimWidth, _RingAmount,
                                             float2(asin(saturate(_RingInnerOuter.w)) * _PlanetAxisSign, _RingInnerOuter.z),   // axis follows the ring
                                             _Time.y * _PlanetSpin, 0);
                    color = lerp(color, lerp(pl.rgb, skyBehind, bodyHaze * 0.7), pl.a * k);
                }
                color = lerp(color, c2, a2 * f2);
                color = lerp(color, c4, a4 * f4);

                // Aurora: in the upper atmosphere, so in front of the planets and moons (additive glow)
                if (_AuroraAmount > 0 && up > 0)
                {
                    color += AuroraLayer(dir, 0);
                }
                // glow the aurora casts on the low sky under it (same azimuth as the focus): ties it to the scene
                if (_AuroraAmount > 0 && _AuroraGlow > 0)
                {
                    float3 fd = normalize(float3(_AuroraFocus.x, 0, _AuroraFocus.z) + 1e-5);
                    float az = saturate(dot(normalize(float3(dir.x, 0, dir.z) + 1e-5), fd));
                    float band = (1 - smoothstep(-0.05, 0.35, abs(up - 0.04))) * pow(az, 3);
                    color += lerp(_AuroraLow.rgb, _AuroraHigh.rgb, saturate(up * 2)) * band * _AuroraGlow * _AuroraAmount * 0.35;
                }

                // Sun: soft glow, flat halo ring, hard disc
                float cosA = dot(dir, L);
                float ang = acos(clamp(cosA, -1, 1));
                float aa = fwidth(ang);
                // Toon sun: soft glow + flat halo ring in the sun colour, hard-edged disc at Sun Brightness (HDR)
                color += _SunColor.rgb * pow(saturate(cosA), _GlowPower) * _GlowAmount;
                color = lerp(color, _SunColor.rgb, (1 - smoothstep(_HaloSize - aa, _HaloSize + aa, ang)) * _HaloAmount);
                color = lerp(color, _SunColor.rgb * _SunBrightness, 1 - smoothstep(_SunSize - aa, _SunSize + aa, ang));

                // Overhead toon volumetric clouds (cover the sun when they pass in front of it)
                if (up > 0 && _VolAmount > 0)
                {
                    half4 vol = VolumetricLayer(dir, L, i.positionCS.xy);
                    if (_VolDebugMask > 0.5) return half4(vol.aaa / max(_VolAmount, 1e-3), 1);   // silhouette for measuring
                    // aerial perspective: low (far) clouds take the horizon sky colour and thin out
                    float haze = (1 - smoothstep(_VolHaze.x, _VolHaze.y, up)) * _VolHaze.z;
                    vol.rgb = lerp(vol.rgb, color, haze);
                    vol.a *= 1 - haze * 0.5;
                    color = lerp(color, vol.rgb, vol.a);
                }

                // Far clouds on a flattened dome: xz / (y + curve) so they shrink towards the horizon
                if (up > 0)
                {
                    float2 uv = dir.xz / (up + _CloudCurve) * _CloudScale + _CloudWind.xy * _CloudSpeed * _Time.y;
                    float d = CloudDensity(uv);
                    // Edges one pixel wide (fwidth) + _CloudEdge: the density changes slowly, a fixed width blurs
                    float w = fwidth(d) + _CloudEdge;
                    float cover = smoothstep(_CloudCoverage - w, _CloudCoverage + w, d);
                    float2 toSun = normalize(L.xz + 1e-4) * _CloudLightOffset;
                    float split = d - CloudDensity(uv + toSun) + _CloudLitBias;
                    half lit = smoothstep(-fwidth(split), fwidth(split), split);
                    half3 cloud = lerp(_CloudShadowColor.rgb, _CloudLitColor.rgb, lit);
                    cloud += _SunColor.rgb * pow(saturate(cosA), _GlowPower * 0.5) * _GlowAmount * lit;   // brighter near the sun
                    // Unclamped lerp: UE's Cloud Opacity 1.2157 pushes the cloud past its colour, as the original does
                    color += (cloud - color) * (cover * smoothstep(0, _CloudHorizonFade, up) * _CloudOpacity);
                }
                // +-0.5 LSB dither against banding in the long smooth gradient
                float2 px = i.positionCS.xy;
                color += (frac(sin(dot(px, float2(12.9898, 78.233))) * 43758.5453) - 0.5) * (_Dither / 255.0);
                return half4(color, 1);
            }
            ENDHLSL
        }
    }
}
