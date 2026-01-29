using System.IO;
using UnityEditor;
using UnityEngine;
using UnityEngine.U2D.Animation;

public static class SpriteLibraryAutoPopulator
{
    private const string DefaultLibraryPath = "Assets/Characters/RigHumanoidV1/SpriteLibrary/rig_humanoid_v1.spriteLibrary";

    [MenuItem("Tools/Character/Populate Sprite Library")]
    public static void Populate()
    {
        var manifest = PartsManifestBuilder.LoadManifest();
        if (manifest == null)
        {
            Debug.LogWarning("Parts manifest not found. Run Build Parts Manifest first.");
            return;
        }

        var spriteLibrary = LoadOrCreateLibrary(DefaultLibraryPath, recreate: true);
        if (spriteLibrary == null)
        {
            return;
        }

        foreach (var category in manifest.categories)
        {
            foreach (var entry in category.Value)
            {
                if (string.IsNullOrWhiteSpace(entry.path))
                {
                    continue;
                }

                var sprite = AssetDatabase.LoadAssetAtPath<Sprite>(entry.path);
                if (sprite == null)
                {
                    var importer = AssetImporter.GetAtPath(entry.path) as TextureImporter;
                    if (importer != null)
                    {
                        importer.textureType = TextureImporterType.Sprite;
                        importer.spritePixelsPerUnit = 100f;
                        importer.mipmapEnabled = false;
                        importer.alphaIsTransparency = true;
                        importer.SaveAndReimport();
                        sprite = AssetDatabase.LoadAssetAtPath<Sprite>(entry.path);
                    }

                    if (sprite == null)
                    {
                        Debug.LogWarning($"Sprite not found at {entry.path}");
                        continue;
                    }
                }

                spriteLibrary.AddCategoryLabel(sprite, category.Key, entry.label);
            }
        }

        EditorUtility.SetDirty(spriteLibrary);
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();
    }

    private static SpriteLibraryAsset LoadOrCreateLibrary(string assetPath, bool recreate)
    {
        if (recreate)
        {
            if (AssetDatabase.LoadAssetAtPath<SpriteLibraryAsset>(assetPath) != null)
            {
                AssetDatabase.DeleteAsset(assetPath);
            }
        }

        var directory = Path.GetDirectoryName(assetPath);
        if (!string.IsNullOrWhiteSpace(directory) && !Directory.Exists(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var spriteLibrary = AssetDatabase.LoadAssetAtPath<SpriteLibraryAsset>(assetPath);
        if (spriteLibrary != null)
        {
            return spriteLibrary;
        }

        return CreateSpriteLibraryAsset(assetPath);
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
}
