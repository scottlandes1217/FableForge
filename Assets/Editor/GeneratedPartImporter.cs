using System.IO;
using UnityEditor;
using UnityEngine;

public static class GeneratedPartImporter
{
    private const string LastGeneratedFileName = "last_generated.txt";

    [MenuItem("Tools/Character/Import Last Generated")]
    public static void ImportLastGenerated()
    {
        var lastPathFile = Path.Combine(Application.persistentDataPath, "GeneratedParts", LastGeneratedFileName);
        if (!File.Exists(lastPathFile))
        {
            Debug.LogWarning($"No last generated path file found at {lastPathFile}");
            return;
        }

        var sourcePath = File.ReadAllText(lastPathFile).Trim();
        if (string.IsNullOrWhiteSpace(sourcePath) || !File.Exists(sourcePath))
        {
            Debug.LogWarning("Last generated file path is missing or invalid.");
            return;
        }

        var category = new DirectoryInfo(Path.GetDirectoryName(sourcePath) ?? string.Empty).Name;
        if (string.IsNullOrWhiteSpace(category))
        {
            Debug.LogWarning("Unable to resolve category from generated path.");
            return;
        }

        var destinationFolder = $"Assets/Characters/Parts/{category}";
        if (!AssetDatabase.IsValidFolder(destinationFolder))
        {
            Directory.CreateDirectory(destinationFolder);
            AssetDatabase.Refresh();
        }

        var fileName = Path.GetFileName(sourcePath);
        var destinationPath = Path.Combine(destinationFolder, fileName);

        File.Copy(sourcePath, destinationPath, overwrite: true);
        AssetDatabase.ImportAsset(destinationPath);

        PartsManifestBuilder.BuildManifestMenu();
        SpriteLibraryAutoPopulator.Populate();

        Debug.Log($"Imported generated part to {destinationPath}");
    }
}
