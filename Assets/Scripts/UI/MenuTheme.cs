using UnityEngine;
using TMPro;

[CreateAssetMenu(menuName = "FableForge/Menu Theme", fileName = "MenuTheme")]
public class MenuTheme : ScriptableObject
{
    [Header("Book Palette")]
    public Color parchmentBg = new Color(0.95f, 0.91f, 0.82f, 1f);
    public Color parchmentDark = new Color(0.85f, 0.80f, 0.70f, 1f);
    public Color parchmentBorder = new Color(0.65f, 0.55f, 0.40f, 1f);
    public Color inkColor = new Color(0.15f, 0.10f, 0.05f, 1f);
    public Color inkMuted = new Color(0.35f, 0.28f, 0.22f, 1f);
    public Color bookAccent = new Color(0.6f, 0.4f, 0.2f, 1f);
    public Color bookDanger = new Color(0.7f, 0.2f, 0.1f, 1f);
    public Color bookSecondary = new Color(0.3f, 0.5f, 0.3f, 1f);

    [Header("Modern Palette")]
    public Color primaryColor = new Color(0.15f, 0.25f, 0.35f, 1f);
    public Color secondaryColor = new Color(0.2f, 0.6f, 0.4f, 1f);
    public Color accentColor = new Color(0.3f, 0.5f, 0.8f, 1f);
    public Color dangerColor = new Color(0.8f, 0.2f, 0.2f, 1f);
    public Color darkBg = new Color(0.08f, 0.1f, 0.12f, 0.98f);
    public Color panelBg = new Color(0.12f, 0.15f, 0.18f, 0.98f);
    public Color lightText = new Color(0.95f, 0.95f, 0.95f, 1f);
    public Color mutedText = new Color(0.7f, 0.7f, 0.7f, 1f);

    [Header("Typography")]
    public TMP_FontAsset titleFont;
    public TMP_FontAsset bodyFont;
    public TMP_FontAsset buttonFont;
}
