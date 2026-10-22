using System;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.SceneManagement;

/// <summary>
/// Stage rules for "밤이 오기 전 수확": the round runs from 14:00 to 22:00 in game time (roundSeconds of real
/// time) and drives the DayNightBlend sky with it. Customers keep coming to the shop door and pay for their
/// orders; earn goal coins before night to win. When the clock reaches 22:00 first, the round is lost. Ready -> Playing -> Won / Lost.
/// Enter starts, R restarts the scene, Esc pauses. Goal and round length are my own values.
/// </summary>
[DefaultExecutionOrder(-100)]
public class GameDirector : MonoBehaviour
{
    public enum State { Ready, Playing, Paused, Won, Lost }

    [Header("Rules")]
    [Tooltip("Coins to earn before night.")]
    public int goal = 500;
    [Tooltip("Real seconds from the start hour to the end hour.")]
    public float roundSeconds = 180f;
    public float startHour = 14f;
    public float endHour = 22f;

    [Header("Scene")]
    public CatController cat;
    public CatHarvester harvester;
    public DeliveryPoint delivery;
    public DayNightBlend dayNight;

    public State Current { get; private set; } = State.Ready;
    public float Elapsed { get; private set; }
    public float Remaining => Mathf.Max(0f, roundSeconds - Elapsed);
    public float Hour => Mathf.Lerp(startHour, endHour, Elapsed / roundSeconds);
    public int Delivered => delivery != null ? delivery.Delivered : 0;
    public int Coins => delivery != null ? delivery.Coins : 0;
    public int Served => delivery != null ? delivery.Served : 0;
    /// <summary>Fruits picked over the whole round (delivered + still in the basket).</summary>
    public int Harvested { get; private set; }
    public event Action<State> StateChanged;

    int _lastCarried;

    void Awake()
    {
        if (cat == null) cat = FindAnyObjectByType<CatController>();
        if (harvester == null) harvester = FindAnyObjectByType<CatHarvester>();
        if (delivery == null) delivery = FindAnyObjectByType<DeliveryPoint>();
        if (dayNight == null) dayNight = FindAnyObjectByType<DayNightBlend>();
    }

    void Start()
    {
        if (delivery != null) delivery.Paid += OnPaid;
        if (harvester != null) harvester.CarriedChanged += OnCarried;
        SetHour(startHour);
        SetState(State.Ready);
    }

    void OnDestroy()
    {
        if (delivery != null) delivery.Paid -= OnPaid;
        if (harvester != null) harvester.CarriedChanged -= OnCarried;
        Time.timeScale = 1f;
    }

    void Update()
    {
        var kb = Keyboard.current;
        switch (Current)
        {
            case State.Ready:
                if (kb != null && (kb.enterKey.wasPressedThisFrame || kb.numpadEnterKey.wasPressedThisFrame)) Begin();
                break;
            case State.Playing:
                if (kb != null && kb.escapeKey.wasPressedThisFrame) { Pause(true); break; }
                Elapsed += Time.deltaTime;
                SetHour(Hour);
                if (Elapsed >= roundSeconds) SetState(State.Lost);
                break;
            case State.Paused:
                if (kb != null && kb.escapeKey.wasPressedThisFrame) Pause(false);
                if (kb != null && kb.rKey.wasPressedThisFrame) Restart();
                break;
            case State.Won:
            case State.Lost:
                if (kb != null && (kb.rKey.wasPressedThisFrame || kb.enterKey.wasPressedThisFrame)) Restart();
                break;
        }
    }

    public void Begin()
    {
        if (Current != State.Ready) return;
        Elapsed = 0f;
        SetState(State.Playing);
    }

    public void Pause(bool on)
    {
        if (on && Current == State.Playing) SetState(State.Paused);
        else if (!on && Current == State.Paused) SetState(State.Playing);
    }

    public void Restart()
    {
        Time.timeScale = 1f;
        SceneManager.LoadScene(SceneManager.GetActiveScene().buildIndex);
    }

    void OnPaid(int coins, int gained)
    {
        if (Current == State.Playing && coins >= goal) SetState(State.Won);
    }

    void OnCarried(int carried)
    {
        if (carried > _lastCarried) Harvested += carried - _lastCarried;
        _lastCarried = carried;
    }

    void SetHour(float h)
    {
        if (dayNight != null) dayNight.hour = h;
    }

    void SetState(State s)
    {
        Current = s;
        Time.timeScale = s == State.Paused ? 0f : 1f;
        if (cat != null) cat.gameLocked = s != State.Playing;
        StateChanged?.Invoke(s);
    }
}
