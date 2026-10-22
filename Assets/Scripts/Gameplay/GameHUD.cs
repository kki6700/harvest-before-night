using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem.UI;
using UnityEngine.UI;

/// <summary>
/// Screen UI for the stage, built in code so the scene only needs this one component:
/// clock + time bar (top left), coins / basket / current order (top right), "+n원" pop-up when a customer pays,
/// action hint (bottom),
/// start, pause and result panels in the middle. Korean text uses the Windows "Malgun Gothic" font
/// through a dynamic OS font. Colours come from the team palette (abyss #06161F, cyan #62F2E1,
/// gold #FFD27A, violet #A08BFF); sizes and layout are my own.
/// </summary>
public class GameHUD : MonoBehaviour
{
    public GameDirector director;
    public CatHarvester harvester;

    // The overlay UI here is drawn into the linear buffer and gamma-encoded once more on output (measured: the
    // panel #06161F came out as #1A5151, teal), so palette colours are given as their linear values.
    static readonly Color Abyss = Lin(0x06, 0x16, 0x1F, 0xF0);
    static readonly Color Cyan = Lin(0x62, 0xF2, 0xE1, 0xFF);
    static readonly Color Gold = Lin(0xFF, 0xD2, 0x7A, 0xFF);
    static readonly Color Violet = Lin(0xA0, 0x8B, 0xFF, 0xFF);
    static readonly Color Ink = Lin(0xE8, 0xF4, 0xF2, 0xFF);

    static Color Lin(byte r, byte g, byte b, byte a)
    {
        Color c = ((Color)new Color32(r, g, b, 255)).linear;
        c.a = a / 255f;
        return c;
    }

    Font _font;
    Text _clock, _remain, _delivered, _basket, _order, _prompt, _popup, _resultTitle, _resultBody;
    float _popupT = 99f;
    Image _timeFill, _goalFill;
    GameObject _ready, _paused, _result;

    void Awake()
    {
        if (director == null) director = FindAnyObjectByType<GameDirector>();
        if (harvester == null) harvester = FindAnyObjectByType<CatHarvester>();
        _font = Font.CreateDynamicFontFromOSFont(new[] { "Malgun Gothic", "맑은 고딕", "Arial" }, 32);
        Build();
    }

    void OnEnable()
    {
        if (director != null) director.StateChanged += OnState;
        if (director != null && director.delivery != null) director.delivery.Paid += OnPaid;
    }

    void OnDisable()
    {
        if (director != null) director.StateChanged -= OnState;
        if (director != null && director.delivery != null) director.delivery.Paid -= OnPaid;
    }

    void OnPaid(int coins, int gained)
    {
        _popup.text = "+" + gained + "원";
        _popupT = 0f;
    }

    void Update()
    {
        if (director == null) return;
        float h = director.Hour;
        int hh = Mathf.FloorToInt(h), mm = Mathf.FloorToInt((h - hh) * 60f / 10f) * 10;
        _clock.text = string.Format("{0} {1}:{2:00}", hh < 12 ? "오전" : "오후", hh > 12 ? hh - 12 : hh, mm);
        float rem = director.Remaining;
        _remain.text = string.Format("밤까지 {0}:{1:00}", (int)rem / 60, (int)rem % 60);
        float t = Mathf.Clamp01(rem / director.roundSeconds);
        _timeFill.fillAmount = t;
        _timeFill.color = Color.Lerp(Violet, Gold, t);
        _delivered.text = string.Format("돈  {0} / {1}원", director.Coins, director.goal);
        _goalFill.fillAmount = Mathf.Clamp01((float)director.Coins / director.goal);
        var dp = director.delivery;
        if (dp != null)
            _order.text = dp.IsReady ? string.Format("손님 주문  {0} / {1}개", dp.Filled, dp.Order)
                        : dp.Current == DeliveryPoint.Phase.Paying ? "고마워요!" : "다음 손님이 오는 중…";
        // pop-up rises and fades over 1.6 s
        _popupT += Time.unscaledDeltaTime;
        float k = Mathf.Clamp01(_popupT / 1.6f);
        _popup.gameObject.SetActive(k < 1f);
        ((RectTransform)_popup.transform).anchoredPosition = new Vector2(22, -160 - 50f * k);
        _popup.color = new Color(Gold.r, Gold.g, Gold.b, 1f - k * k);
        if (harvester != null)
        {
            _basket.text = string.Format("바구니  {0} / {1}", harvester.Carried, harvester.capacity);
            _basket.color = harvester.IsFull ? Gold : Ink;
            _prompt.text = director.Current == GameDirector.State.Playing ? harvester.Prompt : "";
        }
        _prompt.transform.parent.gameObject.SetActive(_prompt.text.Length > 0);
    }

