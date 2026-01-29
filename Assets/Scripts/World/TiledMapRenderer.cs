using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
#if UNITY_EDITOR
using UnityEditor;
#endif

public class TiledMapRenderer
{
    private const uint FlippedHorizontallyFlag = 0x80000000;
    private const uint FlippedVerticallyFlag = 0x40000000;
    private const uint FlippedDiagonallyFlag = 0x20000000;
    private const uint FlipMask = ~(FlippedHorizontallyFlag | FlippedVerticallyFlag | FlippedDiagonallyFlag);

    private readonly Dictionary<string, Texture2D> textureCache = new Dictionary<string, Texture2D>();

    public bool Render(TiledMapData map, Transform parent, float tileScale, out Bounds bounds)
    {
        bounds = new Bounds(Vector3.zero, Vector3.zero);
        if (map == null || map.tilesets.Count == 0 || map.layers.Count == 0)
        {
            return false;
        }

        var resolvedScale = Mathf.Max(0.01f, tileScale);
        var hasBounds = false;
        var layerIndex = 0;
        foreach (var layer in map.layers)
        {
            var layerRoot = new GameObject(layer.name ?? $"Layer_{layerIndex}");
            layerRoot.transform.SetParent(parent, false);

            var zOffset = 0f;
            if (layer.properties != null && layer.properties.TryGetValue("zOffset", out var zOffsetValue))
            {
                float.TryParse(zOffsetValue, out zOffset);
            }

            foreach (var chunk in layer.chunks)
            {
                RenderChunk(map, layer, chunk, layerRoot.transform, layerIndex, zOffset, resolvedScale, ref bounds, ref hasBounds);
            }

            layerIndex++;
        }

        return hasBounds;
    }

    private void RenderChunk(
        TiledMapData map,
        TiledLayerData layer,
        TiledChunkData chunk,
        Transform parent,
        int layerIndex,
        float zOffset,
        float tileScale,
        ref Bounds bounds,
        ref bool hasBounds)
    {
        if (chunk.gids == null || chunk.gids.Length == 0)
        {
            return;
        }

        var tilesWide = chunk.width;
        var tilesHigh = chunk.height;
        var expected = tilesWide * tilesHigh;
        if (chunk.gids.Length < expected)
        {
            return;
        }

        for (var row = 0; row < tilesHigh; row++)
        {
            for (var col = 0; col < tilesWide; col++)
            {
                var index = row * tilesWide + col;
                var rawGid = chunk.gids[index];
                if (rawGid == 0)
                {
                    continue;
                }

                var flipH = (rawGid & FlippedHorizontallyFlag) != 0;
                var flipV = (rawGid & FlippedVerticallyFlag) != 0;
                var flipD = (rawGid & FlippedDiagonallyFlag) != 0;
                var gid = (int)(rawGid & FlipMask);

                var tileset = ResolveTileset(map, gid);
                if (tileset == null)
                {
                    continue;
                }

                var sprite = CreateSprite(map, tileset, gid);
                if (sprite == null)
                {
                    continue;
                }

                var tileX = chunk.x + col;
                var tileY = chunk.y + row;
                var worldX = (tileX + 0.5f) * tileScale;
                var worldY = (-tileY - 0.5f) * tileScale;
                var pixelSize = map.tileWidth > 0 ? tileScale / map.tileWidth : 0f;
                if (pixelSize > 0f)
                {
                    worldX = SnapToPixelGrid(worldX, pixelSize);
                    worldY = SnapToPixelGrid(worldY, pixelSize);
                }

                var tileObject = new GameObject($"Tile_{tileX}_{tileY}");
                tileObject.transform.SetParent(parent, false);
                tileObject.transform.localPosition = new Vector3(worldX, worldY, 0f);

                var renderer = tileObject.AddComponent<SpriteRenderer>();
                renderer.sprite = sprite;
                var sortingOrder = Mathf.RoundToInt(layerIndex * 10f + zOffset);
                renderer.sortingOrder = sortingOrder;

                var scaleX = flipH ? -1f : 1f;
                var scaleY = flipV ? -1f : 1f;
                if (flipD)
                {
                    var temp = scaleX;
                    scaleX = scaleY;
                    scaleY = temp;
                }
                tileObject.transform.localScale = new Vector3(scaleX * tileScale, scaleY * tileScale, 1f);

                var tileId = gid - tileset.firstGid;
                if (tileId >= 0 && tileset.animations != null && tileset.animations.TryGetValue(tileId, out var frames))
                {
                    var animatedFrames = BuildAnimationFrames(map, tileset, frames);
                    if (animatedFrames.Count > 0)
                    {
                        var animator = tileObject.AddComponent<TiledTileAnimator>();
                        animator.SetFrames(animatedFrames);
                    }
                }

                var tileBounds = renderer.bounds;
                if (!hasBounds)
                {
                    bounds = tileBounds;
                    hasBounds = true;
                }
                else
                {
                    bounds.Encapsulate(tileBounds);
                }
            }
        }
    }

