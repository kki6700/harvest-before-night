using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Shows how full the basket is: the basket model already contains ~90 fruit pieces stacked from the
/// bottom up, so the lowest N are switched on for the current fill fraction (0 = empty, 1 = heaped).
/// </summary>
public class BasketFill : MonoBehaviour
{
    [Tooltip("Parent of the fruit pieces inside the basket.")]
    public Transform fruitRoot;

    readonly List<GameObject> _pieces = new List<GameObject>();

    void Awake()
    {
        if (fruitRoot == null) fruitRoot = transform.Find("Basket_Fruits");
        if (fruitRoot == null) return;
        foreach (Transform t in fruitRoot) _pieces.Add(t.gameObject);
        // bottom layer first, so the basket fills upward
        _pieces.Sort((a, b) => a.transform.localPosition.y.CompareTo(b.transform.localPosition.y));
        SetFill(0f);
    }

    public void SetFill(float fraction)
    {
        int show = Mathf.RoundToInt(Mathf.Clamp01(fraction) * _pieces.Count);
        for (int i = 0; i < _pieces.Count; i++) _pieces[i].SetActive(i < show);
    }
}
