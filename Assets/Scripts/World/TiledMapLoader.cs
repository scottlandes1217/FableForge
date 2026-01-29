using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Xml.Linq;
using UnityEngine;

public static class TiledMapLoader
{
    public static TiledMapData LoadFromFile(string absolutePath)
    {
        if (string.IsNullOrWhiteSpace(absolutePath) || !File.Exists(absolutePath))
        {
            return null;
        }

        var document = XDocument.Load(absolutePath);
        if (document.Root == null || document.Root.Name.LocalName != "map")
        {
            return null;
        }

        var mapElement = document.Root;
        var map = new TiledMapData
        {
            orientation = mapElement.Attribute("orientation")?.Value,
            renderOrder = mapElement.Attribute("renderorder")?.Value,
            width = GetInt(mapElement, "width"),
            height = GetInt(mapElement, "height"),
            tileWidth = GetInt(mapElement, "tilewidth"),
            tileHeight = GetInt(mapElement, "tileheight"),
            infinite = GetInt(mapElement, "infinite") == 1,
            sourcePath = absolutePath
        };

        foreach (var tilesetElement in mapElement.Elements("tileset"))
        {
            var tileset = LoadTilesetElement(tilesetElement, absolutePath);
            if (tileset == null)
            {
                continue;
            }

            map.tilesets.Add(tileset);
        }

        foreach (var layerElement in mapElement.Elements("layer"))
        {
            var layer = new TiledLayerData
            {
                name = layerElement.Attribute("name")?.Value,
                width = GetInt(layerElement, "width"),
                height = GetInt(layerElement, "height"),
                properties = ParseProperties(layerElement.Element("properties"))
            };

            var dataElement = layerElement.Element("data");
            if (dataElement == null)
            {
                continue;
            }

            var encoding = dataElement.Attribute("encoding")?.Value;
            if (!string.Equals(encoding, "csv", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var chunks = dataElement.Elements("chunk").ToList();
            if (chunks.Count > 0)
            {
                foreach (var chunkElement in chunks)
                {
                    var chunk = new TiledChunkData
                    {
                        x = GetInt(chunkElement, "x"),
                        y = GetInt(chunkElement, "y"),
                        width = GetInt(chunkElement, "width"),
                        height = GetInt(chunkElement, "height"),
                        gids = ParseCsv(chunkElement.Value)
                    };
                    layer.chunks.Add(chunk);
                }
            }
            else
            {
                var chunk = new TiledChunkData
                {
                    x = 0,
                    y = 0,
                    width = layer.width,
                    height = layer.height,
                    gids = ParseCsv(dataElement.Value)
                };
                layer.chunks.Add(chunk);
            }

            map.layers.Add(layer);
        }

        foreach (var objectGroupElement in mapElement.Elements("objectgroup"))
        {
            var group = new TiledObjectGroupData
            {
                name = objectGroupElement.Attribute("name")?.Value,
                properties = ParseProperties(objectGroupElement.Element("properties"))
            };

            foreach (var objectElement in objectGroupElement.Elements("object"))
            {
                var obj = new TiledObjectData
                {
                    id = GetInt(objectElement, "id"),
                    name = objectElement.Attribute("name")?.Value,
                    type = objectElement.Attribute("type")?.Value,
                    gid = GetInt(objectElement, "gid"),
                    x = GetFloat(objectElement, "x"),
                    y = GetFloat(objectElement, "y"),
                    width = GetFloat(objectElement, "width"),
                    height = GetFloat(objectElement, "height"),
                    properties = ParseProperties(objectElement.Element("properties"))
                };

                group.objects.Add(obj);
            }

            map.objectGroups.Add(group);
        }

        map.tilesets = map.tilesets.OrderBy(item => item.firstGid).ToList();
        return map;
    }

    public static TiledTilesetData LoadTilesetFromFile(string absolutePath)
    {
        if (string.IsNullOrWhiteSpace(absolutePath))
        {
            return null;
        }

        XDocument document = null;
        if (File.Exists(absolutePath))
        {
            document = XDocument.Load(absolutePath);
        }
        else
        {
            var resourcePath = ToResourcesPath(absolutePath);
            if (!string.IsNullOrWhiteSpace(resourcePath))
            {
                var textAsset = Resources.Load<TextAsset>(resourcePath);
                if (textAsset != null && !string.IsNullOrWhiteSpace(textAsset.text))
                {
                    document = XDocument.Parse(textAsset.text);
                    Debug.Log($"[Tiles] Loaded tileset from Resources: {resourcePath}");
                }
                else
                {
                    Debug.LogWarning($"[Tiles] Missing tileset resource: {resourcePath}");
                }
            }
        }

        if (document == null)
        {
            Debug.LogWarning($"[Tiles] Failed to load tileset: {absolutePath}");
            return null;
        }

        if (document.Root == null || document.Root.Name.LocalName != "tileset")
        {
            return null;
        }

        var tilesetElement = document.Root;
        var tileset = new TiledTilesetData
        {
            name = tilesetElement.Attribute("name")?.Value,
            tileWidth = GetInt(tilesetElement, "tilewidth"),
            tileHeight = GetInt(tilesetElement, "tileheight"),
            tileCount = GetInt(tilesetElement, "tilecount"),
            columns = GetInt(tilesetElement, "columns"),
            sourcePath = absolutePath
        };

        var imageElement = tilesetElement.Element("image");
        if (imageElement != null)
        {
            tileset.imageSource = imageElement.Attribute("source")?.Value;
            tileset.imageWidth = GetInt(imageElement, "width");
            tileset.imageHeight = GetInt(imageElement, "height");
        }

        ParseTilesetTiles(tilesetElement, tileset);

        return tileset;
    }

    private static string ToResourcesPath(string absolutePath)
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

    private static uint[] ParseCsv(string csv)
    {
        if (string.IsNullOrWhiteSpace(csv))
        {
            return Array.Empty<uint>();
        }

        var values = csv
            .Split(new[] { ',', '\n', '\r', '\t', ' ' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(value =>
            {
                if (uint.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed))
                {
                    return parsed;
                }

                return 0u;
            })
            .ToArray();

        return values;
    }

    private static int GetInt(XElement element, string attributeName)
    {
        if (element == null)
        {
            return 0;
        }

        var value = element.Attribute(attributeName)?.Value;
        return int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed)
            ? parsed
            : 0;
    }

    private static float GetFloat(XElement element, string attributeName)
    {
        if (element == null)
        {
            return 0f;
        }

        var value = element.Attribute(attributeName)?.Value;
        return float.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed)
            ? parsed
            : 0f;
    }

    private static TiledTilesetData LoadTilesetElement(XElement tilesetElement, string mapPath)
    {
        if (tilesetElement == null)
        {
            return null;
        }

        var sourceAttribute = tilesetElement.Attribute("source")?.Value;
        if (!string.IsNullOrWhiteSpace(sourceAttribute))
        {
            var resolved = ResolveTilesetSource(mapPath, sourceAttribute);
            var external = LoadTilesetFromFile(resolved);
            if (external != null)
            {
                external.firstGid = GetInt(tilesetElement, "firstgid");
                return external;
            }
        }

        var tileset = new TiledTilesetData
        {
            firstGid = GetInt(tilesetElement, "firstgid"),
            name = tilesetElement.Attribute("name")?.Value,
            tileWidth = GetInt(tilesetElement, "tilewidth"),
            tileHeight = GetInt(tilesetElement, "tileheight"),
            tileCount = GetInt(tilesetElement, "tilecount"),
            columns = GetInt(tilesetElement, "columns"),
            sourcePath = mapPath
        };

        var imageElement = tilesetElement.Element("image");
        if (imageElement != null)
        {
            tileset.imageSource = imageElement.Attribute("source")?.Value;
            tileset.imageWidth = GetInt(imageElement, "width");
            tileset.imageHeight = GetInt(imageElement, "height");
        }

        ParseTilesetTiles(tilesetElement, tileset);
        return tileset;
    }

    private static void ParseTilesetTiles(XElement tilesetElement, TiledTilesetData tileset)
    {
        foreach (var tileElement in tilesetElement.Elements("tile"))
        {
            var id = GetInt(tileElement, "id");
            if (id < 0)
            {
                continue;
            }

            var type = tileElement.Attribute("type")?.Value;
            if (string.IsNullOrWhiteSpace(type))
            {
                type = tileElement.Attribute("class")?.Value;
            }
            if (!string.IsNullOrWhiteSpace(type))
            {
                if (!tileset.typeToIds.TryGetValue(type, out var ids))
                {
                    ids = new List<int>();
                    tileset.typeToIds[type] = ids;
                }
                ids.Add(id);
            }

            var animationElement = tileElement.Element("animation");
            if (animationElement != null)
            {
                var frames = new List<TiledTileAnimationFrame>();
                foreach (var frameElement in animationElement.Elements("frame"))
                {
                    var frameId = GetInt(frameElement, "tileid");
                    var duration = GetInt(frameElement, "duration");
                    frames.Add(new TiledTileAnimationFrame { tileId = frameId, durationMs = duration });
                }

                if (frames.Count > 0)
                {
                    tileset.animations[id] = frames;
                }
            }
        }
    }

    private static string ResolveTilesetSource(string mapPath, string tilesetSource)
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

        var xcodeRoot = Path.Combine(Application.dataPath, "XcodeImport", "FableForge Shared");
        var xcodeResolved = Path.GetFullPath(Path.Combine(xcodeRoot, tilesetSource));
        if (File.Exists(xcodeResolved))
        {
            return xcodeResolved;
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
            var resourcesTsx = Path.Combine(Application.dataPath, "Resources/Maps/TSX", tilesetFile);
            if (File.Exists(resourcesTsx))
            {
                return resourcesTsx;
            }

            var customTsx = Path.Combine(Application.dataPath, "Resources/Maps/CustomMaps", tilesetFile);
            if (File.Exists(customTsx))
            {
                return customTsx;
            }
        }

        return resolved;
    }

