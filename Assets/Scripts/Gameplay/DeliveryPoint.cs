using System;
using UnityEngine;

/// <summary>
/// The alien customer at the shop door. The cat hands over its basket here; each fruit counts
/// toward the stage goal. Plays the customer's pick-up animation when something is delivered.
/// </summary>
public class DeliveryPoint : MonoBehaviour
{
    [Tooltip("How close the cat must come (m).")]
    public float radius = 2.2f;
    public Animator customerAnimator;
    public string receiveTrigger = "PickUp";

    public int Delivered { get; private set; }
    /// <summary>Raised with the new total whenever fruit is delivered.</summary>
    public event Action<int> DeliveredChanged;

    public void Receive(int amount)
    {
        if (amount <= 0) return;
        Delivered += amount;
        if (customerAnimator != null && !string.IsNullOrEmpty(receiveTrigger))
            customerAnimator.SetTrigger(receiveTrigger);
        DeliveredChanged?.Invoke(Delivered);
    }
}
