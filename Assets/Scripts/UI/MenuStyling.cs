using TMPro;
using UnityEngine;
using UnityEngine.UI;

public static class MenuStyling
{
    private static MenuTheme cachedTheme;
    private const string DefaultTitleFontPath = "Fonts/TT Ramillas Initials Trial Variable";
    private const string DefaultBodyFontPath = "Fonts/TT Ramillas Trial Regular";
    private static TMP_FontAsset cachedDefaultTitleFont;
    private static TMP_FontAsset cachedDefaultBodyFont;
    private static Texture2D cachedParchmentTexture;
    private static Sprite cachedParchmentSprite;
    private static Texture2D cachedButtonTexture;
    private static Sprite cachedButtonSprite;
    private static Texture2D cachedButtonSelectedTexture;
    private static Sprite cachedButtonSelectedSprite;
    private static Texture2D cachedRoundedButtonTexture;
    private static Sprite cachedRoundedButtonSprite;
    private static Texture2D cachedRoundedSelectedTexture;
    private static Sprite cachedRoundedSelectedSprite;
    private static Sprite cachedResourceButtonSprite;
    private static Sprite cachedResourceButtonSelectedSprite;

    public static MenuTheme Theme
    {
        get
        {
            if (cachedTheme == null)
            {
                cachedTheme = Resources.Load<MenuTheme>("MenuTheme");
            }
            return cachedTheme;
        }
    }

    public static (float panelWidth, float panelHeight, float buttonWidth, float buttonHeight, float spacing) GetResponsiveDimensions(Vector2 size)
    {
        var isLandscape = size.x > size.y;
        if (isLandscape)
        {
            var buttonWidth = Mathf.Min(280f, size.x * 0.3f);
            var buttonHeight = Mathf.Min(60f, size.y * 0.08f);
            return (
                panelWidth: size.x * 0.85f,
                panelHeight: size.y * 0.9f,
                buttonWidth: buttonWidth,
                buttonHeight: Mathf.Max(50f, buttonHeight),
                spacing: 15f
            );
        }

        var portraitButtonWidth = Mathf.Min(300f, size.x * 0.7f);
        var portraitButtonHeight = Mathf.Min(65f, size.y * 0.08f);
        return (
            panelWidth: size.x * 0.9f,
            panelHeight: size.y * 0.85f,
            buttonWidth: portraitButtonWidth,
            buttonHeight: Mathf.Max(55f, portraitButtonHeight),
            spacing: 20f
        );
    }

    public static Image CreateBookPage(Transform parent, Vector2 size, string name = "BookPage")
    {
        var panelObject = new GameObject(name);
        panelObject.transform.SetParent(parent, false);
        var rect = panelObject.AddComponent<RectTransform>();
        if (size == Vector2.zero)
        {
            rect.anchorMin = Vector2.zero;
            rect.anchorMax = Vector2.one;
            rect.offsetMin = Vector2.zero;
            rect.offsetMax = Vector2.zero;
        }
        else
        {
            rect.sizeDelta = size;
        }

        var image = panelObject.AddComponent<Image>();
        var backgroundSprite = Resources.Load<Sprite>("Main/book_page");
        image.sprite = backgroundSprite != null ? backgroundSprite : GetParchmentSprite();
        image.type = backgroundSprite != null ? Image.Type.Simple : Image.Type.Sliced;
        image.color = GetThemeColor(t => t.parchmentBg, new Color(0.95f, 0.91f, 0.82f, 1f));

        var outline = panelObject.AddComponent<Outline>();
        outline.effectColor = GetThemeColor(t => t.parchmentBorder, new Color(0.65f, 0.55f, 0.4f, 1f));
        outline.effectDistance = new Vector2(2f, -2f);

        var layout = panelObject.AddComponent<LayoutElement>();
        layout.ignoreLayout = true;

        return image;
    }

