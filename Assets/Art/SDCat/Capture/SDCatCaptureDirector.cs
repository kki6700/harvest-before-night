using UnityEngine;

// Drives the SD cat during a capture: plays one Animator state and spins the cat like a turntable.
// Started and stopped by Editor/SDCatCapture.cs; harmless in normal play.
public class SDCatCaptureDirector : MonoBehaviour
{
    public string animatorState = "SDCat_Idle";
    public float degreesPerSecond;

    void Start()
    {
        var animator = GetComponent<Animator>();
        if (animator != null && !string.IsNullOrEmpty(animatorState)) animator.Play(animatorState, 0, 0f);
    }

    void Update()
    {
        if (degreesPerSecond != 0f) transform.Rotate(0f, degreesPerSecond * Time.deltaTime, 0f, Space.World);
    }
}
