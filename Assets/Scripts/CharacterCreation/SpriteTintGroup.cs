using System.Collections.Generic;
using UnityEngine;

public class SpriteTintGroup : MonoBehaviour
{
    public string tintKey;
    public List<SpriteRenderer> renderers = new List<SpriteRenderer>();

    public void ApplyColor(Color color)
    {
        foreach (var renderer in renderers)
        {
            if (renderer != null)
            {
                renderer.color = color;
            }
        }
    }
}