    public static Button CreateBookButton(Transform parent, string label, Vector2 size, string name = "BookButton")
    {
        var buttonObject = new GameObject(name);
        buttonObject.transform.SetParent(parent, false);
        var rect = buttonObject.AddComponent<RectTransform>();
        rect.sizeDelta = size;

        var image = buttonObject.AddComponent<Image>();
        var resourceSprite = GetResourceButtonSprite();
        image.sprite = resourceSprite != null ? resourceSprite : GetRoundedButtonSprite();
        image.type = resourceSprite != null ? Image.Type.Simple : Image.Type.Sliced;
        image.color = GetThemeColor(t => t.parchmentBg, new Color(0.95f, 0.91f, 0.82f, 1f));

        var button = buttonObject.AddComponent<Button>();

        var layout = buttonObject.AddComponent<LayoutElement>();
        layout.preferredWidth = size.x;
        layout.preferredHeight = size.y;

        var labelObject = new GameObject("Label");
        labelObject.transform.SetParent(buttonObject.transform, false);
        var labelRect = labelObject.AddComponent<RectTransform>();
        labelRect.anchorMin = Vector2.zero;
        labelRect.anchorMax = Vector2.one;
        labelRect.offsetMin = Vector2.zero;
        labelRect.offsetMax = Vector2.zero;

        var text = labelObject.AddComponent<TextMeshProUGUI>();
        text.text = label;
        text.fontSize = 26f;
        text.alignment = TextAlignmentOptions.Center;
        text.color = Color.white;
        text.fontStyle = FontStyles.Normal;
        ApplyFont(text, theme => theme.buttonFont, theme => theme.bodyFont, GetBodyFontAsset());

        return button;
    }

    public static Sprite GetResourceButtonSprite()
    {
        if (cachedResourceButtonSprite != null)
        {
            return cachedResourceButtonSprite;
        }

        cachedResourceButtonSprite = Resources.Load<Sprite>("Main/button1");
        return cachedResourceButtonSprite;
    }

    public static Sprite GetResourceButtonSelectedSprite()
    {
        if (cachedResourceButtonSelectedSprite != null)
        {
            return cachedResourceButtonSelectedSprite;
        }

        cachedResourceButtonSelectedSprite = Resources.Load<Sprite>("Main/button1_selected");
        return cachedResourceButtonSelectedSprite;
    }

    public static TMP_Text CreateBookTitle(Transform parent, string title, Vector2 size, string name = "BookTitle")
    {
        var titleObject = new GameObject(name);
        titleObject.transform.SetParent(parent, false);
        var rect = titleObject.AddComponent<RectTransform>();
        rect.sizeDelta = size;

        var text = titleObject.AddComponent<TextMeshProUGUI>();
        text.text = title;
        text.fontSize = 32f;
        text.alignment = TextAlignmentOptions.Center;
        text.color = Color.black;
        text.fontStyle = FontStyles.Normal;
        ApplyFont(text, theme => theme.titleFont, theme => theme.bodyFont, GetTitleFontAsset());

        var layout = titleObject.AddComponent<LayoutElement>();
        layout.preferredHeight = Mathf.Max(36f, size.y);

        return text;
    }

    public static string TruncateText(string text, TMP_FontAsset font, float fontSize, float maxWidth)
    {
        if (string.IsNullOrEmpty(text))
        {
            return text;
        }

        var generator = new TMP_TextInfo();
        var probe = new GameObject("TextProbe");
        var tmp = probe.AddComponent<TextMeshProUGUI>();
        tmp.font = font;
        tmp.fontSize = fontSize;
        tmp.text = text;
        tmp.ForceMeshUpdate();
        var width = tmp.preferredWidth;
        Object.Destroy(probe);

        if (width <= maxWidth)
        {
            return text;
        }

        var low = 0;
        var high = text.Length;
        var best = "";
        while (low <= high)
        {
            var mid = (low + high) / 2;
            var truncated = text.Substring(0, mid) + "...";
            tmp = new GameObject("TextProbe").AddComponent<TextMeshProUGUI>();
            tmp.font = font;
            tmp.fontSize = fontSize;
            tmp.text = truncated;
            tmp.ForceMeshUpdate();
            width = tmp.preferredWidth;
            Object.Destroy(tmp.gameObject);

            if (width <= maxWidth)
            {
                best = truncated;
                low = mid + 1;
            }
            else
            {
                high = mid - 1;
            }
        }

        return best;
    }

    private static void ApplyFont(TextMeshProUGUI text, System.Func<MenuTheme, TMP_FontAsset> primary, System.Func<MenuTheme, TMP_FontAsset> fallback, TMP_FontAsset runtimeFallback)
    {
        var theme = Theme;
        if (theme != null)
        {
            text.font = primary(theme) != null ? primary(theme) : fallback(theme);
            if (text.font == null)
            {
                text.font = runtimeFallback;
            }
            return;
        }
        text.font = runtimeFallback ?? TMP_Settings.defaultFontAsset;
    }