    void OnState(GameDirector.State s)
    {
        _ready.SetActive(s == GameDirector.State.Ready);
        _paused.SetActive(s == GameDirector.State.Paused);
        _result.SetActive(s == GameDirector.State.Won || s == GameDirector.State.Lost);
        if (s == GameDirector.State.Won)
        {
            _resultTitle.text = "수확 성공!";
            _resultTitle.color = Gold;
            float rem = director.Remaining;
            _resultBody.text = string.Format("밤이 오기 전에 {0}원을 벌었어요.\n손님 {1}명 · 열매 {2}개 납품 · 남은 시간 {3}:{4:00}",
                director.Coins, director.Served, director.Delivered, (int)rem / 60, (int)rem % 60);
        }
        else if (s == GameDirector.State.Lost)
        {
            _resultTitle.text = "밤이 찾아왔어요";
            _resultTitle.color = Violet;
            _resultBody.text = string.Format("번 돈 {0} / {1}원 · 손님 {2}명 · 열매 {3}개\n조금만 더 서두르면 할 수 있어요!",
                director.Coins, director.goal, director.Served, director.Delivered);
        }
    }

    // ---------- building ----------
    void Build()
    {
        if (FindAnyObjectByType<EventSystem>() == null)
            new GameObject("EventSystem", typeof(EventSystem), typeof(InputSystemUIInputModule));

        var canvasGo = new GameObject("HUD Canvas", typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
        canvasGo.transform.SetParent(transform, false);
        var canvas = canvasGo.GetComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        canvas.sortingOrder = 10;
        var scaler = canvasGo.GetComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920, 1080);
        scaler.matchWidthOrHeight = 0.5f;
        var root = canvasGo.transform;

        // top left: clock + time bar
        var clockPanel = Panel(root, "Clock", new Vector2(0, 1), new Vector2(32, -32), new Vector2(380, 132));
        _clock = Label(clockPanel, "오후 2:00", 44, Ink, TextAnchor.UpperLeft, new Vector2(22, -14), new Vector2(340, 56));
        _remain = Label(clockPanel, "밤까지 3:00", 24, Cyan, TextAnchor.UpperLeft, new Vector2(22, -70), new Vector2(340, 30));
        _timeFill = Bar(clockPanel, new Vector2(22, -108), new Vector2(336, 10));

        // top right: delivered + basket
        var countPanel = Panel(root, "Counts", new Vector2(1, 1), new Vector2(-32, -32), new Vector2(380, 166));
        _delivered = Label(countPanel, "돈  0 / 500원", 34, Gold, TextAnchor.UpperLeft, new Vector2(22, -14), new Vector2(340, 46));
        _goalFill = Bar(countPanel, new Vector2(22, -64), new Vector2(316, 10));
        _basket = Label(countPanel, "바구니  0 / 12", 26, Ink, TextAnchor.UpperLeft, new Vector2(22, -84), new Vector2(320, 36));
        _order = Label(countPanel, "손님 주문", 26, Cyan, TextAnchor.UpperLeft, new Vector2(22, -120), new Vector2(340, 36));
        _popup = Label(countPanel, "", 44, Gold, TextAnchor.UpperLeft, new Vector2(22, -160), new Vector2(340, 56));
        _popup.gameObject.SetActive(false);

        // bottom: action hint
        var promptPanel = Panel(root, "Prompt", new Vector2(0.5f, 0), new Vector2(0, 60), new Vector2(560, 64));
        _prompt = Label(promptPanel, "", 30, Ink, TextAnchor.MiddleCenter, Vector2.zero, new Vector2(560, 64), true);

        // start
        _ready = Panel(root, "Ready", new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(860, 560)).gameObject;
        Label(_ready.transform, "밤이 오기 전 수확", 64, Gold, TextAnchor.UpperCenter, new Vector2(0, -40), new Vector2(860, 80), true);
        Label(_ready.transform,
            "가게 문 앞으로 외계인 손님들이 하나둘 찾아와요.\n바구니를 문 고양이가 되어 등불 열매와 버섯꽃을 수확해\n주문을 채우고, 밤 10시 전에 500원을 벌어 보세요.",
            28, Ink, TextAnchor.UpperCenter, new Vector2(0, -140), new Vector2(780, 140), true);
        Label(_ready.transform,
            "WASD 이동   ·   Shift 달리기   ·   E / Space 수확 · 납품\n마우스 오른쪽 드래그 카메라   ·   휠 줌   ·   Esc 일시 정지\n열매 1개 10원 · 주문을 다 채우면 보너스 20원 · 바구니는 12개까지",
            22, Cyan, TextAnchor.UpperCenter, new Vector2(0, -300), new Vector2(780, 110), true);
        Button(_ready.transform, "Enter  시작", new Vector2(0, -440), () => director.Begin());

        // pause
        _paused = Panel(root, "Paused", new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(560, 300)).gameObject;
        Label(_paused.transform, "일시 정지", 54, Ink, TextAnchor.UpperCenter, new Vector2(0, -40), new Vector2(560, 70), true);
        Label(_paused.transform, "Esc 계속   ·   R 처음부터", 26, Cyan, TextAnchor.UpperCenter, new Vector2(0, -130), new Vector2(560, 40), true);
        Button(_paused.transform, "계속하기", new Vector2(0, -200), () => director.Pause(false));

        // result
        _result = Panel(root, "Result", new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(760, 400)).gameObject;
        _resultTitle = Label(_result.transform, "", 64, Gold, TextAnchor.UpperCenter, new Vector2(0, -44), new Vector2(760, 84), true);
        _resultBody = Label(_result.transform, "", 28, Ink, TextAnchor.UpperCenter, new Vector2(0, -150), new Vector2(700, 110), true);
        Button(_result.transform, "R  다시 하기", new Vector2(0, -290), () => director.Restart());

        _ready.SetActive(false); _paused.SetActive(false); _result.SetActive(false);
    }

