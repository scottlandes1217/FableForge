using UnityEditor;
using UnityEngine;

/// <summary>
/// Sets imported textures to Sprite mode with Sprite Mode = Single by default
/// so you don't have to change it manually for every character part asset.
/// </summary>
public class SpriteModeTexturePostprocessor : AssetPostprocessor
{
    private void OnPreprocessTexture()
    {
        var importer = (TextureImporter)assetImporter;
        if (importer == null)
        {
            return;
        }

        var path = assetPath.Replace('\\', '/');
        if (!path.StartsWith("Assets/"))
        {
            return;
        }

        // Apply to character parts and common sprite folders so new assets get Single by default.
        bool isCharacterOrSpriteArt = path.IndexOf("/Characters/", System.StringComparison.OrdinalIgnoreCase) >= 0
            || path.IndexOf("/CharacterParts/", System.StringComparison.OrdinalIgnoreCase) >= 0
            || path.IndexOf("/Sprites/", System.StringComparison.OrdinalIgnoreCase) >= 0
            || path.IndexOf("/Data/CharacterParts/", System.StringComparison.OrdinalIgnoreCase) >= 0;

        if (!isCharacterOrSpriteArt)
        {
            return;
        }

        // Skip paths that are likely sprite atlases (multi-sprite).
        if (path.IndexOf("Atlas", System.StringComparison.OrdinalIgnoreCase) >= 0
            || path.IndexOf("SpriteSheet", System.StringComparison.OrdinalIgnoreCase) >= 0)
        {
            return;
        }

        // Default to Sprite + Single so you don't have to set it per asset.
        if (importer.textureType != TextureImporterType.Sprite)
        {
            importer.textureType = TextureImporterType.Sprite;
        }

        if (importer.spriteImportMode != SpriteImportMode.Single)
        {
            importer.spriteImportMode = SpriteImportMode.Single;
        }
    }
}
