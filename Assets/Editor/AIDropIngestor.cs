using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

public static class AIDropIngestor
{
    private const string DropFolder = "Assets/AI_Drops";
    private const string PartsRoot = "Assets/Characters/Parts";

    [MenuItem("Tools/Character/Ingest AI Drops")]
    public static void Ingest()
    {
        if (!AssetDatabase.IsValidFolder(DropFolder))
        {
            Debug.LogWarning($"AI drop folder not found at {DropFolder}");
            return;
        }

        var mapping = BuildPrefixMap();
        var files = Directory.GetFiles(DropFolder, "*.png", SearchOption.TopDirectoryOnly);
        foreach (var file in files)
        {
            var fileName = Path.GetFileName(file);
            var targetCategory = ResolveCategory(fileName, mapping);
            if (string.IsNullOrWhiteSpace(targetCategory))
            {
                Debug.LogWarning($"Could not map {fileName} to a category.");
                continue;
            }

            var destinationFolder = $"{PartsRoot}/{targetCategory}";
            if (!AssetDatabase.IsValidFolder(destinationFolder))
            {
                Directory.CreateDirectory(destinationFolder);
                AssetDatabase.Refresh();
            }

            var destinationPath = $"{destinationFolder}/{fileName}";
            var result = AssetDatabase.MoveAsset(file, destinationPath);
            if (!string.IsNullOrWhiteSpace(result))
            {
                Debug.LogWarning($"Failed to move {fileName}: {result}");
            }
        }

        PartsManifestBuilder.BuildManifestMenu();
        SpriteLibraryAutoPopulator.Populate();
    }

    private static Dictionary<string, string> BuildPrefixMap()
    {
        return new Dictionary<string, string>
        {
            { "body_", "Body" },
            { "head_", "Head" },
            { "eyes_", "Eyes" },
            { "mouth_", "Mouth" },
            { "nose_", "Nose" },
            { "hair_front_", "HairFront" },
            { "hair_back_", "HairBack" },
            { "top_", "Top" },
            { "bottom_", "Bottom" },
            { "shoes_", "Shoes" },
            { "gloves_", "Gloves" },
            { "armor_", "Armor" },
            { "weapon_", "Weapon" },
            { "shield_", "Shield" },
            { "accessory_", "Accessory" }
        };
    }

    private static string ResolveCategory(string fileName, Dictionary<string, string> mapping)
    {
        var lower = fileName.ToLowerInvariant();
        foreach (var entry in mapping)
        {
            if (lower.StartsWith(entry.Key))
            {
                return entry.Value;
            }
        }

        return null;
    }
}