    Transform Panel(Transform parent, string name, Vector2 anchor, Vector2 pos, Vector2 size)
    {
        // border = four thin cyan strips on the edges. An Outline effect, or a cyan plate behind the
        // see-through panel, tinted the whole panel teal.
        var go = new GameObject(name, typeof(RectTransform), typeof(Image));
        go.transform.SetParent(parent, false);
        var rt = (RectTransform)go.transform;
        rt.anchorMin = rt.anchorMax = rt.pivot = anchor;
        rt.anchoredPosition = pos; rt.sizeDelta = size;
        go.GetComponent<Image>().color = Abyss;
        var edge = new Color(Cyan.r, Cyan.g, Cyan.b, 0.6f);
        Strip(go.transform, new Vector2(0, 1), new Vector2(1, 1), new Vector2(0, -2), Vector2.zero, edge);
        Strip(go.transform, new Vector2(0, 0), new Vector2(1, 0), Vector2.zero, new Vector2(0, 2), edge);
        Strip(go.transform, new Vector2(0, 0), new Vector2(0, 1), Vector2.zero, new Vector2(2, 0), edge);
        Strip(go.transform, new Vector2(1, 0), new Vector2(1, 1), new Vector2(-2, 0), Vector2.zero, edge);
        return go.transform;
    }