    private static Dictionary<string, string> ParseProperties(XElement propertiesElement)
    {
        var properties = new Dictionary<string, string>();
        if (propertiesElement == null)
        {
            return properties;
        }

        foreach (var property in propertiesElement.Elements("property"))
        {
            var name = property.Attribute("name")?.Value;
            if (string.IsNullOrWhiteSpace(name))
            {
                continue;
            }

            var value = property.Attribute("value")?.Value;
            if (string.IsNullOrEmpty(value))
            {
                value = property.Value;
            }

            properties[name] = value ?? string.Empty;
        }

        return properties;
    }
}

public class TiledMapData
{
    public string orientation;
    public string renderOrder;
    public int width;
    public int height;
    public int tileWidth;
    public int tileHeight;
    public bool infinite;
    public string sourcePath;
    public List<TiledTilesetData> tilesets = new List<TiledTilesetData>();
    public List<TiledLayerData> layers = new List<TiledLayerData>();
    public List<TiledObjectGroupData> objectGroups = new List<TiledObjectGroupData>();
}

public class TiledTilesetData
{
    public int firstGid;
    public string name;
    public int tileWidth;
    public int tileHeight;
    public int tileCount;
    public int columns;
    public string imageSource;
    public int imageWidth;
    public int imageHeight;
    public string sourcePath;
    public Dictionary<string, List<int>> typeToIds = new Dictionary<string, List<int>>();
    public Dictionary<int, List<TiledTileAnimationFrame>> animations = new Dictionary<int, List<TiledTileAnimationFrame>>();
}

public class TiledLayerData
{
    public string name;
    public int width;
    public int height;
    public Dictionary<string, string> properties = new Dictionary<string, string>();
    public List<TiledChunkData> chunks = new List<TiledChunkData>();
}

public class TiledChunkData
{
    public int x;
    public int y;
    public int width;
    public int height;
    public uint[] gids = Array.Empty<uint>();
}

public class TiledTileAnimationFrame
{
    public int tileId;
    public int durationMs;
}

public class TiledObjectGroupData
{
    public string name;
    public Dictionary<string, string> properties = new Dictionary<string, string>();
    public List<TiledObjectData> objects = new List<TiledObjectData>();
}

public class TiledObjectData
{
    public int id;
    public string name;
    public string type;
    public int gid;
    public float x;
    public float y;
    public float width;
    public float height;
    public Dictionary<string, string> properties = new Dictionary<string, string>();
}