    private TiledTilesetData ResolveTileset(TiledMapData map, int gid)
    {
        TiledTilesetData selected = null;
        foreach (var tileset in map.tilesets)
        {
            if (gid >= tileset.firstGid)
            {
                selected = tileset;
            }
            else
            {
                break;
            }
        }

        return selected;
    }

    private Sprite CreateSprite(TiledMapData map, TiledTilesetData tileset, int gid)
    {
        var tileId = gid - tileset.firstGid;
        if (tileId < 0)
        {
            return null;
        }

        var texture = LoadTilesetTexture(map.sourcePath, tileset);
        if (texture == null || tileset.columns <= 0)
        {
            return null;
        }

        var col = tileId % tileset.columns;
        var row = tileId / tileset.columns;
        var rect = new Rect(
            col * tileset.tileWidth,
            tileset.imageHeight - ((row + 1) * tileset.tileHeight),
            tileset.tileWidth,
            tileset.tileHeight);

        if (rect.xMax > texture.width || rect.yMax > texture.height)
        {
            return null;
        }

        return Sprite.Create(texture, rect, new Vector2(0.5f, 0.5f), map.tileWidth);
    }

    private List<TiledTileAnimator.FrameData> BuildAnimationFrames(TiledMapData map, TiledTilesetData tileset, List<TiledTileAnimationFrame> frames)
    {
        var results = new List<TiledTileAnimator.FrameData>();
        if (frames == null || frames.Count == 0)
        {
            return results;
        }

        foreach (var frame in frames)
        {
            var sprite = CreateSpriteFromTileset(tileset, frame.tileId, map.sourcePath, map.tileWidth);
            if (sprite == null)
            {
                continue;
            }

            var duration = Mathf.Max(0.01f, frame.durationMs / 1000f);
            results.Add(new TiledTileAnimator.FrameData(sprite, duration));
        }

        return results;
    }

    public Sprite CreateSpriteFromTileset(TiledTilesetData tileset, int tileId, string sourcePath, int pixelsPerUnit)
    {
        if (tileset == null || tileId < 0)
        {
            return null;
        }

        var texture = LoadTilesetTexture(sourcePath, tileset);
        if (texture == null || tileset.columns <= 0)
        {
            if (texture == null)
            {
                Debug.LogWarning($"[Tiles] Texture missing for tileset '{tileset.name}' source '{tileset.imageSource}'");
            }
            return null;
        }

        var col = tileId % tileset.columns;
        var row = tileId / tileset.columns;
        var rect = new Rect(
            col * tileset.tileWidth,
            tileset.imageHeight - ((row + 1) * tileset.tileHeight),
            tileset.tileWidth,
            tileset.tileHeight);

        if (rect.xMax > texture.width || rect.yMax > texture.height)
        {
            Debug.LogWarning($"[Tiles] Rect out of bounds for tileset '{tileset.name}' tile {tileId} rect {rect} texture {texture.width}x{texture.height}");
            return null;
        }

        return Sprite.Create(texture, rect, new Vector2(0.5f, 0.5f), pixelsPerUnit);
    }

