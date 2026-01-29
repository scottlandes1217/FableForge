using System;
using System.Collections.Generic;
using System.IO;
using FableForge.Models;
using UnityEngine;

namespace FableForge.Systems
{
    [Serializable]
    public class SaveData
    {
        public Player player;
        public GameCharacter character;
        public string worldSeed;
        public long savedAtUnix;
        public string worldPrefabId;
        public string currentMapFileName;
        public bool useProceduralWorld;
        public bool hasPlayerPosition;
    }

    public class GameState : MonoBehaviour
    {
        public static GameState Instance { get; private set; }

        public SaveData CurrentSave { get; private set; }

        private void Awake()
        {
            if (Instance != null && Instance != this)
            {
                Destroy(gameObject);
                return;
            }

            Instance = this;
            DontDestroyOnLoad(gameObject);
        }

        public void SetSave(SaveData data)
        {
            CurrentSave = data;
        }
    }

    public static class SaveManager
    {
        private const string SlotKeyPrefix = "FableForge_SaveSlot_";

        public static string GetSlotPath(int slotIndex)
        {
            var dir = Path.Combine(Application.persistentDataPath, "Saves");
            Directory.CreateDirectory(dir);
            return Path.Combine(dir, $"slot_{slotIndex}.json");
        }

        public static void SaveSlot(int slotIndex, SaveData data)
        {
        if (data != null)
        {
            data.savedAtUnix = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        }
            var json = JsonUtility.ToJson(data, true);
            File.WriteAllText(GetSlotPath(slotIndex), json);
            PlayerPrefs.SetString($"{SlotKeyPrefix}{slotIndex}_LastPlayed", DateTime.UtcNow.ToString("O"));
            PlayerPrefs.Save();
        }

        public static SaveData LoadSlot(int slotIndex)
        {
            var path = GetSlotPath(slotIndex);
            if (!File.Exists(path))
            {
                return null;
            }

            var json = File.ReadAllText(path);
            return JsonUtility.FromJson<SaveData>(json);
        }
    }

    [Serializable]
    public class WorldConfig
    {
        public int width = 64;
        public int height = 64;
        public int seed = 0;
        public string name;
        public string description;
    }

    [Serializable]
    public class TerrainThresholds
    {
        public float water = 0.15f;
        public float grass = 0.9f;
        public float dirt = 0.95f;
    }

    public class WorldSystem : MonoBehaviour
    {
        public static WorldSystem Instance { get; private set; }

        public WorldConfig Config { get; private set; } = new WorldConfig();
        public int[,] Tiles { get; private set; }
        public string CurrentPrefabId { get; private set; }
        public PrefabWorldData CurrentPrefabData { get; private set; }

        private void Awake()
        {
            if (Instance != null && Instance != this)
            {
                Destroy(gameObject);
                return;
            }

            Instance = this;
            DontDestroyOnLoad(gameObject);
        }

        public void Initialize(WorldConfig config)
        {
            Config = config;
            Tiles = WorldGenerator.Generate(config);
        }

        public void InitializeFromPrefab(string prefabId, int fallbackWidth = 64, int fallbackHeight = 64)
        {
            var data = WorldPrefabLoader.Load(prefabId);
            if (data == null)
            {
                Debug.LogWarning($"[WorldSystem] Prefab world '{prefabId}' not found. Using fallback procedural world.");
            }
            var config = new WorldConfig
            {
                width = data?.width ?? fallbackWidth,
                height = data?.height ?? fallbackHeight,
                seed = data?.seed ?? UnityEngine.Random.Range(0, 100000),
                name = data?.name,
                description = data?.description
            };

            Config = config;
            Tiles = WorldGenerator.Generate(config, data?.thresholds, data?.waterFeatures);
            CurrentPrefabId = prefabId;
            CurrentPrefabData = data;
        }
    }

    public static class WorldGenerator
    {
        public static int[,] Generate(WorldConfig config)
        {
            return Generate(config, null, null);
        }

        public static int[,] Generate(WorldConfig config, TerrainThresholds thresholds, PrefabWaterFeaturesData waterFeatures)
        {
            var resolved = thresholds ?? new TerrainThresholds();
            var tiles = new int[config.width, config.height];

            var random = new System.Random(config.seed);
            var offsetX = (float)random.NextDouble() * 1000f;
            var offsetY = (float)random.NextDouble() * 1000f;
            var noiseScale = 0.08f;

            for (var x = 0; x < config.width; x++)
            {
                for (var y = 0; y < config.height; y++)
                {
                    var nx = (x + offsetX) * noiseScale;
                    var ny = (y + offsetY) * noiseScale;
                    var primary = Mathf.PerlinNoise(nx, ny);
                    var secondary = Mathf.PerlinNoise(nx * 2f, ny * 2f) * 0.5f;
                    var value = Mathf.Clamp01((primary + secondary) / 1.5f);

                    if (value < resolved.water)
                    {
                        tiles[x, y] = 0;
                    }
                    else if (value < resolved.grass)
                    {
                        tiles[x, y] = 1;
                    }
                    else if (value < resolved.dirt)
                    {
                        tiles[x, y] = 2;
                    }
                    else
                    {
                        tiles[x, y] = 3;
                    }
                }
            }

            ApplyWaterFeatures(tiles, config, random, waterFeatures);
            return tiles;
        }

