using System;
using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEngine;

public static class XcodeProjectImporter
{
    private const string DefaultSourcePath = "/Users/scottlandes/Projects/FableForge";
    private const string TargetFolderName = "XcodeImport";

    private static readonly HashSet<string> ExcludedExtensions = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
    };

    private static readonly HashSet<string> ExcludedDirectoryNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        ".git",
        ".svn",
        ".hg",
    };

    private static readonly HashSet<string> ExcludedFileNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        ".DS_Store",
    };

    [MenuItem("Tools/FableForge/Import Xcode Project")]
    public static void ImportXcodeProject()
    {
        var sourcePath = DefaultSourcePath;
        if (!Directory.Exists(sourcePath))
        {
            Debug.LogError($"Xcode project not found at: {sourcePath}");
            return;
        }

        var targetRoot = Path.Combine(Application.dataPath, TargetFolderName);
        EnsureDirectory(targetRoot);

        var copiedCount = 0;
        var skippedCount = 0;

        foreach (var dir in Directory.EnumerateDirectories(sourcePath, "*", SearchOption.AllDirectories))
        {
            var relativeDir = Path.GetRelativePath(sourcePath, dir);
            if (IsExcludedDirectory(dir) || IsExcludedRelativePath(relativeDir))
            {
                skippedCount++;
                continue;
            }

            EnsureDirectory(Path.Combine(targetRoot, relativeDir));
        }

        foreach (var file in Directory.EnumerateFiles(sourcePath, "*", SearchOption.AllDirectories))
        {
            var relativeFile = Path.GetRelativePath(sourcePath, file);
            if (IsExcludedDirectory(Path.GetDirectoryName(file) ?? string.Empty) ||
                IsExcludedRelativePath(relativeFile))
            {
                skippedCount++;
                continue;
            }

            if (ExcludedFileNames.Contains(Path.GetFileName(file)) ||
                ExcludedExtensions.Contains(Path.GetExtension(file)))
            {
                skippedCount++;
                continue;
            }

            var destination = Path.Combine(targetRoot, relativeFile);
            EnsureDirectory(Path.GetDirectoryName(destination) ?? targetRoot);

            try
            {
                File.Copy(file, destination, true);
                copiedCount++;
            }
            catch (Exception ex)
            {
                skippedCount++;
                Debug.LogWarning($"Skipped file due to error: {file} ({ex.GetType().Name})");
            }
        }

        Debug.Log($"Xcode import complete. Copied {copiedCount} file(s), skipped {skippedCount}.");
        AssetDatabase.Refresh();
    }

    private static bool IsExcludedDirectory(string path)
    {
        if (string.IsNullOrEmpty(path))
        {
            return false;
        }

        var segments = path.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        foreach (var segment in segments)
        {
            if (ExcludedDirectoryNames.Contains(segment))
            {
                return true;
            }

            if (segment.StartsWith(".") && segment.Length > 1)
            {
                return true;
            }
        }

        return false;
    }

    private static bool IsExcludedRelativePath(string relativePath)
    {
        if (string.IsNullOrEmpty(relativePath))
        {
            return false;
        }

        var segments = relativePath.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        foreach (var segment in segments)
        {
            if (ExcludedDirectoryNames.Contains(segment))
            {
                return true;
            }

            if (segment.StartsWith(".") && segment.Length > 1)
            {
                return true;
            }
        }

        return false;
    }

    private static void EnsureDirectory(string path)
    {
        if (!Directory.Exists(path))
        {
            Directory.CreateDirectory(path);
        }
    }
}