    private Texture2D LoadTilesetTexture(string mapPath, TiledTilesetData tileset)
    {
        if (string.IsNullOrWhiteSpace(tileset.imageSource))
        {
            return null;
        }

        var basePath = !string.IsNullOrWhiteSpace(tileset.sourcePath) ? tileset.sourcePath : mapPath;
        var absolutePath = ResolveTilesetPath(basePath, tileset.imageSource);
        if (string.IsNullOrWhiteSpace(absolutePath))
        {
            var resourceTexture = LoadTilesetTextureFromResources(tileset.imageSource);
            if (resourceTexture != null)
            {
                ApplyTilesetTextureSettings(resourceTexture);
                return resourceTexture;
            }

            Debug.LogWarning($"[Tiles] Texture path unresolved for tileset '{tileset.name}' source '{tileset.imageSource}'");
            return null;
        }

        if (textureCache.TryGetValue(absolutePath, out var cached))
        {
            return cached;
        }

        var resourcePath = ToResourcesPathFromAbsolute(absolutePath);
        if (!string.IsNullOrWhiteSpace(resourcePath))
        {
            if (textureCache.TryGetValue(resourcePath, out var cachedResource))
            {
                textureCache[absolutePath] = cachedResource;
                return cachedResource;
            }
        }

#if UNITY_EDITOR
        if (File.Exists(absolutePath))
        {
            var rawBytes = File.ReadAllBytes(absolutePath);
            var rawTexture = new Texture2D(2, 2, TextureFormat.RGBA32, false);
            if (rawTexture.LoadImage(rawBytes))
            {
                ApplyTilesetTextureSettings(rawTexture);
                textureCache[absolutePath] = rawTexture;
                if (!string.IsNullOrWhiteSpace(resourcePath))
                {
                    textureCache[resourcePath] = rawTexture;
                }
                return rawTexture;
            }
            Debug.LogWarning($"[Tiles] Failed to load texture bytes for {absolutePath}");
        }
#endif

#if UNITY_EDITOR
        var assetPath = ToAssetPath(absolutePath);
        if (!string.IsNullOrWhiteSpace(assetPath))
        {
            var assetTexture = AssetDatabase.LoadAssetAtPath<Texture2D>(assetPath);
                if (assetTexture != null)
                {
                    ApplyTilesetTextureSettings(assetTexture);
                    textureCache[absolutePath] = assetTexture;
                    return assetTexture;
                }
        }
#endif

        if (!string.IsNullOrWhiteSpace(resourcePath))
        {
            var resourceTexture = Resources.Load<Texture2D>(resourcePath);
            if (resourceTexture != null)
            {
                ApplyTilesetTextureSettings(resourceTexture);
                textureCache[absolutePath] = resourceTexture;
                textureCache[resourcePath] = resourceTexture;
                return resourceTexture;
            }
        }

        if (!File.Exists(absolutePath))
        {
            var resourceTexture = LoadTilesetTextureFromResources(tileset.imageSource);
            if (resourceTexture != null)
            {
                ApplyTilesetTextureSettings(resourceTexture);
                return resourceTexture;
            }

            Debug.LogWarning($"[Tiles] Texture file missing at {absolutePath}");
            return null;
        }

        var bytes = File.ReadAllBytes(absolutePath);
        var texture = new Texture2D(2, 2, TextureFormat.RGBA32, false);
        if (!texture.LoadImage(bytes))
        {
            Debug.LogWarning($"[Tiles] Failed to load texture bytes for {absolutePath}");
            return null;
        }

        ApplyTilesetTextureSettings(texture);
        textureCache[absolutePath] = texture;
        return texture;
    }

    private string ToResourcesPathFromAbsolute(string absolutePath)
    {
        if (string.IsNullOrWhiteSpace(absolutePath))
        {
            return null;
        }

        var normalized = absolutePath.Replace('\\', '/');
        var marker = "/Resources/";
        var index = normalized.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
        if (index < 0)
        {
            return null;
        }

        var resourcePath = normalized.Substring(index + marker.Length);
        var extension = Path.GetExtension(resourcePath);
        if (!string.IsNullOrWhiteSpace(extension))
        {
            resourcePath = resourcePath.Substring(0, resourcePath.Length - extension.Length);
        }

        return resourcePath;
    }

    private Texture2D LoadTilesetTextureFromResources(string tilesetSource)
    {
        var resourcePath = ResolveResourcesTexturePath(tilesetSource);
        if (string.IsNullOrWhiteSpace(resourcePath))
        {
            return null;
        }

        if (textureCache.TryGetValue(resourcePath, out var cached))
        {
            return cached;
        }

        var texture = Resources.Load<Texture2D>(resourcePath);
        if (texture == null)
        {
            Debug.LogWarning($"[Tiles] Missing tileset texture resource: {resourcePath} (source: {tilesetSource})");
            return null;
        }

        textureCache[resourcePath] = texture;
        return texture;
    }

