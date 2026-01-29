using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;
using UnityEngine.U2D.Animation;

public static class DefaultRigSetup
{
    private const string RigRoot = "Assets/Characters/RigHumanoidV1";
    private const string LibraryPath = "Assets/Characters/RigHumanoidV1/SpriteLibrary/rig_humanoid_v1.spriteLibrary";
    private const string PrefabPath = "Assets/Resources/CharacterRigs/DefaultPreviewRig.prefab";
    private const string PlaceholderPath = "Assets/Characters/RigHumanoidV1/SpriteLibrary/placeholder.png";

    private static readonly (string name, int order)[] Slots =
    {
        ("Body", 0),
        ("Bottom", 5),
        ("Top", 6),
        ("Armor", 7),
        ("Head", 10),
        ("Eyes", 12),
        ("Mouth", 13),
        ("Nose", 14),
        ("HairBack", 8),
        ("HairFront", 15),
        ("Gloves", 9),
        ("Shoes", 4),
        ("Weapon", 20),
        ("Shield", 19),
        ("Accessory", 16)
    };

    [InitializeOnLoadMethod]
    private static void EnsureDefaultRigAssets()
    {
        EditorApplication.delayCall += EnsureAssets;
    }

    [MenuItem("Tools/Character/Create Default Rig Prefab")]
    private static void EnsureAssets()
    {
        if (EditorApplication.isPlayingOrWillChangePlaymode)
        {
            return;
        }

        EnsureFolders();
        var placeholderSprite = EnsurePlaceholderSprite();
        var library = EnsureSpriteLibrary(placeholderSprite);
        EnsurePrefab(library, placeholderSprite);
    }

    private static void EnsureFolders()
    {
        CreateFolder("Assets/Characters");
        CreateFolder("Assets/Characters/RigHumanoidV1");
        CreateFolder("Assets/Characters/RigHumanoidV1/Prefabs");
        CreateFolder("Assets/Characters/RigHumanoidV1/Rigs");
        CreateFolder("Assets/Characters/RigHumanoidV1/SpriteLibrary");
        CreateFolder("Assets/Characters/RigHumanoidV1/Slots");
        CreateFolder("Assets/Resources");
        CreateFolder("Assets/Resources/CharacterRigs");
    }

    private static Sprite EnsurePlaceholderSprite()
    {
        var texture = new Texture2D(8, 8, TextureFormat.RGBA32, false);
        var color = new Color(0.85f, 0.82f, 0.75f, 1f);
        var pixels = new Color[64];
        for (var i = 0; i < pixels.Length; i++)
        {
            pixels[i] = color;
        }
        texture.SetPixels(pixels);
        texture.Apply();

        var png = texture.EncodeToPNG();
        File.WriteAllBytes(PlaceholderPath, png);
        AssetDatabase.ImportAsset(PlaceholderPath, ImportAssetOptions.ForceSynchronousImport);

        var sprite = AssetDatabase.LoadAssetAtPath<Sprite>(PlaceholderPath);
        if (sprite == null)
        {
            var importer = AssetImporter.GetAtPath(PlaceholderPath) as TextureImporter;
            if (importer != null)
            {
                importer.textureType = TextureImporterType.Sprite;
                importer.spritePixelsPerUnit = 100f;
                importer.SaveAndReimport();
                sprite = AssetDatabase.LoadAssetAtPath<Sprite>(PlaceholderPath);
            }
        }

        return sprite;
    }

    private static SpriteLibraryAsset EnsureSpriteLibrary(Sprite placeholderSprite)
    {
        var library = AssetDatabase.LoadAssetAtPath<SpriteLibraryAsset>(LibraryPath);
        if (library == null)
        {
            library = CreateSpriteLibraryAsset(LibraryPath);
            if (library == null)
            {
                Debug.LogWarning($"Failed to create SpriteLibraryAsset at {LibraryPath}");
                return null;
            }
        }

        if (placeholderSprite != null)
        {
            var existingCategories = new HashSet<string>(library.GetCategoryNames());
            foreach (var slot in Slots)
            {
                if (!existingCategories.Contains(slot.name))
                {
                    library.AddCategoryLabel(placeholderSprite, slot.name, "placeholder");
                }
            }
        }

        EditorUtility.SetDirty(library);
        AssetDatabase.SaveAssets();
        return library;
    }