        private static void ApplyWaterFeatures(int[,] tiles, WorldConfig config, System.Random random, PrefabWaterFeaturesData waterFeatures)
        {
            if (tiles == null || config == null || waterFeatures == null)
            {
                return;
            }

            if (!string.Equals(waterFeatures.type, "rivers", StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            var density = (waterFeatures.density ?? string.Empty).Trim().ToLowerInvariant();
            var riverCount = density switch
            {
                "low" => 1,
                "high" => 3,
                _ => 2
            };

            for (var i = 0; i < riverCount; i++)
            {
                CarveRiver(tiles, config, random);
            }
        }

        private static void CarveRiver(int[,] tiles, WorldConfig config, System.Random random)
        {
            var width = config.width;
            var height = config.height;
            if (width <= 0 || height <= 0)
            {
                return;
            }

            var startEdge = random.Next(0, 4);
            var x = 0;
            var y = 0;
            switch (startEdge)
            {
                case 0:
                    x = 0;
                    y = random.Next(0, height);
                    break;
                case 1:
                    x = width - 1;
                    y = random.Next(0, height);
                    break;
                case 2:
                    x = random.Next(0, width);
                    y = 0;
                    break;
                default:
                    x = random.Next(0, width);
                    y = height - 1;
                    break;
            }

            var dx = startEdge == 0 ? 1 : startEdge == 1 ? -1 : random.Next(0, 2) == 0 ? 1 : -1;
            var dy = startEdge == 2 ? 1 : startEdge == 3 ? -1 : random.Next(0, 2) == 0 ? 1 : -1;
            var steps = width + height;
            for (var step = 0; step < steps; step++)
            {
                for (var ox = -1; ox <= 1; ox++)
                {
                    for (var oy = -1; oy <= 1; oy++)
                    {
                        var rx = x + ox;
                        var ry = y + oy;
                        if (rx >= 0 && rx < width && ry >= 0 && ry < height)
                        {
                            tiles[rx, ry] = 0;
                        }
                    }
                }

                if (random.NextDouble() < 0.35)
                {
                    dx = random.Next(-1, 2);
                    if (dx == 0)
                    {
                        dx = random.Next(0, 2) == 0 ? 1 : -1;
                    }
                }

                if (random.NextDouble() < 0.35)
                {
                    dy = random.Next(-1, 2);
                    if (dy == 0)
                    {
                        dy = random.Next(0, 2) == 0 ? 1 : -1;
                    }
                }

                x += dx;
                y += dy;
                if (x < 0 || x >= width || y < 0 || y >= height)
                {
                    break;
                }
            }
        }
    }

    public class TileManager : MonoBehaviour
    {
        public static TileManager Instance { get; private set; }

        private void Awake()
        {
            if (Instance != null && Instance != this)
            {
                Destroy(gameObject);
                return;
            }

            Instance = this;
            DontDestroyOnLoad(gameObject);
        }
    }

    public class ChunkSystem
    {
        public int chunkSize = 16;
        public Dictionary<Vector2Int, int[,]> chunks = new Dictionary<Vector2Int, int[,]>();

        public int[,] GetChunk(Vector2Int coord, int[,] worldTiles)
        {
            if (chunks.TryGetValue(coord, out var cached))
            {
                return cached;
            }

            var chunk = new int[chunkSize, chunkSize];
            for (var x = 0; x < chunkSize; x++)
            {
                for (var y = 0; y < chunkSize; y++)
                {
                    var worldX = coord.x * chunkSize + x;
                    var worldY = coord.y * chunkSize + y;
                    if (worldX >= 0 && worldY >= 0 && worldX < worldTiles.GetLength(0) && worldY < worldTiles.GetLength(1))
                    {
                        chunk[x, y] = worldTiles[worldX, worldY];
                    }
                }
            }

            chunks[coord] = chunk;
            return chunk;
        }
    }

    public class DialogueSystem : MonoBehaviour
    {
        public static DialogueSystem Instance { get; private set; }

        private void Awake()
        {
            if (Instance != null && Instance != this)
            {
                Destroy(gameObject);
                return;
            }

            Instance = this;
            DontDestroyOnLoad(gameObject);
        }

        public void StartDialogue(string dialogueId)
        {
            Debug.Log($"Dialogue started: {dialogueId}");
        }
    }

    public class CombatSystem : MonoBehaviour
    {
        public static CombatSystem Instance { get; private set; }

        private void Awake()
        {
            if (Instance != null && Instance != this)
            {
                Destroy(gameObject);
                return;
            }

            Instance = this;
            DontDestroyOnLoad(gameObject);
        }

        public void StartCombat(Player player, List<Animal> enemies)
        {
            Debug.Log($"Combat started with {enemies?.Count ?? 0} enemies.");
        }
    }

    public static class DeltaPersistence
    {
        public static string ComputeDelta(string previousJson, string nextJson)
        {
            return nextJson;
        }
    }

    public static class TiledMapParser
    {
        public static int[,] Parse(string json)
        {
            return new int[0, 0];
        }
    }

    public static class TMXInstanceLoader
    {
        public static int[,] LoadFromFile(string path)
        {
            return new int[0, 0];
        }
    }

    public static class TerrainAutotiling
    {
        public static int ComputeTileIndex(int[,] tiles, int x, int y)
        {
            return tiles[x, y];
        }
    }

    public static class PrefabFactory
    {
        private static Sprite cachedWhiteSprite;

        public static GameObject CreatePlaceholder(Vector3 position, Color color, float size)
        {
            var obj = new GameObject("Tile");
            var renderer = obj.AddComponent<SpriteRenderer>();
            renderer.sprite = GetWhiteSprite();
            renderer.color = color;
            obj.transform.position = position;
            obj.transform.localScale = new Vector3(size, size, 1f);
            return obj;
        }

        public static GameObject CreateMarker(string name, Vector3 position, Color color, float size, int sortingOrder)
        {
            var obj = new GameObject(name);
            var renderer = obj.AddComponent<SpriteRenderer>();
            renderer.sprite = GetWhiteSprite();
            renderer.color = color;
            renderer.sortingOrder = sortingOrder;
            obj.transform.position = position;
            obj.transform.localScale = new Vector3(size, size, 1f);
            return obj;
        }

        private static Sprite GetWhiteSprite()
        {
            if (cachedWhiteSprite != null)
            {
                return cachedWhiteSprite;
            }

            var texture = new Texture2D(1, 1, TextureFormat.RGBA32, false);
            texture.SetPixel(0, 0, Color.white);
            texture.Apply();
            cachedWhiteSprite = Sprite.Create(texture, new Rect(0, 0, 1, 1), new Vector2(0.5f, 0.5f), 1f);
            return cachedWhiteSprite;
        }
    }

    public static class WorldPrefabLoader
    {
        private static readonly string[] CandidatePaths =
        {
            "XcodeImport/FableForge Shared/Prefabs/Maps"
        };

        private static readonly string[] ChestCandidatePaths =
        {
            "Resources/Prefabs/Objects",
            "XcodeImport/FableForge Shared/Prefabs/Objects",
            "XcodeImport/Prefabs/Objects"
        };

        private static readonly string[] ItemCandidatePaths =
        {
            "Resources/Prefabs/Objects",
            "XcodeImport/FableForge Shared/Prefabs/Objects",
            "XcodeImport/Prefabs/Objects"
        };

        private static readonly string[] CompanionCandidatePaths =
        {
            "Resources/Prefabs/Data",
            "XcodeImport/FableForge Shared/Prefabs/Data",
            "XcodeImport/Prefabs/Data"
        };

        private static readonly string[] EnemyCandidatePaths =
        {
            "Resources/Prefabs/Data",
            "XcodeImport/FableForge Shared/Prefabs/Data",
            "XcodeImport/Prefabs/Data"
        };

        public static PrefabWorldData Load(string prefabId)
        {
            if (string.IsNullOrWhiteSpace(prefabId))
            {
                return null;
            }

            var json = LoadJson(prefabId);
            if (string.IsNullOrWhiteSpace(json))
            {
                return null;
            }

            var root = MiniJson.Deserialize(json) as Dictionary<string, object>;
            if (root == null || !root.TryGetValue("worldConfig", out var worldConfigObj))
            {
                return null;
            }

            var worldConfig = worldConfigObj as Dictionary<string, object>;
            if (worldConfig == null)
            {
                return null;
            }

            var data = new PrefabWorldData
            {
                name = GetString(worldConfig, "name"),
                description = GetString(worldConfig, "description"),
                tmxFile = GetString(worldConfig, "tmxFile"),
                seed = GetInt(worldConfig, "seed", UnityEngine.Random.Range(0, 100000)),
                width = GetInt(worldConfig, "width", 64),
                height = GetInt(worldConfig, "height", 64),
                thresholds = new TerrainThresholds(),
                entities = new PrefabEntitiesData(),
                enterConfig = new PrefabEnterConfig(),
                prefabs = new List<PrefabDefinition>()
            };

            if (worldConfig.TryGetValue("terrain", out var terrainObj))
            {
                var terrain = terrainObj as Dictionary<string, object>;
                if (terrain != null)
                {
                    data.thresholds.water = GetFloat(terrain, "waterThreshold", data.thresholds.water);
                    data.thresholds.grass = GetFloat(terrain, "grassThreshold", data.thresholds.grass);
                    data.thresholds.dirt = GetFloat(terrain, "dirtThreshold", data.thresholds.dirt);

                    if (terrain.TryGetValue("groundTiles", out var groundTilesObj))
                    {
                        var groundTiles = groundTilesObj as Dictionary<string, object>;
                        if (groundTiles != null)
                        {
                            data.groundTiles = new PrefabGroundTiles
                            {
                                water = GetStringListFlexible(groundTiles, "water"),
                                grass = GetStringListFlexible(groundTiles, "grass"),
                                dirt = GetStringListFlexible(groundTiles, "dirt"),
                                stone = GetStringListFlexible(groundTiles, "stone")
                            };
                        }
                    }
                }
            }

            if (worldConfig.TryGetValue("entities", out var entitiesObj))
            {
                var entities = entitiesObj as Dictionary<string, object>;
                if (entities != null)
                {
                    data.entities.treeDensity = GetFloat(entities, "treeDensity", data.entities.treeDensity);
                    data.entities.rockDensity = GetFloat(entities, "rockDensity", data.entities.rockDensity);
                    data.entities.treeBlockedTerrainTypes = GetStringList(entities, "treeBlockedTerrainTypes");
                    data.entities.rockBlockedTerrainTypes = GetStringList(entities, "rockBlockedTerrainTypes");
                    data.entities.treePrefabs = GetStringList(entities, "treePrefabs");
                    data.entities.rockPrefabs = GetStringList(entities, "rockPrefabs");
                    data.entities.chests = GetChestList(entities);
                }
            }

            if (worldConfig.TryGetValue("enemies", out var enemiesObj))
            {
                var enemies = enemiesObj as Dictionary<string, object>;
                if (enemies != null)
                {
                    data.enemies = new PrefabEnemySpawnData
                    {
                        spawnRate = GetFloat(enemies, "spawnRate", 0f),
                        types = GetStringList(enemies, "types"),
                        minLevel = GetInt(enemies, "minLevel", 1),
                        maxLevel = GetInt(enemies, "maxLevel", 1),
                        blockedTerrainTypes = GetStringList(enemies, "blockedTerrainTypes")
                    };
                }
            }

            if (worldConfig.TryGetValue("companions", out var companionsObj))
            {
                var companions = companionsObj as Dictionary<string, object>;
                if (companions != null)
                {
                    data.companions = new PrefabCompanionSpawnData
                    {
                        spawnRate = GetFloat(companions, "spawnRate", 0f),
                        types = GetStringList(companions, "types"),
                        friendlyChance = GetFloat(companions, "friendlyChance", 1f),
                        blockedTerrainTypes = GetStringList(companions, "blockedTerrainTypes")
                    };
                }
            }

            if (worldConfig.TryGetValue("waterFeatures", out var waterObj))
            {
                var water = waterObj as Dictionary<string, object>;
                if (water != null)
                {
                    data.waterFeatures = new PrefabWaterFeaturesData
                    {
                        type = GetString(water, "type"),
                        density = GetString(water, "density")
                    };
                }
            }

            if (worldConfig.TryGetValue("enterConfig", out var enterObj))
            {
                var enter = enterObj as Dictionary<string, object>;
                if (enter != null)
                {
                    data.enterConfig.x = GetInt(enter, "x", data.width / 2);
                    data.enterConfig.y = GetInt(enter, "y", data.height / 2);
                }
            }

            if (root.TryGetValue("prefabs", out var prefabsObj))
            {
                var prefabs = prefabsObj as List<object>;
                if (prefabs != null)
                {
                    foreach (var entry in prefabs)
                    {
                        if (entry is Dictionary<string, object> prefabDict)
                        {
                            data.prefabs.Add(ParsePrefab(prefabDict));
                        }
                    }
                }
            }

            return data;
        }

        public static Dictionary<string, PrefabDefinition> LoadChests()
        {
            var result = new Dictionary<string, PrefabDefinition>();
            var json = LoadJsonFromResources("Prefabs/Objects/chests", "chests.json", ChestCandidatePaths);
            if (string.IsNullOrWhiteSpace(json))
            {
                return result;
            }

            var root = MiniJson.Deserialize(json) as Dictionary<string, object>;
            if (root == null || !root.TryGetValue("chests", out var chestsObj))
            {
                return result;
            }

            if (chestsObj is List<object> list)
            {
                foreach (var entry in list)
                {
                    if (entry is Dictionary<string, object> chestDict)
                    {
                        var prefab = ParsePrefab(chestDict);
                        if (prefab != null && !string.IsNullOrWhiteSpace(prefab.id))
                        {
                            result[prefab.id] = prefab;
                            if (Application.isEditor && prefab.id == "chest_wooden_01")
                            {
                                Debug.Log($"[Prefabs] chest_wooden_01 collisionOffset {prefab.collisionOffset}");
                            }
                        }
                    }
                }
            }

            return result;
        }

        public static Dictionary<string, ItemDefinitionData> LoadItemDefinitions()
        {
            var result = new Dictionary<string, ItemDefinitionData>(StringComparer.OrdinalIgnoreCase);
            var json = LoadJsonFromResources("Prefabs/Objects/items", "items.json", ItemCandidatePaths);
            if (string.IsNullOrWhiteSpace(json))
            {
                return result;
            }

            var root = MiniJson.Deserialize(json) as Dictionary<string, object>;
            if (root == null || !root.TryGetValue("items", out var itemsObj))
            {
                return result;
            }

            if (itemsObj is List<object> list)
            {
                foreach (var entry in list)
                {
                    if (entry is Dictionary<string, object> itemDict)
                    {
                        var definition = new ItemDefinitionData
                        {
                            id = GetString(itemDict, "id"),
                            name = GetString(itemDict, "name"),
                            description = GetString(itemDict, "description"),
                            type = GetString(itemDict, "type"),
                            value = GetInt(itemDict, "value", 0)
                        };
                        if (!string.IsNullOrWhiteSpace(definition.id))
                        {
                            result[definition.id] = definition;
                        }
                    }
                }
            }

            return result;
        }

        public static Dictionary<string, CompanionDefinitionData> LoadCompanionDefinitions()
        {
            var result = new Dictionary<string, CompanionDefinitionData>(StringComparer.OrdinalIgnoreCase);
            var json = LoadJsonFromResources("Prefabs/Data/companions", "companions.json", CompanionCandidatePaths);
            if (string.IsNullOrWhiteSpace(json))
            {
                return result;
            }

            var root = MiniJson.Deserialize(json) as Dictionary<string, object>;
            if (root == null || !root.TryGetValue("animals", out var animalsObj))
            {
                return result;
            }

            if (animalsObj is List<object> list)
            {
                foreach (var entry in list)
                {
                    if (entry is Dictionary<string, object> companionDict)
                    {
                        var prefab = ParsePrefab(companionDict);
                        if (prefab == null || string.IsNullOrWhiteSpace(prefab.id))
                        {
                            continue;
                        }

                        prefab.type = "companion";
                        var definition = new CompanionDefinitionData
                        {
                            id = prefab.id,
                            name = prefab.name,
                            description = prefab.description,
                            requiredBefriendingItem = GetString(companionDict, "requiredBefriendingItem"),
                            level = GetInt(companionDict, "level", 1),
                            prefab = prefab
                        };
                        result[definition.id] = definition;
                    }
                }
            }

            return result;
        }

        public static Dictionary<string, EnemyDefinitionData> LoadEnemyDefinitions()
        {
            var result = new Dictionary<string, EnemyDefinitionData>(StringComparer.OrdinalIgnoreCase);
            var json = LoadJsonFromResources("Prefabs/Data/enemies", "enemies.json", EnemyCandidatePaths);
            if (string.IsNullOrWhiteSpace(json))
            {
                return result;
            }

            var root = MiniJson.Deserialize(json) as Dictionary<string, object>;
            if (root == null || !root.TryGetValue("enemies", out var enemiesObj))
            {
                return result;
            }

            if (enemiesObj is List<object> list)
            {
                foreach (var entry in list)
                {
                    if (entry is Dictionary<string, object> enemyDict)
                    {
                        var prefab = ParsePrefab(enemyDict);
                        if (prefab == null || string.IsNullOrWhiteSpace(prefab.id))
                        {
                            continue;
                        }

                        prefab.type = "enemy";
                        var definition = new EnemyDefinitionData
                        {
                            id = prefab.id,
                            name = prefab.name,
                            description = prefab.description,
                            level = GetInt(enemyDict, "level", 1),
                            hitPoints = GetInt(enemyDict, "hitPoints", 10),
                            attackPoints = GetInt(enemyDict, "attackPoints", 3),
                            defensePoints = GetInt(enemyDict, "defensePoints", 0),
                            speed = GetInt(enemyDict, "speed", 0),
                            prefab = prefab
                        };
                        result[definition.id] = definition;
                    }
                }
            }

            return result;
        }

        private static string LoadJson(string prefabId)
        {
            return LoadJsonFromResources($"Prefabs/Maps/{prefabId}", $"{prefabId}.json", CandidatePaths);
        }

        private static string LoadJsonFromResources(string resourcePath, string fileName, string[] candidates)
        {
            if (Application.isEditor && !string.IsNullOrWhiteSpace(fileName) && candidates != null)
            {
                foreach (var candidate in candidates)
                {
                    var path = Path.Combine(Application.dataPath, candidate, fileName);
                    if (File.Exists(path))
                    {
                        Debug.Log($"[Prefabs] Loaded json from file: {path}");
                        return File.ReadAllText(path);
                    }
                }
            }

            var resource = Resources.Load<TextAsset>(resourcePath);
            if (resource != null)
            {
                Debug.Log($"[Prefabs] Loaded json from Resources: {resourcePath}");
                return resource.text;
            }

            if (string.IsNullOrWhiteSpace(fileName) || candidates == null)
            {
                return null;
            }

            foreach (var candidate in candidates)
            {
                var path = Path.Combine(Application.dataPath, candidate, fileName);
                if (File.Exists(path))
                {
                    return File.ReadAllText(path);
                }
            }

            return null;
        }

        private static string GetString(Dictionary<string, object> dict, string key)
        {
            return dict.TryGetValue(key, out var value) ? value as string : null;
        }

        private static int GetInt(Dictionary<string, object> dict, string key, int fallback)
        {
            if (!dict.TryGetValue(key, out var value) || value == null)
            {
                return fallback;
            }

            return value switch
            {
                int intValue => intValue,
                long longValue => (int)longValue,
                float floatValue => Mathf.RoundToInt(floatValue),
                double doubleValue => Mathf.RoundToInt((float)doubleValue),
                _ => fallback
            };
        }

        private static float GetFloat(Dictionary<string, object> dict, string key, float fallback)
        {
            if (!dict.TryGetValue(key, out var value) || value == null)
            {
                return fallback;
            }

            return value switch
            {
                float floatValue => floatValue,
                double doubleValue => (float)doubleValue,
                int intValue => intValue,
                long longValue => longValue,
                _ => fallback
            };
        }

        private static List<string> GetStringList(Dictionary<string, object> dict, string key)
        {
            var result = new List<string>();
            if (!dict.TryGetValue(key, out var value) || value == null)
            {
                return result;
            }

            if (value is List<object> list)
            {
                foreach (var item in list)
                {
                    if (item is string str)
                    {
                        result.Add(str);
                    }
                }
            }

            return result;
        }

        private static List<string> GetStringListFlexible(Dictionary<string, object> dict, string key)
        {
            var result = new List<string>();
            if (!dict.TryGetValue(key, out var value) || value == null)
            {
                return result;
            }

            if (value is string single)
            {
                result.Add(single);
                return result;
            }

            if (value is List<object> list)
            {
                foreach (var item in list)
                {
                    if (item is string str)
                    {
                        result.Add(str);
                    }
                    else if (item is Dictionary<string, object> dictItem)
                    {
                        if (TryGetTileToken(dictItem, out var tileId))
                        {
                            result.Add(tileId);
                        }
                    }
                }
            }

            return result;
        }

        private static bool TryGetTileToken(Dictionary<string, object> dictItem, out string tileId)
        {
            tileId = null;
            if (dictItem == null)
            {
                return false;
            }

            if (dictItem.TryGetValue("tile_id", out var tileValue) && tileValue is string tileIdValue)
            {
                tileId = tileIdValue;
                return true;
            }

            if (dictItem.TryGetValue("tileId", out var tileIdCamel) && tileIdCamel is string tileIdCamelValue)
            {
                tileId = tileIdCamelValue;
                return true;
            }

            if (dictItem.TryGetValue("tileclass", out var tileClass) && tileClass is string tileClassValue)
            {
                tileId = tileClassValue;
                return true;
            }

            if (dictItem.TryGetValue("tileClass", out var tileClassCamel) && tileClassCamel is string tileClassCamelValue)
            {
                tileId = tileClassCamelValue;
                return true;
            }

            return false;
        }

        private static List<PrefabChestData> GetChestList(Dictionary<string, object> entities)
        {
            var result = new List<PrefabChestData>();
            if (!entities.TryGetValue("chests", out var value) || value == null)
            {
                return result;
            }

            if (value is List<object> list)
            {
                foreach (var entry in list)
                {
                    if (entry is Dictionary<string, object> chestDict)
                    {
                        var chest = new PrefabChestData
                        {
                            chestId = GetString(chestDict, "chestId"),
                            count = GetInt(chestDict, "count", 0),
                            blockedTerrainTypes = GetStringList(chestDict, "blockedTerrainTypes")
                        };
                        result.Add(chest);
                    }
                }
            }

            return result;
        }

        private static PrefabDefinition ParsePrefab(Dictionary<string, object> prefabDict)
        {
            var prefab = new PrefabDefinition
            {
                id = GetString(prefabDict, "id"),
                name = GetString(prefabDict, "name"),
                type = GetString(prefabDict, "type"),
                description = GetString(prefabDict, "description"),
                zPosition = GetFloat(prefabDict, "zPosition", 0f)
            };

            if (prefabDict.TryGetValue("collision", out var collisionObj))
            {
                if (collisionObj is Dictionary<string, object> collisionDict)
                {
                    prefab.collision = ParseCollision(collisionDict);
                }
            }

            if (prefabDict.TryGetValue("collisionOffset", out var offsetObj))
            {
                if (offsetObj is Dictionary<string, object> offsetDict)
                {
                    prefab.collisionOffset = new Vector2(
                        GetFloat(offsetDict, "x", 0f),
                        GetFloat(offsetDict, "y", 0f));
                }
            }

            if (prefabDict.TryGetValue("parts", out var partsObj) && partsObj is List<object> parts)
            {
                foreach (var partObj in parts)
                {
                    if (partObj is Dictionary<string, object> partDict)
                    {
                        prefab.parts.Add(ParsePrefabPart(partDict));
                    }
                }
            }

            if (prefabDict.TryGetValue("lootTable", out var lootObj) && lootObj is List<object> lootRows)
            {
                foreach (var rowObj in lootRows)
                {
                    if (rowObj is Dictionary<string, object> lootDict)
                    {
                        var entry = new PrefabLootEntry
                        {
                            itemId = GetString(lootDict, "itemId"),
                            dropRate = GetFloat(lootDict, "dropRate", 0f),
                            minQuantity = GetInt(lootDict, "minQuantity", 1),
                            maxQuantity = GetInt(lootDict, "maxQuantity", 1)
                        };
                        if (!string.IsNullOrWhiteSpace(entry.itemId))
                        {
                            prefab.lootTable.Add(entry);
                        }
                    }
                }
            }

            if (prefabDict.TryGetValue("fixedItems", out var fixedObj) && fixedObj is List<object> fixedRows)
            {
                foreach (var rowObj in fixedRows)
                {
                    if (rowObj is Dictionary<string, object> fixedDict)
                    {
                        var entry = new PrefabFixedItem
                        {
                            itemId = GetString(fixedDict, "itemId"),
                            quantity = GetInt(fixedDict, "quantity", 1)
                        };
                        if (!string.IsNullOrWhiteSpace(entry.itemId))
                        {
                            prefab.fixedItems.Add(entry);
                        }
                    }
                }
            }

            if (prefabDict.TryGetValue("randomItems", out var randomObj) && randomObj is Dictionary<string, object> randomDict)
            {
                prefab.randomItems = new PrefabRandomItems
                {
                    count = GetString(randomDict, "count"),
                    categories = GetStringList(randomDict, "categories"),
                    minValue = GetInt(randomDict, "minValue", 0),
                    maxValue = GetInt(randomDict, "maxValue", 0)
                };
            }

            if (prefabDict.TryGetValue("lockLevel", out var lockObj) && lockObj != null)
            {
                if (TryGetIntValue(lockObj, out var lockLevel))
                {
                    prefab.lockLevel = lockLevel;
                }
            }

            prefab.requiredKey = GetString(prefabDict, "requiredKey");

            return prefab;
        }

        private static PrefabPart ParsePrefabPart(Dictionary<string, object> partDict)
        {
            var part = new PrefabPart
            {
                layer = GetString(partDict, "layer"),
                assetName = GetString(partDict, "assetName"),
                tileGrid = new List<List<string>>()
            };

            if (partDict.TryGetValue("tileGrid", out var gridObj) && gridObj is List<object> gridRows)
            {
                foreach (var rowObj in gridRows)
                {
                    var row = new List<string>();
                    if (rowObj is List<object> rowItems)
                    {
                        foreach (var item in rowItems)
                        {
                            row.Add(item as string);
                        }
                    }
                    part.tileGrid.Add(row);
                }
            }

            return part;
        }

        private static PrefabCollisionData ParseCollision(Dictionary<string, object> collisionDict)
        {
            var collision = new PrefabCollisionData
            {
                type = GetString(collisionDict, "type")
            };

            if (collisionDict.TryGetValue("size", out var sizeObj) && sizeObj is Dictionary<string, object> sizeDict)
            {
                collision.size = new Vector2(
                    GetFloat(sizeDict, "width", 0f),
                    GetFloat(sizeDict, "height", 0f));
            }

            return collision;
        }

        private static bool TryGetIntValue(object value, out int result)
        {
            switch (value)
            {
                case int intValue:
                    result = intValue;
                    return true;
                case long longValue:
                    result = (int)longValue;
                    return true;
                case float floatValue:
                    result = Mathf.RoundToInt(floatValue);
                    return true;
                case double doubleValue:
                    result = Mathf.RoundToInt((float)doubleValue);
                    return true;
                case string stringValue when int.TryParse(stringValue, out var parsed):
                    result = parsed;
                    return true;
                default:
                    result = 0;
                    return false;
            }
        }
    }

    public class PrefabWorldData
    {
        public string name;
        public string description;
        public string tmxFile;
        public int width;
        public int height;
        public int seed;
        public TerrainThresholds thresholds;
        public PrefabGroundTiles groundTiles;
        public PrefabEntitiesData entities;
        public PrefabEnemySpawnData enemies;
        public PrefabCompanionSpawnData companions;
        public PrefabWaterFeaturesData waterFeatures;
        public PrefabEnterConfig enterConfig;
        public List<PrefabDefinition> prefabs;
    }

    public class PrefabGroundTiles
    {
        public List<string> water = new List<string>();
        public List<string> grass = new List<string>();
        public List<string> dirt = new List<string>();
        public List<string> stone = new List<string>();
    }

    public class PrefabEntitiesData
    {
        public float treeDensity = 0.002f;
        public float rockDensity = 0.005f;
        public List<string> treeBlockedTerrainTypes = new List<string>();
        public List<string> rockBlockedTerrainTypes = new List<string>();
        public List<string> treePrefabs = new List<string>();
        public List<string> rockPrefabs = new List<string>();
        public List<PrefabChestData> chests = new List<PrefabChestData>();
    }

    public class PrefabEnemySpawnData
    {
        public float spawnRate;
        public List<string> types = new List<string>();
        public int minLevel = 1;
        public int maxLevel = 1;
        public List<string> blockedTerrainTypes = new List<string>();
    }

    public class PrefabCompanionSpawnData
    {
        public float spawnRate;
        public List<string> types = new List<string>();
        public float friendlyChance = 1f;
        public List<string> blockedTerrainTypes = new List<string>();
    }

    public class PrefabWaterFeaturesData
    {
        public string type;
        public string density;
    }

    public class PrefabChestData
    {
        public string chestId;
        public int count;
        public List<string> blockedTerrainTypes = new List<string>();
    }

    public class PrefabEnterConfig
    {
        public int x;
        public int y;
    }

    public class PrefabDefinition
    {
        public string id;
        public string name;
        public string type;
        public string description;
        public List<PrefabPart> parts = new List<PrefabPart>();
        public PrefabCollisionData collision;
        public Vector2 collisionOffset;
        public float zPosition;
        public List<PrefabLootEntry> lootTable = new List<PrefabLootEntry>();
        public List<PrefabFixedItem> fixedItems = new List<PrefabFixedItem>();
        public PrefabRandomItems randomItems;
        public int? lockLevel;
        public string requiredKey;
    }

    public class PrefabLootEntry
    {
        public string itemId;
        public float dropRate;
        public int minQuantity;
        public int maxQuantity;
    }

    public class PrefabFixedItem
    {
        public string itemId;
        public int quantity;
    }

    public class PrefabRandomItems
    {
        public string count;
        public List<string> categories = new List<string>();
        public int minValue;
        public int maxValue;
    }

    public class ItemDefinitionData
    {
        public string id;
        public string name;
        public string description;
        public string type;
        public int value;
    }

    public class CompanionDefinitionData
    {
        public string id;
        public string name;
        public string description;
        public string requiredBefriendingItem;
        public int level;
        public PrefabDefinition prefab;
    }

    public class EnemyDefinitionData
    {
        public string id;
        public string name;
        public string description;
        public int level;
        public int hitPoints;
        public int attackPoints;
        public int defensePoints;
        public int speed;
        public PrefabDefinition prefab;
    }

    public class PrefabPart
    {
        public string layer;
        public List<List<string>> tileGrid = new List<List<string>>();
        public string assetName;
    }

    public class PrefabCollisionData
    {
        public string type;
        public Vector2 size;
    }
}