    private string ResolveResourcesTexturePath(string tilesetSource)
    {
        if (string.IsNullOrWhiteSpace(tilesetSource))
        {
            return null;
        }

        var normalized = tilesetSource.Replace('\\', '/');
        if (normalized.StartsWith("../", StringComparison.OrdinalIgnoreCase))
        {
            normalized = normalized.Substring(3);
        }

        var extension = Path.GetExtension(normalized);
        if (!string.IsNullOrWhiteSpace(extension))
        {
            normalized = normalized.Substring(0, normalized.Length - extension.Length);
        }

        return Path.Combine("Maps", normalized).Replace('\\', '/');
    }

    private static float SnapToPixelGrid(float value, float pixelSize)
    {
        if (pixelSize <= 0f)
        {
            return value;
        }

        return Mathf.Round(value / pixelSize) * pixelSize;
    }

    private static void ApplyTilesetTextureSettings(Texture2D texture)
    {
        if (texture == null)
        {
            return;
        }

        texture.filterMode = FilterMode.Point;
        texture.wrapMode = TextureWrapMode.Clamp;
        texture.anisoLevel = 0;
    }

    private string ResolveTilesetPath(string mapPath, string tilesetSource)
    {
        if (string.IsNullOrWhiteSpace(mapPath) || string.IsNullOrWhiteSpace(tilesetSource))
        {
            return null;
        }

        var mapDirectory = Path.GetDirectoryName(mapPath);
        if (string.IsNullOrWhiteSpace(mapDirectory))
        {
            return null;
        }

        var resolved = Path.GetFullPath(Path.Combine(mapDirectory, tilesetSource));
        if (File.Exists(resolved))
        {
            return resolved;
        }

        if (tilesetSource.StartsWith("Assets.xcassets", StringComparison.OrdinalIgnoreCase))
        {
            var xcodeRoot = Path.Combine(Application.dataPath, "XcodeImport", "FableForge Shared");
            var xcodeResolved = Path.GetFullPath(Path.Combine(xcodeRoot, tilesetSource));
            if (File.Exists(xcodeResolved))
            {
                return xcodeResolved;
            }

            var assetPrefix = "Assets.xcassets/";
            if (tilesetSource.StartsWith(assetPrefix, StringComparison.OrdinalIgnoreCase))
            {
                var assetRelative = tilesetSource.Substring(assetPrefix.Length);
                var tmxMapsResolved = Path.GetFullPath(Path.Combine(xcodeRoot, "Assets.xcassets", "TMX Maps", assetRelative));
                if (File.Exists(tmxMapsResolved))
                {
                    return tmxMapsResolved;
                }
            }
        }

        var xcodeImport = Path.Combine(Application.dataPath, "XcodeImport");
        var fallback = Path.GetFullPath(Path.Combine(xcodeImport, tilesetSource));
        if (File.Exists(fallback))
        {
            return fallback;
        }

        var tilesetFile = Path.GetFileName(tilesetSource);
        if (!string.IsNullOrWhiteSpace(tilesetFile))
        {
            var resourcesMaps = Path.Combine(Application.dataPath, "Resources/Maps");
            var terrainPath = Path.Combine(resourcesMaps, "Terrain", tilesetFile);
            if (File.Exists(terrainPath))
            {
                return terrainPath;
            }

            var tsxPath = Path.Combine(resourcesMaps, "TSX", tilesetFile);
            if (File.Exists(tsxPath))
            {
                return tsxPath;
            }

            var customPath = Path.Combine(resourcesMaps, "CustomMaps", tilesetFile);
            if (File.Exists(customPath))
            {
                return customPath;
            }
        }

        return null;
    }

#if UNITY_EDITOR
    private string ToAssetPath(string absolutePath)
    {
        var dataPath = Application.dataPath;
        if (!absolutePath.StartsWith(dataPath, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        return "Assets" + absolutePath.Substring(dataPath.Length);
    }
#endif
}