    public static TMP_FontAsset GetTitleFontAsset()
    {
        if (cachedDefaultTitleFont != null)
        {
            return cachedDefaultTitleFont;
        }

        cachedDefaultTitleFont = LoadRuntimeFont(DefaultTitleFontPath);
        return cachedDefaultTitleFont;
    }

    public static TMP_FontAsset GetBodyFontAsset()
    {
        if (cachedDefaultBodyFont != null)
        {
            return cachedDefaultBodyFont;
        }

        cachedDefaultBodyFont = LoadRuntimeFont(DefaultBodyFontPath);
        return cachedDefaultBodyFont;
    }

    private static TMP_FontAsset LoadRuntimeFont(string resourcePath)
    {
        var tmpFont = Resources.Load<TMP_FontAsset>(resourcePath);
        if (tmpFont != null)
        {
            tmpFont.atlasPopulationMode = AtlasPopulationMode.Dynamic;
            return tmpFont;
        }

        var font = Resources.Load<Font>(resourcePath);
        if (font == null)
        {
            return null;
        }

        tmpFont = TMP_FontAsset.CreateFontAsset(font);
        if (tmpFont != null)
        {
            tmpFont.atlasPopulationMode = AtlasPopulationMode.Dynamic;
        }
        return tmpFont;
    }

    private static Color GetThemeColor(System.Func<MenuTheme, Color> selector, Color fallback)
    {
        return Theme != null ? selector(Theme) : fallback;
    }

    private static Sprite GetParchmentSprite()
    {
        if (cachedParchmentSprite != null)
        {
            return cachedParchmentSprite;
        }

        cachedParchmentTexture = CreateGradientTexture(new Color(0.96f, 0.93f, 0.85f, 1f), new Color(0.9f, 0.85f, 0.75f, 1f));
        cachedParchmentSprite = Sprite.Create(cachedParchmentTexture, new Rect(0f, 0f, cachedParchmentTexture.width, cachedParchmentTexture.height), new Vector2(0.5f, 0.5f), 100f, 0, SpriteMeshType.FullRect);
        return cachedParchmentSprite;
    }

    private static Sprite GetButtonSprite()
    {
        if (cachedButtonSprite != null)
        {
            return cachedButtonSprite;
        }

        cachedButtonTexture = CreateGradientTexture(new Color(0.88f, 0.84f, 0.75f, 1f), new Color(0.8f, 0.75f, 0.65f, 1f));
        cachedButtonSprite = Sprite.Create(cachedButtonTexture, new Rect(0f, 0f, cachedButtonTexture.width, cachedButtonTexture.height), new Vector2(0.5f, 0.5f), 100f, 0, SpriteMeshType.FullRect);
        return cachedButtonSprite;
    }

    public static Sprite GetButtonSelectedSprite()
    {
        if (cachedButtonSelectedSprite != null)
        {
            return cachedButtonSelectedSprite;
        }

        cachedButtonSelectedTexture = CreateGradientTexture(new Color(0.78f, 0.86f, 0.72f, 1f), new Color(0.7f, 0.8f, 0.65f, 1f));
        cachedButtonSelectedSprite = Sprite.Create(cachedButtonSelectedTexture, new Rect(0f, 0f, cachedButtonSelectedTexture.width, cachedButtonSelectedTexture.height), new Vector2(0.5f, 0.5f), 100f, 0, SpriteMeshType.FullRect);
        return cachedButtonSelectedSprite;
    }

    public static Sprite GetRoundedButtonSprite()
    {
        if (cachedRoundedButtonSprite != null)
        {
            return cachedRoundedButtonSprite;
        }

        cachedRoundedButtonTexture = CreateRoundedGradientTexture(
            new Color(0.9f, 0.87f, 0.8f, 1f),
            new Color(0.82f, 0.78f, 0.7f, 1f),
            24f,
            GetThemeColor(t => t.parchmentBorder, new Color(0.65f, 0.55f, 0.4f, 1f)),
            2f,
            new Vector2Int(256, 96));
        cachedRoundedButtonSprite = Sprite.Create(
            cachedRoundedButtonTexture,
            new Rect(0f, 0f, cachedRoundedButtonTexture.width, cachedRoundedButtonTexture.height),
            new Vector2(0.5f, 0.5f),
            100f,
            0,
            SpriteMeshType.FullRect,
            new Vector4(24f, 24f, 24f, 24f));
        return cachedRoundedButtonSprite;
    }