    static void Strip(Transform parent, Vector2 aMin, Vector2 aMax, Vector2 offMin, Vector2 offMax, Color c)
    {
        var s = new GameObject("Edge", typeof(RectTransform), typeof(Image));
        s.transform.SetParent(parent, false);
        var rt = (RectTransform)s.transform;
        rt.anchorMin = aMin; rt.anchorMax = aMax; rt.offsetMin = offMin; rt.offsetMax = offMax;
        var img = s.GetComponent<Image>(); img.color = c; img.raycastTarget = false;
    }

    Text Label(Transform parent, string text, int size, Color color, TextAnchor align, Vector2 pos, Vector2 boxSize, bool centred = false)
    {
        var go = new GameObject("Text", typeof(RectTransform), typeof(Text), typeof(Shadow));
        go.transform.SetParent(parent, false);
        var rt = (RectTransform)go.transform;
        Vector2 a = centred ? new Vector2(0.5f, 1f) : new Vector2(0f, 1f);
        if (align == TextAnchor.MiddleCenter) a = new Vector2(0.5f, 0.5f);
        rt.anchorMin = rt.anchorMax = rt.pivot = a;
        rt.anchoredPosition = pos; rt.sizeDelta = boxSize;
        var t = go.GetComponent<Text>();
        t.font = _font; t.fontSize = size; t.color = color; t.alignment = align; t.text = text;
        t.lineSpacing = 1.15f; t.horizontalOverflow = HorizontalWrapMode.Overflow; t.verticalOverflow = VerticalWrapMode.Overflow;
        go.GetComponent<Shadow>().effectColor = new Color(0, 0, 0, 0.6f);
        return t;
    }

    Image Bar(Transform parent, Vector2 pos, Vector2 size)
    {
        var bg = new GameObject("Bar", typeof(RectTransform), typeof(Image));
        bg.transform.SetParent(parent, false);
        var rt = (RectTransform)bg.transform;
        rt.anchorMin = rt.anchorMax = rt.pivot = new Vector2(0, 1);
        rt.anchoredPosition = pos; rt.sizeDelta = size;
        bg.GetComponent<Image>().color = new Color(1, 1, 1, 0.12f);
        var fill = new GameObject("Fill", typeof(RectTransform), typeof(Image));
        fill.transform.SetParent(bg.transform, false);
        var frt = (RectTransform)fill.transform;
        frt.anchorMin = Vector2.zero; frt.anchorMax = Vector2.one; frt.offsetMin = frt.offsetMax = Vector2.zero;
        var img = fill.GetComponent<Image>();
        img.sprite = Sprite.Create(Texture2D.whiteTexture, new Rect(0, 0, 4, 4), new Vector2(0.5f, 0.5f));
        img.type = Image.Type.Filled; img.fillMethod = Image.FillMethod.Horizontal; img.fillAmount = 0f; img.color = Cyan;
        return img;
    }

    void Button(Transform parent, string text, Vector2 pos, UnityEngine.Events.UnityAction onClick)
    {
        var go = new GameObject("Button", typeof(RectTransform), typeof(Image), typeof(Button));
        go.transform.SetParent(parent, false);
        var rt = (RectTransform)go.transform;
        rt.anchorMin = rt.anchorMax = rt.pivot = new Vector2(0.5f, 1f);
        rt.anchoredPosition = pos; rt.sizeDelta = new Vector2(300, 70);
        go.GetComponent<Image>().color = new Color(Cyan.r, Cyan.g, Cyan.b, 0.22f);
        var b = go.GetComponent<Button>();
        var cb = b.colors; cb.highlightedColor = new Color(1.6f, 1.6f, 1.6f, 1f); cb.pressedColor = new Color(0.8f, 0.8f, 0.8f, 1f); b.colors = cb;
        b.onClick.AddListener(onClick);
        Label(go.transform, text, 30, Cyan, TextAnchor.MiddleCenter, Vector2.zero, new Vector2(300, 70));
    }
}