    private static SpriteLibraryAsset CreateSpriteLibraryAsset(string assetPath)
    {
        var tempPath = Path.ChangeExtension(assetPath, "asset");
        if (AssetDatabase.LoadAssetAtPath<SpriteLibraryAsset>(tempPath) != null)
        {
            AssetDatabase.DeleteAsset(tempPath);
        }

        var tempAsset = ScriptableObject.CreateInstance<SpriteLibraryAsset>();
        AssetDatabase.CreateAsset(tempAsset, tempPath);
        AssetDatabase.SaveAssets();

        if (!string.Equals(tempPath, assetPath))
        {
            if (AssetDatabase.LoadAssetAtPath<SpriteLibraryAsset>(assetPath) != null)
            {
                AssetDatabase.DeleteAsset(assetPath);
            }
            AssetDatabase.MoveAsset(tempPath, assetPath);
            AssetDatabase.ImportAsset(assetPath, ImportAssetOptions.ForceSynchronousImport);
        }

        return AssetDatabase.LoadAssetAtPath<SpriteLibraryAsset>(assetPath);
    }

    private static void EnsurePrefab(SpriteLibraryAsset library, Sprite placeholderSprite)
    {
        var prefab = AssetDatabase.LoadAssetAtPath<GameObject>(PrefabPath);
        if (prefab != null)
        {
            return;
        }

        var root = new GameObject("DefaultPreviewRig");
        var libraryComponent = root.AddComponent<SpriteLibrary>();
        libraryComponent.spriteLibraryAsset = library;

        var customizer = root.AddComponent<CharacterCustomizer>();

        var slotsRoot = new GameObject("Slots");
        slotsRoot.transform.SetParent(root.transform, false);

        var hairRenderers = new List<SpriteRenderer>();
        var skinRenderers = new List<SpriteRenderer>();
        var eyeRenderers = new List<SpriteRenderer>();

        foreach (var slot in Slots)
        {
            var slotObject = new GameObject(slot.name);
            slotObject.transform.SetParent(slotsRoot.transform, false);

            var renderer = slotObject.AddComponent<SpriteRenderer>();
            renderer.sortingOrder = slot.order;
            if (placeholderSprite != null)
            {
                renderer.sprite = placeholderSprite;
            }

            var resolver = slotObject.AddComponent<SpriteResolver>();
            resolver.SetCategoryAndLabel(slot.name, "placeholder");

            if (slot.name == "Body" || slot.name == "Head")
            {
                skinRenderers.Add(renderer);
            }
            else if (slot.name == "HairFront" || slot.name == "HairBack")
            {
                hairRenderers.Add(renderer);
            }
            else if (slot.name == "Eyes")
            {
                eyeRenderers.Add(renderer);
            }
        }

        var skinGroup = root.AddComponent<SpriteTintGroup>();
        skinGroup.tintKey = "Skin";
        skinGroup.renderers = skinRenderers;

        var hairGroup = root.AddComponent<SpriteTintGroup>();
        hairGroup.tintKey = "Hair";
        hairGroup.renderers = hairRenderers;

        var eyesGroup = root.AddComponent<SpriteTintGroup>();
        eyesGroup.tintKey = "Eyes";
        eyesGroup.renderers = eyeRenderers;

        PrefabUtility.SaveAsPrefabAsset(root, PrefabPath);
        Object.DestroyImmediate(root);
        AssetDatabase.Refresh();
    }

    private static void CreateFolder(string path)
    {
        if (!AssetDatabase.IsValidFolder(path))
        {
            Directory.CreateDirectory(path);
            AssetDatabase.Refresh();
        }
    }
}
