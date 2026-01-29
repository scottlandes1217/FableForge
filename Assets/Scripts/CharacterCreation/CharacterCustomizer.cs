using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using UnityEngine.U2D.Animation;
#if UNITY_EDITOR
using UnityEditor;
#endif

public class CharacterCustomizer : MonoBehaviour
{
    [Header("Preset Sources")]
    [SerializeField] private string presetResourcePath = "CharacterPresets/preset_default";
    [SerializeField] private string presetStreamingFile = "CharacterPresets/preset_default.json";

    [Header("Tint Groups")]
    [SerializeField] private List<SpriteTintGroup> tintGroups = new List<SpriteTintGroup>();

    [Header("Facing")]
    [SerializeField] private FacingDirection defaultFacing = FacingDirection.Front;
    [SerializeField] private FacingDirectionResolver facingResolver;

    private CharacterPreset activePreset;
    private SpriteLibrary spriteLibrary;
    private static Dictionary<string, string> manifestSpriteLookup;
    private static bool manifestLoaded;

    private void Start()
    {
        if (activePreset == null)
        {
            LoadAndApplyPreset();
        }
    }

    public void ApplyPreset(CharacterPreset preset)
    {
        if (preset == null)
        {
            return;
        }

        activePreset = preset;
        ApplySlots(preset.slots);
        ApplyFacing(preset.slots);
        ApplyTints(preset.tints);
    }

    public void LoadAndApplyPreset()
    {
        var preset = LoadPreset();
        if (preset == null)
        {
            Debug.LogWarning("CharacterCustomizer: No preset found.");
            return;
        }

        ApplyPreset(preset);
    }

    private CharacterPreset LoadPreset()
    {
        if (!string.IsNullOrWhiteSpace(presetResourcePath))
        {
            var textAsset = Resources.Load<TextAsset>(presetResourcePath);
            if (textAsset != null)
            {
                return CharacterPreset.FromJson(textAsset.text);
            }
        }

        if (!string.IsNullOrWhiteSpace(presetStreamingFile))
        {
            var path = Path.Combine(Application.streamingAssetsPath, presetStreamingFile);
            if (File.Exists(path))
            {
                var json = File.ReadAllText(path);
                return CharacterPreset.FromJson(json);
            }
        }

        return null;
    }

    private void ApplySlots(Dictionary<string, string> slots)
    {
        if (slots == null || slots.Count == 0)
        {
            return;
        }

        if (spriteLibrary == null)
        {
            spriteLibrary = GetComponentInParent<SpriteLibrary>();
        }

        var hasLibrary = HasSpriteLibraryEntries(spriteLibrary);
        var resolvers = GetComponentsInChildren<SpriteResolver>(true);
        foreach (var resolver in resolvers)
        {
            if (resolver == null)
            {
                continue;
            }

            var category = resolver.GetCategory();
            if (string.IsNullOrWhiteSpace(category))
            {
                category = resolver.gameObject.name;
                if (!string.IsNullOrWhiteSpace(category) && hasLibrary)
                {
                    resolver.SetCategoryAndLabel(category, "placeholder");
                }
            }

            if (!slots.TryGetValue(category, out var label) || string.IsNullOrWhiteSpace(label))
            {
                continue;
            }

            if (hasLibrary)
            {
                resolver.SetCategoryAndLabel(category, label);
                continue;
            }

            var manifestSprite = TryLoadSpriteFromManifest(category, label);
            if (manifestSprite != null)
            {
                var renderer = resolver.GetComponent<SpriteRenderer>();
                if (renderer != null)
                {
                    resolver.enabled = false;
                    renderer.sprite = manifestSprite;
                    renderer.enabled = true;
                }
            }
        }
    }

    private void ApplyTints(Dictionary<string, string> tints)
    {
        if (tints == null || tints.Count == 0)
        {
            return;
        }

        foreach (var group in tintGroups)
        {
            if (group == null || string.IsNullOrWhiteSpace(group.tintKey))
            {
                continue;
            }

            if (tints.TryGetValue(group.tintKey, out var hex) && TryParseHexColor(hex, out var color))
            {
                group.ApplyColor(color);
            }
        }
    }

    private void ApplyFacing(Dictionary<string, string> slots)
    {
        if (slots == null || slots.Count == 0)
        {
            return;
        }

        if (facingResolver == null)
        {
            facingResolver = GetComponent<FacingDirectionResolver>();
        }

        if (facingResolver == null)
        {
            facingResolver = gameObject.AddComponent<FacingDirectionResolver>();
        }

        if (!HasSpriteLibraryEntries(spriteLibrary))
        {
            return;
        }

        facingResolver.SetFacing(defaultFacing, slots);
    }

