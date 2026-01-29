using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

public static class PartsManifestBuilder
{
    private const string PartsRootRelative = "Assets/Characters/Parts";
    private const string ManifestRelativePath = "Assets/Data/CharacterParts/parts_manifest.json";
    private const string DefaultRigId = "humanoid_v1";

    [MenuItem("Tools/Character/Build Parts Manifest")]
    public static void BuildManifestMenu()
    {
        var manifest = BuildManifest();
        if (manifest == null)
        {
            return;
        }

        WriteManifest(manifest);
        AssetDatabase.Refresh();
    }

    public static PartsManifest BuildManifest()
    {
        var partsRoot = Path.Combine(Application.dataPath, "Characters/Parts");
        if (!Directory.Exists(partsRoot))
        {
            Debug.LogWarning($"Parts folder not found at {partsRoot}");
            return null;
        }

        var manifest = new PartsManifest
        {
            rig = DefaultRigId,
            categories = new Dictionary<string, List<PartsManifestEntry>>()
        };

        var categoryDirs = Directory.GetDirectories(partsRoot);
        foreach (var dir in categoryDirs)
        {
            var categoryName = Path.GetFileName(dir);
            var entries = new List<PartsManifestEntry>();

            var files = Directory.GetFiles(dir, "*.png", SearchOption.AllDirectories);
            foreach (var file in files)
            {
                var label = Path.GetFileNameWithoutExtension(file);
                var normalized = file.Replace("\\", "/");
                var assetPath = normalized.StartsWith(Application.dataPath)
                    ? $"Assets{normalized.Substring(Application.dataPath.Length)}"
                    : $"Assets/Characters/Parts/{categoryName}/{Path.GetFileName(file)}";
                entries.Add(new PartsManifestEntry { label = label, path = assetPath });
            }

            manifest.categories[categoryName] = entries;
        }

        return manifest;
    }

    public static void WriteManifest(PartsManifest manifest)
    {
        var outputPath = Path.Combine(Application.dataPath, "Data/CharacterParts");
        Directory.CreateDirectory(outputPath);

        var json = SerializeManifest(manifest);
        File.WriteAllText(Path.Combine(outputPath, "parts_manifest.json"), json);
    }

    public static PartsManifest LoadManifest()
    {
        var manifestPath = Path.Combine(Application.dataPath, "Data/CharacterParts/parts_manifest.json");
        if (!File.Exists(manifestPath))
        {
            return null;
        }

        var json = File.ReadAllText(manifestPath);
        return DeserializeManifest(json);
    }

    private static string SerializeManifest(PartsManifest manifest)
    {
        var categories = new Dictionary<string, object>();
        foreach (var kvp in manifest.categories)
        {
            var list = new List<object>();
            foreach (var entry in kvp.Value)
            {
                list.Add(new Dictionary<string, object>
                {
                    { "label", entry.label },
                    { "path", entry.path }
                });
            }

            categories[kvp.Key] = list;
        }

        var payload = new Dictionary<string, object>
        {
            { "rig", manifest.rig },
            { "categories", categories }
        };

        return MiniJson.Serialize(payload);
    }

    private static PartsManifest DeserializeManifest(string json)
    {
        var parsed = MiniJson.Deserialize(json) as Dictionary<string, object>;
        if (parsed == null)
        {
            return null;
        }

        var manifest = new PartsManifest();
        if (parsed.TryGetValue("rig", out var rigValue))
        {
            manifest.rig = rigValue as string;
        }

        if (parsed.TryGetValue("categories", out var categoriesObj) && categoriesObj is Dictionary<string, object> categoriesDict)
        {
            foreach (var category in categoriesDict)
            {
                var entries = new List<PartsManifestEntry>();
                if (category.Value is List<object> list)
                {
                    foreach (var item in list)
                    {
                        if (item is Dictionary<string, object> entryDict)
                        {
                            entries.Add(new PartsManifestEntry
                            {
                                label = entryDict.TryGetValue("label", out var labelObj) ? labelObj as string : null,
                                path = entryDict.TryGetValue("path", out var pathObj) ? pathObj as string : null
                            });
                        }
                    }
                }

                manifest.categories[category.Key] = entries;
            }
        }

        return manifest;
    }
}
