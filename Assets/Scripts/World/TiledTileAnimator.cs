using System.Collections.Generic;
using UnityEngine;

public class TiledTileAnimator : MonoBehaviour
{
    public readonly struct FrameData
    {
        public readonly Sprite sprite;
        public readonly float duration;

        public FrameData(Sprite sprite, float duration)
        {
            this.sprite = sprite;
            this.duration = duration;
        }
    }

    private readonly List<FrameData> frames = new List<FrameData>();
    private SpriteRenderer spriteRenderer;
    private int currentIndex;
    private float timer;

    public void SetFrames(List<FrameData> newFrames)
    {
        frames.Clear();
        if (newFrames != null)
        {
            frames.AddRange(newFrames);
        }

        currentIndex = 0;
        timer = 0f;
        EnsureRenderer();
        ApplyFrame();
    }

    private void Awake()
    {
        EnsureRenderer();
    }

    private void Update()
    {
        if (frames.Count == 0)
        {
            return;
        }

        timer += Time.deltaTime;
        if (timer < frames[currentIndex].duration)
        {
            return;
        }

        timer = 0f;
        currentIndex = (currentIndex + 1) % frames.Count;
        ApplyFrame();
    }

    private void EnsureRenderer()
    {
        if (spriteRenderer == null)
        {
            spriteRenderer = GetComponent<SpriteRenderer>();
        }
    }

    private void ApplyFrame()
    {
        if (spriteRenderer == null || frames.Count == 0)
        {
            return;
        }

        spriteRenderer.sprite = frames[currentIndex].sprite;
    }
}