    public static Sprite GetRoundedSelectedSprite()
    {
        if (cachedRoundedSelectedSprite != null)
        {
            return cachedRoundedSelectedSprite;
        }

        cachedRoundedSelectedTexture = CreateRoundedGradientTexture(
            new Color(0.82f, 0.9f, 0.78f, 1f),
            new Color(0.72f, 0.82f, 0.68f, 1f),
            24f,
            GetThemeColor(t => t.parchmentBorder, new Color(0.65f, 0.55f, 0.4f, 1f)),
            2f,
            new Vector2Int(256, 96));
        cachedRoundedSelectedSprite = Sprite.Create(
            cachedRoundedSelectedTexture,
            new Rect(0f, 0f, cachedRoundedSelectedTexture.width, cachedRoundedSelectedTexture.height),
            new Vector2(0.5f, 0.5f),
            100f,
            0,
            SpriteMeshType.FullRect,
            new Vector4(24f, 24f, 24f, 24f));
        return cachedRoundedSelectedSprite;
    }

    private static Texture2D CreateGradientTexture(Color top, Color bottom)
    {
        const int size = 64;
        var texture = new Texture2D(size, size, TextureFormat.RGBA32, false)
        {
            wrapMode = TextureWrapMode.Clamp,
            filterMode = FilterMode.Bilinear
        };

        for (var y = 0; y < size; y++)
        {
            var t = (float)y / (size - 1);
            var color = Color.Lerp(bottom, top, t);
            for (var x = 0; x < size; x++)
            {
                texture.SetPixel(x, y, color);
            }
        }

        texture.Apply();
        return texture;
    }

    private static Texture2D CreateRoundedGradientTexture(Color top, Color bottom, float radius, Color borderColor, float borderThickness, Vector2Int size)
    {
        var texture = new Texture2D(size.x, size.y, TextureFormat.RGBA32, false)
        {
            wrapMode = TextureWrapMode.Clamp,
            filterMode = FilterMode.Bilinear
        };

        var width = size.x;
        var height = size.y;
        var radiusSquared = radius * radius;
        var innerRadius = Mathf.Max(0f, radius - borderThickness);
        var innerRadiusSquared = innerRadius * innerRadius;
        var left = radius;
        var right = width - radius - 1f;
        var bottomY = radius;
        var topY = height - radius - 1f;

        for (var y = 0; y < height; y++)
        {
            var t = (float)y / (height - 1);
            var baseColor = Color.Lerp(bottom, top, t);
            for (var x = 0; x < width; x++)
            {
                var alpha = 1f;
                if (x < left && y < bottomY)
                {
                    alpha = DistanceAlpha(x, y, left, bottomY, radiusSquared);
                }
                else if (x > right && y < bottomY)
                {
                    alpha = DistanceAlpha(x, y, right, bottomY, radiusSquared);
                }
                else if (x < left && y > topY)
                {
                    alpha = DistanceAlpha(x, y, left, topY, radiusSquared);
                }
                else if (x > right && y > topY)
                {
                    alpha = DistanceAlpha(x, y, right, topY, radiusSquared);
                }

                var color = baseColor;
                if (alpha > 0f)
                {
                    var isBorder = false;
                    if (borderThickness > 0f)
                    {
                        if (x < left && y < bottomY)
                        {
                            isBorder = DistanceAlpha(x, y, left, bottomY, innerRadiusSquared) == 0f;
                        }
                        else if (x > right && y < bottomY)
                        {
                            isBorder = DistanceAlpha(x, y, right, bottomY, innerRadiusSquared) == 0f;
                        }
                        else if (x < left && y > topY)
                        {
                            isBorder = DistanceAlpha(x, y, left, topY, innerRadiusSquared) == 0f;
                        }
                        else if (x > right && y > topY)
                        {
                            isBorder = DistanceAlpha(x, y, right, topY, innerRadiusSquared) == 0f;
                        }
                        else if (x < borderThickness || x > width - borderThickness - 1 || y < borderThickness || y > height - borderThickness - 1)
                        {
                            isBorder = true;
                        }
                    }

                    color = isBorder ? borderColor : baseColor;
                    color.a = 1f;
                    texture.SetPixel(x, y, color);
                }
                else
                {
                    color.a = 0f;
                    texture.SetPixel(x, y, color);
                }
            }
        }

        texture.Apply();
        return texture;
    }

    private static float DistanceAlpha(float x, float y, float cx, float cy, float radiusSquared)
    {
        var dx = x - cx;
        var dy = y - cy;
        var distSquared = dx * dx + dy * dy;
        return distSquared <= radiusSquared ? 1f : 0f;
    }
}