    private bool HasSpriteLibraryEntries(SpriteLibrary library)
    {
        if (library == null || library.spriteLibraryAsset == null)
        {
            return false;
        }

        try
        {
            foreach (var _ in library.spriteLibraryAsset.GetCategoryNames())
            {
                return true;
            }
        }
        catch (Exception)
        {
            return false;
        }

        return false;
    }

    private Sprite TryLoadSpriteFromManifest(string category, string label)
    {
        if (string.IsNullOrWhiteSpace(category) || string.IsNullOrWhiteSpace(label))
        {
            return null;
        }

        EnsureManifestLookup();
        if (manifestSpriteLookup == null)
        {
            return null;
        }

        var lookupKey = $"{category}|{label}";
        if (!manifestSpriteLookup.TryGetValue(lookupKey, out var assetPath))
        {
            return null;
        }

        return LoadSpriteAtPath(assetPath);
    }

    private void EnsureManifestLookup()
    {
        if (manifestLoaded)
        {
            return;
        }

        manifestLoaded = true;
        manifestSpriteLookup = new Dictionary<string, string>();

        var manifestPath = Path.Combine(Application.dataPath, "Data/CharacterParts/parts_manifest.json");
        string json = null;
        if (File.Exists(manifestPath))
        {
            json = File.ReadAllText(manifestPath);
        }
        else
        {
            var textAsset = Resources.Load<TextAsset>("Data/CharacterParts/parts_manifest");
            if (textAsset != null)
            {
                json = textAsset.text;
            }
        }

        if (string.IsNullOrWhiteSpace(json))
        {
            return;
        }

        var parsed = MiniJson.Deserialize(json) as Dictionary<string, object>;
        if (parsed == null || !parsed.TryGetValue("categories", out var categoriesObj) || categoriesObj is not Dictionary<string, object> categoriesDict)
        {
            return;
        }

        foreach (var categoryEntry in categoriesDict)
        {
            if (categoryEntry.Value is not List<object> list)
            {
                continue;
            }

            foreach (var item in list)
            {
                if (item is not Dictionary<string, object> entryDict)
                {
                    continue;
                }

                var entryLabel = entryDict.TryGetValue("label", out var labelObj) ? labelObj as string : null;
                var entryPath = entryDict.TryGetValue("path", out var pathObj) ? pathObj as string : null;
                if (string.IsNullOrWhiteSpace(entryLabel) || string.IsNullOrWhiteSpace(entryPath))
                {
                    continue;
                }

                var key = $"{categoryEntry.Key}|{entryLabel}";
                manifestSpriteLookup[key] = entryPath;
            }
        }
    }

    private Sprite LoadSpriteAtPath(string assetPath)
    {
        if (string.IsNullOrWhiteSpace(assetPath))
        {
            return null;
        }

#if UNITY_EDITOR
        var assetSprite = AssetDatabase.LoadAssetAtPath<Sprite>(assetPath);
        if (assetSprite != null)
        {
            return assetSprite;
        }
#endif

        if (assetPath.Contains("/Resources/", StringComparison.OrdinalIgnoreCase))
        {
            var resourcesIndex = assetPath.IndexOf("/Resources/", StringComparison.OrdinalIgnoreCase);
            var resourcesPath = assetPath.Substring(resourcesIndex + "/Resources/".Length);
            resourcesPath = Path.ChangeExtension(resourcesPath, null);
            var resourceSprite = Resources.Load<Sprite>(resourcesPath);
            if (resourceSprite != null)
            {
                return resourceSprite;
            }
        }

        if (assetPath.StartsWith("Assets/", StringComparison.OrdinalIgnoreCase))
        {
            var relative = assetPath.Substring("Assets/".Length);
            var fullPath = Path.Combine(Application.dataPath, relative);
            if (File.Exists(fullPath))
            {
                var bytes = File.ReadAllBytes(fullPath);
                var texture = new Texture2D(2, 2, TextureFormat.RGBA32, false);
                if (texture.LoadImage(bytes))
                {
                    return Sprite.Create(texture, new Rect(0f, 0f, texture.width, texture.height), new Vector2(0.5f, 0.5f), 100f);
                }
            }
        }

        return null;
    }

    private bool TryParseHexColor(string hex, out Color color)
    {
        color = Color.white;
        if (string.IsNullOrWhiteSpace(hex))
        {
            return false;
        }

        if (!hex.StartsWith("#"))
        {
            hex = $"#{hex}";
        }

        return ColorUtility.TryParseHtmlString(hex, out color);
    }
}
