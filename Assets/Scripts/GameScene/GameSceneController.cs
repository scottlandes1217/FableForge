using System;
using System.Collections.Generic;
using System.IO;
using FableForge.Systems;
using FableForge.UI;
using UnityEngine;

public class GameSceneController : MonoBehaviour
{
    public static GameSceneController Instance { get; private set; }
    public bool IsInBattle => isInBattle;

    private const float TargetTilePixelSize = 32f;
    private const float DefaultTilePixelSize = 16f;
    [Tooltip("Vertical number of tiles visible; larger = more zoomed out. Used for both TMX and procedural maps.")]
    [SerializeField] private float targetTilesOnScreenY = 22f;
    private const float DoorTriggerCooldownSeconds = 0.35f;
    [SerializeField] private float playerColliderWidthFactor = 0.3f;
    [SerializeField] private float playerColliderHeightFactor = 0.25f;
    [SerializeField] private bool showPlayerColliderOutline = true;
    [SerializeField] private float playerColliderYOffset = 0.0f;
    [SerializeField] private bool showPrefabColliderOutlines = true;
    private float tiledMapTileScale = 1f;
    private bool isTiledMapActive;
    private readonly Dictionary<string, TiledTilesetData> proceduralTilesets = new Dictionary<string, TiledTilesetData>();
    private readonly TiledMapRenderer proceduralRenderer = new TiledMapRenderer();
    private readonly Dictionary<Vector2Int, TiledDoorInfo> tiledDoorTiles = new Dictionary<Vector2Int, TiledDoorInfo>();
    private readonly HashSet<Vector2Int> tiledCollisionTiles = new HashSet<Vector2Int>();
    private const int ProceduralBlockRadius = 1;
    private GameObject proceduralWorldRoot;
    private GameObject proceduralEntitiesRoot;
    private readonly Dictionary<Vector2Int, Transform> proceduralBlocks = new Dictionary<Vector2Int, Transform>();
    private readonly Dictionary<Vector2Int, Transform> proceduralEntityBlocks = new Dictionary<Vector2Int, Transform>();
    private Vector2Int? proceduralCenterBlock;
    private string currentTmxName;
    private string previousTmxName;
    private float doorTriggerCooldownUntil;
    private Vector2Int? lastDoorTile;
    private Transform playerTransform;
    private Vector3 playerBaseScale = Vector3.one;
    private int tiledCharacterSortingOrder = 120;
    private Vector3 tiledMapCenter = Vector3.zero;
    private Vector2Int? tiledSpawnTile;
    private BoxCollider2D playerCollider;
    private bool loggedColliderState;

    /// <summary>Base sorting order for the player so they draw in front of the map. Set when applying sort order; CharacterCustomizer uses this so it isn't overwritten every frame.</summary>
    public static int PlayerSortingBaseOrder { get; private set; }
    private float lastCollisionLogTime;
    private float nextColliderAuditTime;
    private Dictionary<string, PrefabDefinition> cachedChestPrefabs;
    private Dictionary<string, CompanionDefinitionData> cachedCompanionDefinitions;
    private Dictionary<string, EnemyDefinitionData> cachedEnemyDefinitions;
    private float nextCompanionRefreshTime;
    private float nextEnemyRefreshTime;
    private Transform companionFollowersRoot;
    private bool isInBattle;
    private readonly Dictionary<Transform, Vector3> battleOriginalPositions = new Dictionary<Transform, Vector3>();
    private readonly List<CompanionFollower> battleFollowers = new List<CompanionFollower>();
    private Coroutine proceduralRefreshRoutine;
    private readonly HashSet<string> loggedTileWarnings = new HashSet<string>();
    private static Material prefabColliderMaterial;
    private struct TileSpriteInstance
    {
        public Sprite sprite;
        public Vector2 localOffset;
        public float scale;
    }
    private struct TilesetAnchor
    {
        public int minCol;
        public int maxRow;
    }

    private void Start()
    {
        Debug.LogWarning("[Collision] GameSceneController.Start");
        EnsureSystems();
        InitializeWorld();
        var renderedTmx = false;
        var saveData = GameState.Instance != null ? GameState.Instance.CurrentSave : null;
        if (saveData != null && !saveData.useProceduralWorld && !string.IsNullOrWhiteSpace(saveData.currentMapFileName))
        {
            renderedTmx = LoadTiledMap(saveData.currentMapFileName, null, false, false);
        }

        if (!renderedTmx)
        {
            renderedTmx = TryRenderTiledMap();
        }
        if (!renderedTmx)
        {
            RenderWorldPreview();
            RenderEntityPreview();
        }
        SpawnPlayerFromSave();
    }

    private void Awake()
    {
        if (Instance != null && Instance != this)
        {
            Destroy(gameObject);
            return;
        }

        Instance = this;
    }

    private void Update()
    {
        UpdateSavePlayerSnapshot();
        if (isTiledMapActive)
        {
            CheckDoorTrigger();

            if (playerTransform != null && Time.time >= nextColliderAuditTime)
            {
                nextColliderAuditTime = Time.time + 2f;
                var rootCollider = playerTransform.GetComponent<BoxCollider2D>();
                if (rootCollider == null)
                {
                    EnsurePlayerCollider(playerTransform.gameObject);
                }
                else
                {
                    playerCollider = rootCollider;
                    AuditAndCleanupColliders(true);
                    RefreshPlayerColliderOutline();
                }
                LogColliderState();
            }
        }
        else
        {
            UpdateProceduralBlocks();
        }
    }

    private void EnsureSystems()
    {
        if (FindFirstObjectByType<GameState>() == null)
        {
            new GameObject("GameState").AddComponent<GameState>();
        }

        if (FindFirstObjectByType<WorldSystem>() == null)
        {
            new GameObject("WorldSystem").AddComponent<WorldSystem>();
        }

        if (FindFirstObjectByType<TileManager>() == null)
        {
            new GameObject("TileManager").AddComponent<TileManager>();
        }

        if (FindFirstObjectByType<DialogueSystem>() == null)
        {
            new GameObject("DialogueSystem").AddComponent<DialogueSystem>();
        }

        if (FindFirstObjectByType<CombatSystem>() == null)
        {
            new GameObject("CombatSystem").AddComponent<CombatSystem>();
        }

        if (FindFirstObjectByType<RuntimeGameUIBootstrap>() == null)
        {
            new GameObject("GameUIBootstrap").AddComponent<RuntimeGameUIBootstrap>();
        }
    }

    private void InitializeWorld()
    {
        var worldSystem = WorldSystem.Instance;
        if (worldSystem == null)
        {
            return;
        }

        var saveData = GameState.Instance != null ? GameState.Instance.CurrentSave : null;
        var prefabId = !string.IsNullOrWhiteSpace(saveData?.worldPrefabId) ? saveData.worldPrefabId : "prefabs_grassland";
        worldSystem.InitializeFromPrefab(prefabId, 64, 64);
    }

    private void RenderWorldPreview()
    {
        if (FindFirstObjectByType<WorldSystem>() == null)
        {
            return;
        }

        if (GameObject.Find("WorldPreview") != null)
        {
            return;
        }

        var worldSystem = WorldSystem.Instance;
        if (worldSystem == null || worldSystem.Tiles == null)
        {
            return;
        }

        EnsureWorldCamera(worldSystem.Config);
        proceduralWorldRoot = new GameObject("WorldPreview");
        proceduralBlocks.Clear();
        if (proceduralEntitiesRoot == null)
        {
            proceduralEntitiesRoot = new GameObject("WorldEntities");
        }
        proceduralEntityBlocks.Clear();

        var tileScale = GetProceduralTileScale();
        var width = Mathf.Max(1, worldSystem.Config.width);
        var height = Mathf.Max(1, worldSystem.Config.height);
        var blockWorldSizeX = width * tileScale;
        var blockWorldSizeY = height * tileScale;
        var enter = worldSystem.CurrentPrefabData?.enterConfig;
        var spawnX = enter != null ? enter.x : worldSystem.Config.width / 2;
        var spawnY = enter != null ? enter.y : worldSystem.Config.height / 2;
        var spawnWorldX = spawnX * tileScale;
        var spawnWorldY = spawnY * tileScale;
        var centerBlock = new Vector2Int(
            Mathf.FloorToInt(spawnWorldX / blockWorldSizeX),
            Mathf.FloorToInt(spawnWorldY / blockWorldSizeY));
        proceduralCenterBlock = centerBlock;

        if (proceduralRefreshRoutine != null)
        {
            StopCoroutine(proceduralRefreshRoutine);
            proceduralRefreshRoutine = null;
        }
        proceduralRefreshRoutine = StartCoroutine(RefreshProceduralBlocksOverFrames(centerBlock));
    }

    private string GetGroundTileSpec(PrefabGroundTiles groundTiles, int tileValue, int seed, int x, int y)
    {
        if (groundTiles == null)
        {
            return null;
        }

        var options = tileValue switch
        {
            0 => groundTiles.water,
            1 => groundTiles.grass,
            2 => groundTiles.dirt,
            _ => groundTiles.stone
        };

        if (options == null || options.Count == 0)
        {
            return null;
        }

        var index = GetDeterministicIndex(seed, x, y, options.Count);
        return options[index];
    }

    private bool TryCreateProceduralTileSprite(string spec, int seed, int x, int y, out Sprite sprite, out float tileScale)
    {
        sprite = null;
        tileScale = 1f;

        if (string.IsNullOrWhiteSpace(spec))
        {
            LogTileWarningOnce("empty-spec");
            return false;
        }

        var dashIndex = spec.IndexOf('-');
        if (dashIndex <= 0 || dashIndex >= spec.Length - 1)
        {
            LogTileWarningOnce($"invalid-spec:{spec}");
            return false;
        }

        var tilesetName = spec.Substring(0, dashIndex);
        if (tilesetName.Equals("exterior", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }
        var token = spec.Substring(dashIndex + 1);
        var tileset = GetProceduralTileset(tilesetName);
        if (tileset == null)
        {
            LogTileWarningOnce($"missing-tileset:{tilesetName}");
            return false;
        }

        int tileId;
        if (!int.TryParse(token, out tileId))
        {
            if (!tileset.typeToIds.TryGetValue(token, out var ids) || ids.Count == 0)
            {
                LogTileWarningOnce($"missing-tileclass:{tilesetName}:{token}");
                return false;
            }

            var index = GetDeterministicIndex(seed, x, y, ids.Count);
            tileId = ids[index];
        }

        tileScale = tileset.tileWidth > 0 ? TargetTilePixelSize / tileset.tileWidth : 1f;
        sprite = proceduralRenderer.CreateSpriteFromTileset(tileset, tileId, tileset.sourcePath, tileset.tileWidth);
        if (sprite == null)
        {
            LogTileWarningOnce($"sprite-null:{tilesetName}:{tileId}");
        }
        return sprite != null;
    }

    private bool TryCreateProceduralTileSpritesForPart(string spec, int seed, int x, int y, Dictionary<string, TilesetAnchor> tilesetAnchors, out List<TileSpriteInstance> sprites, out float tileScale)
    {
        sprites = null;
        tileScale = 1f;

        if (string.IsNullOrWhiteSpace(spec))
        {
            LogTileWarningOnce("empty-spec");
            return false;
        }

        var dashIndex = spec.IndexOf('-');
        if (dashIndex <= 0 || dashIndex >= spec.Length - 1)
        {
            LogTileWarningOnce($"invalid-spec:{spec}");
            return false;
        }

        var tilesetName = spec.Substring(0, dashIndex);
        if (tilesetName.Equals("exterior", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var token = spec.Substring(dashIndex + 1);
        var tileset = GetProceduralTileset(tilesetName);
        if (tileset == null)
        {
            LogTileWarningOnce($"missing-tileset:{tilesetName}");
            return false;
        }

        if (int.TryParse(token, out var explicitId))
        {
            return TryCreateSingleTileSprite(tileset, tilesetName, explicitId, out sprites, out tileScale);
        }

        if (!tileset.typeToIds.TryGetValue(token, out var ids) || ids.Count == 0)
        {
            LogTileWarningOnce($"missing-tileclass:{tilesetName}:{token}");
            return false;
        }

        if (ids.Count == 1)
        {
            return TryCreateSingleTileSprite(tileset, tilesetName, ids[0], out sprites, out tileScale);
        }

        if (tileset.columns <= 0)
        {
            return false;
        }

        tileScale = tileset.tileWidth > 0 ? TargetTilePixelSize / tileset.tileWidth : 1f;
        if (!TryGetTilesetAnchor(tilesetAnchors, tilesetName, tileset, ids, out var anchor))
        {
            return false;
        }

        sprites = new List<TileSpriteInstance>(ids.Count);
        for (var i = 0; i < ids.Count; i++)
        {
            var id = ids[i];
            var sprite = proceduralRenderer.CreateSpriteFromTileset(tileset, id, tileset.sourcePath, tileset.tileWidth);
            if (sprite == null)
            {
                LogTileWarningOnce($"sprite-null:{tilesetName}:{id}");
                continue;
            }

            var col = id % tileset.columns;
            var row = id / tileset.columns;
            var localOffset = new Vector2((col - anchor.minCol) * tileScale, (anchor.maxRow - row) * tileScale);
            sprites.Add(new TileSpriteInstance
            {
                sprite = sprite,
                localOffset = localOffset,
                scale = tileScale
            });
        }

        return sprites.Count > 0;
    }

    private bool TryCreateSingleTileSprite(TiledTilesetData tileset, string tilesetName, int tileId, out List<TileSpriteInstance> sprites, out float tileScale)
    {
        sprites = null;
        tileScale = tileset.tileWidth > 0 ? TargetTilePixelSize / tileset.tileWidth : 1f;
        var sprite = proceduralRenderer.CreateSpriteFromTileset(tileset, tileId, tileset.sourcePath, tileset.tileWidth);
        if (sprite == null)
        {
            LogTileWarningOnce($"sprite-null:{tilesetName}:{tileId}");
            return false;
        }

        sprites = new List<TileSpriteInstance>(1)
        {
            new TileSpriteInstance
            {
                sprite = sprite,
                localOffset = Vector2.zero,
                scale = tileScale
            }
        };
        return true;
    }

    private bool TryGetTilesetAnchor(Dictionary<string, TilesetAnchor> tilesetAnchors, string tilesetName, TiledTilesetData tileset, List<int> ids, out TilesetAnchor anchor)
    {
        if (tilesetAnchors != null && tilesetAnchors.TryGetValue(tilesetName, out anchor))
        {
            return true;
        }

        if (tileset.columns <= 0)
        {
            anchor = default;
            return false;
        }

        var minCol = int.MaxValue;
        var maxRow = int.MinValue;
        for (var i = 0; i < ids.Count; i++)
        {
            var id = ids[i];
            var col = id % tileset.columns;
            var row = id / tileset.columns;
            minCol = Mathf.Min(minCol, col);
            maxRow = Mathf.Max(maxRow, row);
        }

        anchor = new TilesetAnchor
        {
            minCol = minCol,
            maxRow = maxRow
        };
        return true;
    }

    private Dictionary<string, TilesetAnchor> BuildPrefabTilesetAnchors(PrefabDefinition prefab)
    {
        var anchors = new Dictionary<string, TilesetAnchor>(StringComparer.OrdinalIgnoreCase);
        if (prefab?.parts == null)
        {
            return anchors;
        }

        for (var partIndex = 0; partIndex < prefab.parts.Count; partIndex++)
        {
            var part = prefab.parts[partIndex];
            if (part?.tileGrid == null)
            {
                continue;
            }

            for (var row = 0; row < part.tileGrid.Count; row++)
            {
                var rowData = part.tileGrid[row];
                if (rowData == null)
                {
                    continue;
                }

                for (var col = 0; col < rowData.Count; col++)
                {
                    var spec = rowData[col];
                    if (string.IsNullOrWhiteSpace(spec))
                    {
                        continue;
                    }

                    if (!TryGetTilesetToken(spec, out var tilesetName, out var token))
                    {
                        continue;
                    }

                    var tileset = GetProceduralTileset(tilesetName);
                    if (tileset == null || tileset.columns <= 0)
                    {
                        continue;
                    }

                    if (!anchors.TryGetValue(tilesetName, out var anchor))
                    {
                        anchor = new TilesetAnchor
                        {
                            minCol = int.MaxValue,
                            maxRow = int.MinValue
                        };
                    }

                    if (int.TryParse(token, out var tileId))
                    {
                        UpdateAnchorFromTile(tileset, tileId, ref anchor);
                    }
                    else if (tileset.typeToIds.TryGetValue(token, out var ids))
                    {
                        for (var idIndex = 0; idIndex < ids.Count; idIndex++)
                        {
                            UpdateAnchorFromTile(tileset, ids[idIndex], ref anchor);
                        }
                    }

                    anchors[tilesetName] = anchor;
                }
            }
        }

        return anchors;
    }

    private bool TryGetTilesetToken(string spec, out string tilesetName, out string token)
    {
        tilesetName = null;
        token = null;
        if (string.IsNullOrWhiteSpace(spec))
        {
            return false;
        }

        var dashIndex = spec.IndexOf('-');
        if (dashIndex <= 0 || dashIndex >= spec.Length - 1)
        {
            return false;
        }

        tilesetName = spec.Substring(0, dashIndex);
        if (tilesetName.Equals("exterior", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        token = spec.Substring(dashIndex + 1);
        return true;
    }

    private void UpdateAnchorFromTile(TiledTilesetData tileset, int tileId, ref TilesetAnchor anchor)
    {
        var col = tileId % tileset.columns;
        var row = tileId / tileset.columns;
        anchor.minCol = Mathf.Min(anchor.minCol, col);
        anchor.maxRow = Mathf.Max(anchor.maxRow, row);
    }

    private void UpdateTileBounds(TiledTilesetData tileset, int tileId, ref int minCol, ref int maxCol, ref int minRow, ref int maxRow)
    {
        var col = tileId % tileset.columns;
        var row = tileId / tileset.columns;
        minCol = Mathf.Min(minCol, col);
        maxCol = Mathf.Max(maxCol, col);
        minRow = Mathf.Min(minRow, row);
        maxRow = Mathf.Max(maxRow, row);
    }

    private TiledTilesetData GetProceduralTileset(string tilesetName)
    {
        if (proceduralTilesets.TryGetValue(tilesetName, out var cached))
        {
            return cached;
        }

        var tsxPath = ResolveProceduralTilesetPath(tilesetName);
        if (string.IsNullOrWhiteSpace(tsxPath))
        {
            LogTileWarningOnce($"tsx-not-found:{tilesetName}");
            return null;
        }

        var tileset = TiledMapLoader.LoadTilesetFromFile(tsxPath);
        if (tileset != null)
        {
            proceduralTilesets[tilesetName] = tileset;
        }
        else
        {
            LogTileWarningOnce($"tsx-load-failed:{tilesetName}:{tsxPath}");
        }

        return tileset;
    }

    private void LogTileWarningOnce(string message)
    {
        if (string.IsNullOrWhiteSpace(message) || loggedTileWarnings.Contains(message))
        {
            return;
        }

        loggedTileWarnings.Add(message);
        Debug.LogWarning($"[Tiles] {message}");
    }

    private string ResolveProceduralTilesetPath(string tilesetName)
    {
        if (string.IsNullOrWhiteSpace(tilesetName))
        {
            return null;
        }

        var fileName = $"{tilesetName}.tsx";
        var candidates = new[]
        {
            Path.Combine(Application.dataPath, "Resources/Maps/TSX", fileName),
            Path.Combine(Application.dataPath, "Resources/Prefabs/Maps/TSX", fileName),
            Path.Combine(Application.dataPath, "XcodeImport/FableForge Shared/Prefabs/Maps/TSX", fileName),
            Path.Combine(Application.dataPath, "XcodeImport/Prefabs/Maps/TSX", fileName)
        };

        for (var i = 0; i < candidates.Length; i++)
        {
            var candidate = candidates[i];
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return null;
    }

    private static int GetDeterministicIndex(int seed, int x, int y, int count)
    {
        if (count <= 0)
        {
            return 0;
        }

        unchecked
        {
            var hash = seed;
            hash = (hash * 397) ^ x;
            hash = (hash * 397) ^ y;
            if (hash == int.MinValue)
            {
                hash = 0;
            }
            var index = Mathf.Abs(hash) % count;
            return index;
        }
    }

    private void UpdateProceduralBlocks()
    {
        if (proceduralWorldRoot == null || playerTransform == null)
        {
            return;
        }

        var worldSystem = WorldSystem.Instance;
        if (worldSystem == null)
        {
            return;
        }

        var tileScale = GetProceduralTileScale();
        if (tileScale <= 0f)
        {
            tileScale = 1f;
        }

        var width = Mathf.Max(1, worldSystem.Config.width);
        var height = Mathf.Max(1, worldSystem.Config.height);
        var blockWorldSizeX = width * tileScale;
        var blockWorldSizeY = height * tileScale;
        if (blockWorldSizeX <= 0f || blockWorldSizeY <= 0f)
        {
            return;
        }

        var position = playerTransform.position;
        var center = new Vector2Int(
            Mathf.FloorToInt(position.x / blockWorldSizeX),
            Mathf.FloorToInt(position.y / blockWorldSizeY));

        if (!proceduralCenterBlock.HasValue || proceduralCenterBlock.Value != center)
        {
            proceduralCenterBlock = center;
            if (proceduralRefreshRoutine != null)
            {
                StopCoroutine(proceduralRefreshRoutine);
                proceduralRefreshRoutine = null;
            }
            proceduralRefreshRoutine = StartCoroutine(RefreshProceduralBlocksOverFrames(center));
        }
    }

    private System.Collections.IEnumerator RefreshProceduralBlocksOverFrames(Vector2Int centerBlock)
    {
        yield return null;
        yield return new WaitForEndOfFrame();

        var worldSystem = WorldSystem.Instance;
        if (worldSystem == null)
        {
            proceduralRefreshRoutine = null;
            yield break;
        }

        var frameStart = Time.realtimeSinceStartup;

        var tileScale = GetProceduralTileScale();
        if (tileScale <= 0f)
        {
            tileScale = 1f;
        }

        var width = Mathf.Max(1, worldSystem.Config.width);
        var height = Mathf.Max(1, worldSystem.Config.height);
        var blockWorldSizeX = width * tileScale;
        var blockWorldSizeY = height * tileScale;

        var desiredCoords = new HashSet<Vector2Int>();
        for (var offsetX = -ProceduralBlockRadius; offsetX <= ProceduralBlockRadius; offsetX++)
        {
            for (var offsetY = -ProceduralBlockRadius; offsetY <= ProceduralBlockRadius; offsetY++)
            {
                desiredCoords.Add(new Vector2Int(centerBlock.x + offsetX, centerBlock.y + offsetY));
            }
        }

        var orderedTerrainCoords = new List<Vector2Int>();
        orderedTerrainCoords.Add(centerBlock);
        foreach (var c in desiredCoords)
        {
            if (c != centerBlock)
            {
                orderedTerrainCoords.Add(c);
            }
        }

        var terrainToRemove = new List<Vector2Int>();
        foreach (var coord in proceduralBlocks.Keys)
        {
            if (!desiredCoords.Contains(coord))
            {
                terrainToRemove.Add(coord);
            }
        }

        for (var i = 0; i < terrainToRemove.Count; i++)
        {
            if (Time.realtimeSinceStartup - frameStart >= ProceduralLoadMaxSecondsPerFrame)
            {
                yield return null;
                frameStart = Time.realtimeSinceStartup;
            }

            var coord = terrainToRemove[i];
            if (proceduralBlocks.TryGetValue(coord, out var block))
            {
                proceduralBlocks.Remove(coord);
                if (block != null && block.gameObject != null)
                {
                    yield return DestroyBlockChildrenOverFrames(block.gameObject, 120);
                    Destroy(block.gameObject);
                }
            }
        }

        var terrainHeight = worldSystem.Tiles != null ? worldSystem.Tiles.GetLength(1) : 64;

        foreach (var coord in orderedTerrainCoords)
        {
            if (proceduralBlocks.ContainsKey(coord))
            {
                continue;
            }

            if (Time.realtimeSinceStartup - frameStart >= ProceduralLoadMaxSecondsPerFrame)
            {
                yield return null;
                frameStart = Time.realtimeSinceStartup;
            }

            var root = CreateProceduralBlockRootOnly(coord, proceduralWorldRoot.transform);
            if (root != null)
            {
                proceduralBlocks[coord] = root;
                for (var yStart = 0; yStart < terrainHeight; yStart += TerrainRowsPerFrame)
                {
                    if (Time.realtimeSinceStartup - frameStart >= ProceduralLoadMaxSecondsPerFrame)
                    {
                        yield return null;
                        frameStart = Time.realtimeSinceStartup;
                    }
                    var rowCount = Mathf.Min(TerrainRowsPerFrame, terrainHeight - yStart);
                    CreateProceduralBlockTilesForRowRange(root, coord, worldSystem, yStart, rowCount);
                }
            }
        }

        foreach (var kvp in proceduralBlocks)
        {
            SetBlockTransformPosition(kvp.Value, kvp.Key, blockWorldSizeX, blockWorldSizeY, "WorldBlock");
        }

        yield return null;

        var data = worldSystem.CurrentPrefabData;
        if (data == null || data.entities == null)
        {
            proceduralRefreshRoutine = null;
            yield break;
        }

        var prefabLookup = BuildPrefabLookup(data);
        var treePrefabs = ResolveEntityPrefabs(data, data.entities.treePrefabs, "tree");
        var rockPrefabs = ResolveEntityPrefabs(data, data.entities.rockPrefabs, "rock");

        var entityToRemove = new List<Vector2Int>();
        foreach (var coord in proceduralEntityBlocks.Keys)
        {
            if (!desiredCoords.Contains(coord))
            {
                entityToRemove.Add(coord);
            }
        }

        for (var i = 0; i < entityToRemove.Count; i++)
        {
            if (Time.realtimeSinceStartup - frameStart >= ProceduralLoadMaxSecondsPerFrame)
            {
                yield return null;
                frameStart = Time.realtimeSinceStartup;
            }

            var coord = entityToRemove[i];
            if (proceduralEntityBlocks.TryGetValue(coord, out var blockRoot))
            {
                proceduralEntityBlocks.Remove(coord);
                if (blockRoot != null && blockRoot.gameObject != null)
                {
                    yield return DestroyBlockChildrenOverFrames(blockRoot.gameObject, 80);
                    Destroy(blockRoot.gameObject);
                }
            }
        }

        var orderedEntityCoords = new List<Vector2Int>();
        orderedEntityCoords.Add(centerBlock);
        foreach (var c in desiredCoords)
        {
            if (c != centerBlock)
            {
                orderedEntityCoords.Add(c);
            }
        }

        foreach (var coord in orderedEntityCoords)
        {
            if (proceduralEntityBlocks.ContainsKey(coord))
            {
                continue;
            }

            if (Time.realtimeSinceStartup - frameStart >= ProceduralLoadMaxSecondsPerFrame)
            {
                yield return null;
                frameStart = Time.realtimeSinceStartup;
            }

            var blockRootObj = new GameObject($"EntitiesBlock_{coord.x}_{coord.y}");
            blockRootObj.transform.SetParent(proceduralEntitiesRoot.transform, false);
            var blockRoot = blockRootObj.transform;
            proceduralEntityBlocks[coord] = blockRoot;

            var entityTileScale = GetProceduralTileScale();
            var entityRandom = GetEntityBlockRandom(coord, data);
            var entityLowOrder = ResolvePlayerSortingOrder() - 1;

            RebuildProceduralEntityBlockTrees(blockRoot, coord, worldSystem, data, prefabLookup, treePrefabs, entityTileScale, entityRandom, entityLowOrder);
            if (Time.realtimeSinceStartup - frameStart >= ProceduralLoadMaxSecondsPerFrame)
            {
                yield return null;
                frameStart = Time.realtimeSinceStartup;
            }
            RebuildProceduralEntityBlockRocks(blockRoot, coord, worldSystem, data, prefabLookup, rockPrefabs, entityTileScale, entityRandom, entityLowOrder);
            if (Time.realtimeSinceStartup - frameStart >= ProceduralLoadMaxSecondsPerFrame)
            {
                yield return null;
                frameStart = Time.realtimeSinceStartup;
            }
            RebuildProceduralEntityBlockChests(blockRoot, coord, worldSystem, data, entityTileScale, entityRandom, entityLowOrder);
            if (Time.realtimeSinceStartup - frameStart >= ProceduralLoadMaxSecondsPerFrame)
            {
                yield return null;
                frameStart = Time.realtimeSinceStartup;
            }
            RebuildProceduralEntityBlockCompanions(blockRoot, coord, worldSystem, data, entityTileScale, entityRandom, entityLowOrder);
            if (Time.realtimeSinceStartup - frameStart >= ProceduralLoadMaxSecondsPerFrame)
            {
                yield return null;
                frameStart = Time.realtimeSinceStartup;
            }
            RebuildProceduralEntityBlockEnemies(blockRoot, coord, worldSystem, data, entityTileScale, entityRandom, entityLowOrder);
        }

        foreach (var kvp in proceduralEntityBlocks)
        {
            SetBlockTransformPosition(kvp.Value, kvp.Key, blockWorldSizeX, blockWorldSizeY, "EntitiesBlock");
        }

        proceduralRefreshRoutine = null;
    }

    private void RefreshProceduralBlocks(Vector2Int centerBlock)
    {
        var worldSystem = WorldSystem.Instance;
        if (worldSystem == null)
        {
            return;
        }

        var tileScale = GetProceduralTileScale();
        if (tileScale <= 0f)
        {
            tileScale = 1f;
        }

        var width = Mathf.Max(1, worldSystem.Config.width);
        var height = Mathf.Max(1, worldSystem.Config.height);
        var blockWorldSizeX = width * tileScale;
        var blockWorldSizeY = height * tileScale;

        var desiredCoords = new HashSet<Vector2Int>();
        for (var offsetX = -ProceduralBlockRadius; offsetX <= ProceduralBlockRadius; offsetX++)
        {
            for (var offsetY = -ProceduralBlockRadius; offsetY <= ProceduralBlockRadius; offsetY++)
            {
                desiredCoords.Add(new Vector2Int(centerBlock.x + offsetX, centerBlock.y + offsetY));
            }
        }

        EnsureProceduralBlocks(desiredCoords, blockWorldSizeX, blockWorldSizeY, worldSystem);
        EnsureProceduralEntityBlocks(desiredCoords, blockWorldSizeX, blockWorldSizeY, worldSystem);
    }

    private void EnsureProceduralBlocks(HashSet<Vector2Int> desiredCoords, float blockWorldSizeX, float blockWorldSizeY, WorldSystem worldSystem)
    {
        if (proceduralWorldRoot == null)
        {
            return;
        }

        var toReuse = new List<Vector2Int>();
        foreach (var coord in proceduralBlocks.Keys)
        {
            if (!desiredCoords.Contains(coord))
            {
                toReuse.Add(coord);
            }
        }

        var reuseIndex = 0;
        foreach (var coord in desiredCoords)
        {
            if (proceduralBlocks.ContainsKey(coord))
            {
                continue;
            }

            if (reuseIndex >= toReuse.Count)
            {
                EnsureProceduralBlock(coord, worldSystem);
                continue;
            }

            var oldCoord = toReuse[reuseIndex++];
            var block = proceduralBlocks[oldCoord];
            proceduralBlocks.Remove(oldCoord);
            proceduralBlocks[coord] = block;
        }

        foreach (var kvp in proceduralBlocks)
        {
            SetBlockTransformPosition(kvp.Value, kvp.Key, blockWorldSizeX, blockWorldSizeY, "WorldBlock");
        }
    }

    private void EnsureProceduralEntityBlocks(HashSet<Vector2Int> desiredCoords, float blockWorldSizeX, float blockWorldSizeY, WorldSystem worldSystem)
    {
        if (proceduralEntitiesRoot == null)
        {
            return;
        }

        var data = worldSystem.CurrentPrefabData;
        if (data == null || data.entities == null)
        {
            return;
        }

        var prefabLookup = BuildPrefabLookup(data);
        var treePrefabs = ResolveEntityPrefabs(data, data.entities.treePrefabs, "tree");
        var rockPrefabs = ResolveEntityPrefabs(data, data.entities.rockPrefabs, "rock");

        var toReuse = new List<Vector2Int>();
        foreach (var coord in proceduralEntityBlocks.Keys)
        {
            if (!desiredCoords.Contains(coord))
            {
                toReuse.Add(coord);
            }
        }

        var reuseIndex = 0;
        foreach (var coord in desiredCoords)
        {
            if (proceduralEntityBlocks.ContainsKey(coord))
            {
                continue;
            }

            if (reuseIndex >= toReuse.Count)
            {
                EnsureProceduralEntityBlock(coord, worldSystem, data, prefabLookup, treePrefabs, rockPrefabs);
                continue;
            }

            var oldCoord = toReuse[reuseIndex++];
            var block = proceduralEntityBlocks[oldCoord];
            proceduralEntityBlocks.Remove(oldCoord);
            proceduralEntityBlocks[coord] = block;
            RebuildProceduralEntityBlock(block, coord, worldSystem, data, prefabLookup, treePrefabs, rockPrefabs);
        }

        foreach (var kvp in proceduralEntityBlocks)
        {
            SetBlockTransformPosition(kvp.Value, kvp.Key, blockWorldSizeX, blockWorldSizeY, "EntitiesBlock");
        }
    }

    private void SetBlockTransformPosition(Transform transform, Vector2Int coord, float blockWorldSizeX, float blockWorldSizeY, string prefix)
    {
        if (transform == null)
        {
            return;
        }

        transform.localPosition = new Vector3(coord.x * blockWorldSizeX, coord.y * blockWorldSizeY, 0f);
        transform.name = $"{prefix}_{coord.x}_{coord.y}";
    }

    private static System.Collections.IEnumerator DestroyBlockChildrenOverFrames(GameObject blockRoot, int chunkSize)
    {
        if (blockRoot == null)
        {
            yield break;
        }

        var tr = blockRoot.transform;
        while (tr.childCount > 0)
        {
            var n = Mathf.Min(chunkSize, tr.childCount);
            for (var i = 0; i < n; i++)
            {
                var child = tr.GetChild(0);
                if (child != null)
                {
                    Destroy(child.gameObject);
                }
            }

            yield return null;
        }
    }

    private void EnsureProceduralBlock(Vector2Int coord, WorldSystem worldSystem)
    {
        if (proceduralWorldRoot == null || proceduralBlocks.ContainsKey(coord))
        {
            return;
        }

        var block = CreateProceduralBlock(coord, proceduralWorldRoot.transform, worldSystem);
        if (block != null)
        {
            proceduralBlocks[coord] = block;
        }
    }

    private void EnsureProceduralEntityBlock(
        Vector2Int coord,
        WorldSystem worldSystem,
        PrefabWorldData data,
        Dictionary<string, PrefabDefinition> prefabLookup,
        List<string> treePrefabs,
        List<string> rockPrefabs)
    {
        if (proceduralEntitiesRoot == null || proceduralEntityBlocks.ContainsKey(coord))
        {
            return;
        }

        var blockRoot = new GameObject($"EntitiesBlock_{coord.x}_{coord.y}");
        blockRoot.transform.SetParent(proceduralEntitiesRoot.transform, false);
        RebuildProceduralEntityBlock(blockRoot.transform, coord, worldSystem, data, prefabLookup, treePrefabs, rockPrefabs);
        proceduralEntityBlocks[coord] = blockRoot.transform;
    }

    private void RebuildProceduralEntityBlock(
        Transform blockRoot,
        Vector2Int coord,
        WorldSystem worldSystem,
        PrefabWorldData data,
        Dictionary<string, PrefabDefinition> prefabLookup,
        List<string> treePrefabs,
        List<string> rockPrefabs)
    {
        RebuildProceduralEntityBlockClear(blockRoot);
        var random = GetEntityBlockRandom(coord, data);
        var tileScale = GetProceduralTileScale();
        var lowOrder = ResolvePlayerSortingOrder() - 1;
        RebuildProceduralEntityBlockTrees(blockRoot, coord, worldSystem, data, prefabLookup, treePrefabs, tileScale, random, lowOrder);
        RebuildProceduralEntityBlockRocks(blockRoot, coord, worldSystem, data, prefabLookup, rockPrefabs, tileScale, random, lowOrder);
        RebuildProceduralEntityBlockChests(blockRoot, coord, worldSystem, data, tileScale, random, lowOrder);
        RebuildProceduralEntityBlockCompanions(blockRoot, coord, worldSystem, data, tileScale, random, lowOrder);
        RebuildProceduralEntityBlockEnemies(blockRoot, coord, worldSystem, data, tileScale, random, lowOrder);
    }

    private static System.Random GetEntityBlockRandom(Vector2Int coord, PrefabWorldData data)
    {
        var baseSeed = (data != null && data.seed != 0 ? data.seed : UnityEngine.Random.Range(0, 100000)) + 7919;
        unchecked
        {
            var blockSeed = (baseSeed * 397) ^ coord.x;
            blockSeed = (blockSeed * 397) ^ coord.y;
            return new System.Random(blockSeed);
        }
    }

    private void RebuildProceduralEntityBlockClear(Transform blockRoot)
    {
        if (blockRoot == null)
        {
            return;
        }

        for (var i = blockRoot.childCount - 1; i >= 0; i--)
        {
            Destroy(blockRoot.GetChild(i).gameObject);
        }
    }

    private void RebuildProceduralEntityBlockTrees(
        Transform blockRoot,
        Vector2Int coord,
        WorldSystem worldSystem,
        PrefabWorldData data,
        Dictionary<string, PrefabDefinition> prefabLookup,
        List<string> treePrefabs,
        float tileScale,
        System.Random random,
        int lowOrder)
    {
        if (blockRoot == null || worldSystem == null || data?.entities == null)
        {
            return;
        }

        PlacePrefabDensityEntities(blockRoot, worldSystem, data.entities.treeDensity, data.entities.treeBlockedTerrainTypes, treePrefabs, prefabLookup, tileScale, random, lowOrder, "Tree", coord);
    }

    private void RebuildProceduralEntityBlockRocks(
        Transform blockRoot,
        Vector2Int coord,
        WorldSystem worldSystem,
        PrefabWorldData data,
        Dictionary<string, PrefabDefinition> prefabLookup,
        List<string> rockPrefabs,
        float tileScale,
        System.Random random,
        int lowOrder)
    {
        if (blockRoot == null || worldSystem == null || data?.entities == null)
        {
            return;
        }

        PlacePrefabDensityEntities(blockRoot, worldSystem, data.entities.rockDensity, data.entities.rockBlockedTerrainTypes, rockPrefabs, prefabLookup, tileScale, random, lowOrder, "Rock", coord);
    }

    private void RebuildProceduralEntityBlockChests(Transform blockRoot, Vector2Int coord, WorldSystem worldSystem, PrefabWorldData data, float tileScale, System.Random random, int lowOrder)
    {
        if (blockRoot == null || worldSystem == null || data?.entities?.chests == null)
        {
            return;
        }

        foreach (var chest in data.entities.chests)
        {
            var count = chest.count;
            if (count > 0)
            {
                PlaceChestEntities(blockRoot, worldSystem, count, chest.blockedTerrainTypes, chest.chestId, tileScale, random, lowOrder, coord);
            }
        }
    }

    private void RebuildProceduralEntityBlockCompanions(Transform blockRoot, Vector2Int coord, WorldSystem worldSystem, PrefabWorldData data, float tileScale, System.Random random, int lowOrder)
    {
        if (blockRoot == null || worldSystem == null || data?.companions == null)
        {
            return;
        }

        PlaceCompanionEntities(blockRoot, worldSystem, data.companions, tileScale, random, lowOrder, coord);
    }

    private void RebuildProceduralEntityBlockEnemies(Transform blockRoot, Vector2Int coord, WorldSystem worldSystem, PrefabWorldData data, float tileScale, System.Random random, int lowOrder)
    {
        if (blockRoot == null || worldSystem == null || data?.enemies == null)
        {
            return;
        }

        PlaceEnemyEntities(blockRoot, worldSystem, data.enemies, tileScale, random, lowOrder, coord);
    }

    private const int TerrainRowsPerFrame = 3;
    private const float ProceduralLoadMaxSecondsPerFrame = 0.001f;

    private Transform CreateProceduralBlock(Vector2Int coord, Transform parent, WorldSystem worldSystem)
    {
        if (parent == null || worldSystem == null || worldSystem.Tiles == null)
        {
            return null;
        }

        var root = new GameObject($"WorldBlock_{coord.x}_{coord.y}");
        root.transform.SetParent(parent, false);

        var width = worldSystem.Tiles.GetLength(0);
        var height = worldSystem.Tiles.GetLength(1);
        CreateProceduralBlockTilesForRowRange(root.transform, coord, worldSystem, 0, height);
        return root.transform;
    }

    private void CreateProceduralBlockTilesForRowRange(Transform root, Vector2Int coord, WorldSystem worldSystem, int yStart, int yCount)
    {
        if (root == null || worldSystem == null || worldSystem.Tiles == null)
        {
            return;
        }

        var width = worldSystem.Tiles.GetLength(0);
        var height = worldSystem.Tiles.GetLength(1);
        var groundTiles = worldSystem.CurrentPrefabData?.groundTiles;
        var seed = worldSystem.Config.seed;
        var fallbackScale = GetProceduralTileScale();
        var yEnd = Mathf.Min(yStart + yCount, height);

        for (var x = 0; x < width; x++)
        {
            for (var y = yStart; y < yEnd; y++)
            {
                var globalX = coord.x * width + x;
                var globalY = coord.y * height + y;
                var tileValue = GetProceduralTerrainAt(globalX, globalY, worldSystem);
                var created = false;
                if (groundTiles != null)
                {
                    var spec = GetGroundTileSpec(groundTiles, tileValue, seed, globalX, globalY);
                    if (!string.IsNullOrWhiteSpace(spec) && TryCreateProceduralTileSprite(spec, seed, x, y, out var sprite, out var tileScale))
                    {
                        var tileObject = new GameObject($"Tile_{x}_{y}");
                        tileObject.transform.SetParent(root, false);
                        tileObject.transform.localPosition = new Vector3(x * tileScale, y * tileScale, 0f);
                        var renderer = tileObject.AddComponent<SpriteRenderer>();
                        renderer.sprite = sprite;
                        renderer.sortingOrder = 0; // Keep ground behind entity low (playerOrder - 20) and character
                        tileObject.transform.localScale = new Vector3(tileScale, tileScale, 1f);
                        created = true;
                    }
                }

                if (!created)
                {
                    var color = tileValue switch
                    {
                        0 => new Color(0.2f, 0.35f, 0.2f, 1f),
                        1 => new Color(0.2f, 0.2f, 0.35f, 1f),
                        2 => new Color(0.35f, 0.25f, 0.18f, 1f),
                        _ => new Color(0.55f, 0.55f, 0.6f, 1f)
                    };
                    var quad = PrefabFactory.CreatePlaceholder(new Vector3(x * fallbackScale, y * fallbackScale, 0f), color, fallbackScale);
                    quad.transform.SetParent(root, true);
                }
            }
        }
    }

    private Transform CreateProceduralBlockRootOnly(Vector2Int coord, Transform parent)
    {
        if (parent == null)
        {
            return null;
        }

        var root = new GameObject($"WorldBlock_{coord.x}_{coord.y}");
        root.transform.SetParent(parent, false);
        return root.transform;
    }

    private Dictionary<string, PrefabDefinition> BuildPrefabLookup(PrefabWorldData data)
    {
        var result = new Dictionary<string, PrefabDefinition>();
        if (data?.prefabs == null)
        {
            return result;
        }

        foreach (var prefab in data.prefabs)
        {
            if (prefab == null || string.IsNullOrWhiteSpace(prefab.id))
            {
                continue;
            }
            result[prefab.id] = prefab;
        }

        return result;
    }

    private Dictionary<string, PrefabDefinition> GetChestPrefabs()
    {
        if (Application.isEditor)
        {
            cachedChestPrefabs = WorldPrefabLoader.LoadChests();
            return cachedChestPrefabs;
        }

        if (cachedChestPrefabs != null)
        {
            return cachedChestPrefabs;
        }

        cachedChestPrefabs = WorldPrefabLoader.LoadChests();
        return cachedChestPrefabs;
    }

    private Dictionary<string, CompanionDefinitionData> GetCompanionDefinitions()
    {
        if (Application.isEditor && Time.realtimeSinceStartup >= nextCompanionRefreshTime)
        {
            cachedCompanionDefinitions = null;
            nextCompanionRefreshTime = Time.realtimeSinceStartup + 0.5f;
        }

        if (cachedCompanionDefinitions != null)
        {
            return cachedCompanionDefinitions;
        }

        cachedCompanionDefinitions = WorldPrefabLoader.LoadCompanionDefinitions();
        return cachedCompanionDefinitions;
    }

    private Dictionary<string, EnemyDefinitionData> GetEnemyDefinitions()
    {
        if (Application.isEditor && Time.realtimeSinceStartup >= nextEnemyRefreshTime)
        {
            cachedEnemyDefinitions = null;
            nextEnemyRefreshTime = Time.realtimeSinceStartup + 0.5f;
        }

        if (cachedEnemyDefinitions != null)
        {
            return cachedEnemyDefinitions;
        }

        cachedEnemyDefinitions = WorldPrefabLoader.LoadEnemyDefinitions();
        return cachedEnemyDefinitions;
    }

    private List<string> ResolveEntityPrefabs(PrefabWorldData data, List<string> configured, string type)
    {
        var result = new List<string>();
        if (configured != null && configured.Count > 0)
        {
            foreach (var prefabId in configured)
            {
                if (!string.IsNullOrWhiteSpace(prefabId))
                {
                    result.Add(prefabId);
                }
            }
            return result;
        }

        if (data?.prefabs == null)
        {
            return result;
        }

        foreach (var prefab in data.prefabs)
        {
            if (prefab == null || string.IsNullOrWhiteSpace(prefab.id))
            {
                continue;
            }
            if (string.Equals(prefab.type, type, StringComparison.OrdinalIgnoreCase))
            {
                result.Add(prefab.id);
            }
        }

        return result;
    }

    private List<CompanionDefinitionData> ResolveCompanionDefinitions(
        PrefabCompanionSpawnData spawnData,
        Dictionary<string, CompanionDefinitionData> definitions)
    {
        var result = new List<CompanionDefinitionData>();
        if (definitions == null || definitions.Count == 0)
        {
            return result;
        }

        if (spawnData?.types == null || spawnData.types.Count == 0)
        {
            result.AddRange(definitions.Values);
            return result;
        }

        var added = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var type in spawnData.types)
        {
            var token = NormalizeToken(type);
            if (string.IsNullOrWhiteSpace(token))
            {
                continue;
            }

            var matched = false;
            foreach (var definition in definitions.Values)
            {
                if (definition == null)
                {
                    continue;
                }

                if (MatchesToken(definition.id, token) || MatchesToken(definition.name, token))
                {
                    if (added.Add(definition.id))
                    {
                        result.Add(definition);
                    }
                    matched = true;
                }
            }

            if (!matched)
            {
                var placeholder = new CompanionDefinitionData
                {
                    id = $"{token}_placeholder",
                    name = type,
                    description = "Unknown companion",
                    requiredBefriendingItem = string.Empty,
                    level = 1,
                    prefab = null
                };
                if (added.Add(placeholder.id))
                {
                    result.Add(placeholder);
                }
            }
        }

        if (result.Count == 0)
        {
            result.AddRange(definitions.Values);
        }

        return result;
    }

    private List<EnemyDefinitionData> ResolveEnemyDefinitions(
        PrefabEnemySpawnData spawnData,
        Dictionary<string, EnemyDefinitionData> definitions)
    {
        var result = new List<EnemyDefinitionData>();
        if (definitions == null || definitions.Count == 0)
        {
            return result;
        }

        if (spawnData?.types == null || spawnData.types.Count == 0)
        {
            result.AddRange(definitions.Values);
            return result;
        }

        var added = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var type in spawnData.types)
        {
            var token = NormalizeToken(type);
            if (string.IsNullOrWhiteSpace(token))
            {
                continue;
            }

            var matched = false;
            foreach (var definition in definitions.Values)
            {
                if (definition == null)
                {
                    continue;
                }

                if (MatchesToken(definition.id, token) || MatchesToken(definition.name, token))
                {
                    if (added.Add(definition.id))
                    {
                        result.Add(definition);
                    }
                    matched = true;
                }
            }

            if (!matched)
            {
                var placeholder = new EnemyDefinitionData
                {
                    id = $"{token}_placeholder",
                    name = type,
                    description = "Unknown enemy",
                    level = 1,
                    prefab = null
                };
                if (added.Add(placeholder.id))
                {
                    result.Add(placeholder);
                }
            }
        }

        if (result.Count == 0)
        {
            result.AddRange(definitions.Values);
        }

        return result;
    }

    private string NormalizeToken(string value)
    {
        return string.IsNullOrWhiteSpace(value)
            ? string.Empty
            : value.Replace(" ", string.Empty).Replace("-", string.Empty).Replace("_", string.Empty).ToLowerInvariant();
    }

    private bool MatchesToken(string value, string token)
    {
        if (string.IsNullOrWhiteSpace(value) || string.IsNullOrWhiteSpace(token))
        {
            return false;
        }

        return NormalizeToken(value).Contains(token);
    }

    private int GetProceduralTerrainAt(int globalX, int globalY, WorldSystem worldSystem)
    {
        var thresholds = worldSystem?.CurrentPrefabData?.thresholds ?? new TerrainThresholds();
        var waterFeatures = worldSystem?.CurrentPrefabData?.waterFeatures;
        var seed = worldSystem != null ? worldSystem.Config.seed : 0;

        var random = new System.Random(seed);
        var offsetX = (float)random.NextDouble() * 1000f;
        var offsetY = (float)random.NextDouble() * 1000f;
        var noiseScale = 0.08f;

        var nx = (globalX + offsetX) * noiseScale;
        var ny = (globalY + offsetY) * noiseScale;
        var primary = Mathf.PerlinNoise(nx, ny);
        var secondary = Mathf.PerlinNoise(nx * 2f, ny * 2f) * 0.5f;
        var value = Mathf.Clamp01((primary + secondary) / 1.5f);

        if (waterFeatures != null && string.Equals(waterFeatures.type, "rivers", StringComparison.OrdinalIgnoreCase))
        {
            var riverOffsetX = (float)random.NextDouble() * 2000f;
            var riverOffsetY = (float)random.NextDouble() * 2000f;
            var riverScale = 0.04f;
            var riverValue = Mathf.PerlinNoise((globalX + riverOffsetX) * riverScale, (globalY + riverOffsetY) * riverScale);
            var density = (waterFeatures.density ?? string.Empty).Trim().ToLowerInvariant();
            var riverWidth = density switch
            {
                "low" => 0.03f,
                "high" => 0.07f,
                _ => 0.05f
            };

            if (Mathf.Abs(riverValue - 0.5f) < riverWidth)
            {
                return 0;
            }
        }

        if (value < thresholds.water)
        {
            return 0;
        }

        if (value < thresholds.grass)
        {
            return 1;
        }

        if (value < thresholds.dirt)
        {
            return 2;
        }

        return 3;
    }

    private void PlacePrefabDensityEntities(
        Transform parent,
        WorldSystem worldSystem,
        float density,
        List<string> blocked,
        List<string> prefabIds,
        Dictionary<string, PrefabDefinition> prefabs,
        float tileScale,
        System.Random random,
        int sortingOrder,
        string fallbackName,
        Vector2Int blockCoord)
    {
        if (density <= 0f)
        {
            return;
        }

        var width = worldSystem.Tiles.GetLength(0);
        var height = worldSystem.Tiles.GetLength(1);
        var total = width * height;
        var count = Mathf.Clamp(Mathf.RoundToInt(total * density), 0, total);
        PlacePrefabCountEntities(parent, worldSystem, count, blocked, prefabIds, prefabs, tileScale, random, sortingOrder, fallbackName, blockCoord);
    }

    private void PlacePrefabCountEntities(
        Transform parent,
        WorldSystem worldSystem,
        int count,
        List<string> blocked,
        List<string> prefabIds,
        Dictionary<string, PrefabDefinition> prefabs,
        float tileScale,
        System.Random random,
        int sortingOrder,
        string fallbackName,
        Vector2Int blockCoord)
    {
        if (count <= 0)
        {
            return;
        }

        var width = worldSystem.Tiles.GetLength(0);
        var height = worldSystem.Tiles.GetLength(1);
        var attempts = 0;
        var placed = 0;
        var maxAttempts = count * 10;

        while (placed < count && attempts < maxAttempts)
        {
            attempts++;
            var x = random.Next(0, width);
            var y = random.Next(0, height);
            var globalX = blockCoord.x * width + x;
            var globalY = blockCoord.y * height + y;
            var terrain = GetProceduralTerrainAt(globalX, globalY, worldSystem);
            if (IsBlocked(terrain, blocked))
            {
                continue;
            }

            PrefabDefinition prefab = null;
            if (prefabIds != null && prefabIds.Count > 0)
            {
                var prefabId = prefabIds[random.Next(0, prefabIds.Count)];
                prefabs?.TryGetValue(prefabId, out prefab);
            }

            var tileCoord = new Vector2Int(x, y);
            if (prefab != null)
            {
                CreatePrefabAtTile(parent, prefab, tileCoord, worldSystem.Config.seed, tileScale, sortingOrder);
            }
            else
            {
                CreateMarkerAtTile(parent, tileCoord, fallbackName, new Color(0.6f, 0.6f, 0.6f, 1f), tileScale, sortingOrder);
            }

            placed++;
        }
    }

    private void PlaceChestEntities(
        Transform parent,
        WorldSystem worldSystem,
        int count,
        List<string> blocked,
        string chestId,
        float baseTileScale,
        System.Random random,
        int sortingOrder,
        Vector2Int blockCoord)
    {
        if (count <= 0)
        {
            return;
        }

        var width = worldSystem.Tiles.GetLength(0);
        var height = worldSystem.Tiles.GetLength(1);
        var total = width * height;
        var density = total > 0 ? (float)count / total : 0f;
        var targetCount = Mathf.Clamp(Mathf.RoundToInt(total * density), 0, total);

        var chestPrefabs = GetChestPrefabs();
        var attempts = 0;
        var placed = 0;
        var maxAttempts = targetCount * 10;
        while (placed < targetCount && attempts < maxAttempts)
        {
            attempts++;
            var x = random.Next(0, width);
            var y = random.Next(0, height);
            var globalX = blockCoord.x * width + x;
            var globalY = blockCoord.y * height + y;
            var terrain = GetProceduralTerrainAt(globalX, globalY, worldSystem);
            if (IsBlocked(terrain, blocked))
            {
                continue;
            }

            var tileCoord = new Vector2Int(x, y);
            if (TryGetChestPrefab(chestPrefabs, chestId, out var chestPrefab))
            {
                CreatePrefabAtTile(parent, chestPrefab, tileCoord, worldSystem.Config.seed, baseTileScale, sortingOrder);
            }
            else if (TryCreateChestSprite(chestId, worldSystem.Config.seed, tileCoord.x, tileCoord.y, out var sprite, out var tileScale))
            {
                var tileObject = new GameObject($"Chest_{x}_{y}");
                tileObject.transform.SetParent(parent, false);
                tileObject.transform.localPosition = new Vector3(x * tileScale, y * tileScale, 0f);
                var renderer = tileObject.AddComponent<SpriteRenderer>();
                renderer.sprite = sprite;
                renderer.sortingOrder = sortingOrder;
                tileObject.transform.localScale = new Vector3(tileScale, tileScale, 1f);
            }
            else
            {
                var marker = PrefabFactory.CreateMarker("Chest", new Vector3(x * baseTileScale, y * baseTileScale, 0f), new Color(0.85f, 0.7f, 0.2f, 1f), baseTileScale, sortingOrder);
                marker.transform.SetParent(parent, true);
            }

            placed++;
        }
    }

    private void PlaceCompanionEntities(
        Transform parent,
        WorldSystem worldSystem,
        PrefabCompanionSpawnData spawnData,
        float tileScale,
        System.Random random,
        int sortingOrder,
        Vector2Int blockCoord)
    {
        if (spawnData == null || spawnData.spawnRate <= 0f || worldSystem?.Tiles == null)
        {
            return;
        }

        var definitions = ResolveCompanionDefinitions(spawnData, GetCompanionDefinitions());
        if (definitions.Count == 0)
        {
            return;
        }

        var width = worldSystem.Tiles.GetLength(0);
        var height = worldSystem.Tiles.GetLength(1);
        var total = width * height;
        var count = Mathf.Clamp(Mathf.RoundToInt(total * spawnData.spawnRate), 0, total);
        var attempts = 0;
        var placed = 0;
        var maxAttempts = count * 10;

        while (placed < count && attempts < maxAttempts)
        {
            attempts++;
            var x = random.Next(0, width);
            var y = random.Next(0, height);
            var globalX = blockCoord.x * width + x;
            var globalY = blockCoord.y * height + y;
            var terrain = GetProceduralTerrainAt(globalX, globalY, worldSystem);
            if (IsBlocked(terrain, spawnData.blockedTerrainTypes))
            {
                continue;
            }

            var definition = definitions[random.Next(0, definitions.Count)];
            var prefab = definition?.prefab;
            var tileCoord = new Vector2Int(x, y);
            GameObject root;
            if (prefab == null)
            {
                root = CreateMarkerAtTile(parent, tileCoord, definition?.name ?? "Companion", new Color(0.5f, 0.75f, 0.55f, 1f), tileScale, sortingOrder);
                if (root != null)
                {
                    var collider = root.AddComponent<BoxCollider2D>();
                    collider.size = new Vector2(tileScale * 0.8f, tileScale * 0.8f);
                }
            }
            else
            {
                root = CreatePrefabAtTile(parent, prefab, tileCoord, worldSystem.Config.seed, tileScale, sortingOrder);
            }

            AttachCompanionInstance(root, definition);
            placed++;
        }
    }

    private void PlaceEnemyEntities(
        Transform parent,
        WorldSystem worldSystem,
        PrefabEnemySpawnData spawnData,
        float tileScale,
        System.Random random,
        int sortingOrder,
        Vector2Int blockCoord)
    {
        if (spawnData == null || spawnData.spawnRate <= 0f || worldSystem?.Tiles == null)
        {
            return;
        }

        var definitions = ResolveEnemyDefinitions(spawnData, GetEnemyDefinitions());
        if (definitions.Count == 0)
        {
            return;
        }

        var width = worldSystem.Tiles.GetLength(0);
        var height = worldSystem.Tiles.GetLength(1);
        var total = width * height;
        var count = Mathf.Clamp(Mathf.RoundToInt(total * spawnData.spawnRate), 0, total);
        var attempts = 0;
        var placed = 0;
        var maxAttempts = count * 10;

        while (placed < count && attempts < maxAttempts)
        {
            attempts++;
            var x = random.Next(0, width);
            var y = random.Next(0, height);
            var globalX = blockCoord.x * width + x;
            var globalY = blockCoord.y * height + y;
            var terrain = GetProceduralTerrainAt(globalX, globalY, worldSystem);
            if (IsBlocked(terrain, spawnData.blockedTerrainTypes))
            {
                continue;
            }

            var definition = definitions[random.Next(0, definitions.Count)];
            var prefab = definition?.prefab;
            var tileCoord = new Vector2Int(x, y);
            GameObject root;
            if (prefab == null)
            {
                root = CreateMarkerAtTile(parent, tileCoord, definition?.name ?? "Enemy", new Color(0.75f, 0.45f, 0.45f, 1f), tileScale, sortingOrder);
                if (root != null)
                {
                    var collider = root.AddComponent<BoxCollider2D>();
                    collider.size = new Vector2(tileScale * 0.8f, tileScale * 0.8f);
                }
            }
            else
            {
                root = CreatePrefabAtTile(parent, prefab, tileCoord, worldSystem.Config.seed, tileScale, sortingOrder);
            }

            AttachEnemyInstance(root, definition);
            placed++;
        }
    }

    private static bool TryGetChestPrefab(Dictionary<string, PrefabDefinition> chestPrefabs, string chestId, out PrefabDefinition chestPrefab)
    {
        chestPrefab = null;
        if (chestPrefabs == null || string.IsNullOrWhiteSpace(chestId))
        {
            return false;
        }

        if (!chestPrefabs.TryGetValue(chestId, out var candidate) || candidate == null)
        {
            return false;
        }

        if (!PrefabHasRenderableTiles(candidate))
        {
            return false;
        }

        chestPrefab = candidate;
        return true;
    }

    private GameObject CreatePrefabAtTile(Transform parent, PrefabDefinition prefab, Vector2Int tileCoord, int seed, float tileScale, int baseSortingOrder)
    {
        if (prefab == null || parent == null)
        {
            return null;
        }

        var root = new GameObject(prefab.id ?? "Prefab");
        root.transform.SetParent(parent, false);
        root.transform.localPosition = new Vector3(tileCoord.x * tileScale, tileCoord.y * tileScale, 0f);

        if (prefab.parts == null || prefab.parts.Count == 0)
        {
            return root;
        }

        var tilesetAnchors = BuildPrefabTilesetAnchors(prefab);

        foreach (var part in prefab.parts)
        {
            if (part == null || part.tileGrid == null || part.tileGrid.Count == 0)
            {
                continue;
            }

            var partOrder = baseSortingOrder;
            if (!string.IsNullOrWhiteSpace(part.layer) && part.layer.Equals("high", StringComparison.OrdinalIgnoreCase))
            {
                partOrder += 10;
            }

            if (!isTiledMapActive)
            {
                var playerOrder = ResolvePlayerSortingOrder();
                var isHighLayer = !string.IsNullOrWhiteSpace(part.layer)
                    && part.layer.Equals("high", StringComparison.OrdinalIgnoreCase);
                // Entity low must be strictly behind the character's lowest part (playerOrder - 1 after SetSortingOrder shift). Use a large gap so it never overlaps.
                partOrder = isHighLayer ? playerOrder + 10 : playerOrder - 20;
            }

            RenderPrefabPart(root.transform, part, tileCoord, seed, partOrder, tilesetAnchors);
        }

        AddPrefabCollider(root, prefab, tileScale, tilesetAnchors);
        AttachChestInstance(root, prefab);
        return root;
    }

    private GameObject CreateMarkerAtTile(Transform parent, Vector2Int tileCoord, string name, Color color, float tileScale, int sortingOrder)
    {
        var marker = PrefabFactory.CreateMarker(name, new Vector3(tileCoord.x * tileScale, tileCoord.y * tileScale, 0f), color, tileScale, sortingOrder);
        if (parent != null)
        {
            marker.transform.SetParent(parent, true);
        }

        return marker;
    }

    private void RenderPrefabPart(Transform parent, PrefabPart part, Vector2Int baseTile, int seed, int sortingOrder, Dictionary<string, TilesetAnchor> tilesetAnchors)
    {
        var rows = part.tileGrid.Count;
        for (var row = 0; row < rows; row++)
        {
            var rowData = part.tileGrid[row];
            if (rowData == null)
            {
                continue;
            }

            var cols = rowData.Count;
            for (var col = 0; col < cols; col++)
            {
                var spec = rowData[col];
                if (string.IsNullOrWhiteSpace(spec))
                {
                    continue;
                }

                var tileX = baseTile.x + col;
                var tileY = baseTile.y + (rows - 1 - row);
                if (!TryCreateProceduralTileSpritesForPart(spec, seed, tileX, tileY, tilesetAnchors, out var sprites, out var resolvedScale))
                {
                    continue;
                }

                var baseOffset = new Vector2(col * resolvedScale, (rows - 1 - row) * resolvedScale);
                for (var spriteIndex = 0; spriteIndex < sprites.Count; spriteIndex++)
                {
                    var spriteInfo = sprites[spriteIndex];
                    if (spriteInfo.sprite == null)
                    {
                        continue;
                    }

                    var tileObject = new GameObject($"Part_{tileX}_{tileY}_{spriteIndex}");
                    tileObject.transform.SetParent(parent, false);
                    tileObject.transform.localPosition = new Vector3(
                        baseOffset.x + spriteInfo.localOffset.x,
                        baseOffset.y + spriteInfo.localOffset.y,
                        0f);
                    var renderer = tileObject.AddComponent<SpriteRenderer>();
                    renderer.sprite = spriteInfo.sprite;
                    renderer.sortingOrder = sortingOrder;
                    tileObject.transform.localScale = new Vector3(spriteInfo.scale, spriteInfo.scale, 1f);
                }
            }
        }
    }

    private void AddPrefabCollider(GameObject root, PrefabDefinition prefab, float tileScale, Dictionary<string, TilesetAnchor> tilesetAnchors)
    {
        if (root == null || prefab?.collision == null)
        {
            return;
        }

        var size = prefab.collision.size;
        if (size.x <= 0f || size.y <= 0f)
        {
            return;
        }

        var scaleFactor = tileScale / TargetTilePixelSize;
        var collider = root.GetComponent<BoxCollider2D>();
        if (collider == null)
        {
            collider = root.AddComponent<BoxCollider2D>();
        }

        collider.size = size * scaleFactor;
        var offset = prefab.collisionOffset;
        var centerShift = GetPrefabGridCenterOffset(prefab, tileScale, tilesetAnchors);
        var scaledOffset = new Vector2(offset.x * scaleFactor, offset.y * scaleFactor);
        collider.offset = scaledOffset + centerShift;
        collider.isTrigger = false;

        Debug.Log($"[Collision] Added collider for {root.name} size {collider.size} offset {collider.offset} rawSize {size} rawOffset {offset} scale {scaleFactor}");
        if (showPrefabColliderOutlines)
        {
            AddColliderOutline(root, collider);
        }
    }

    private void AttachChestInstance(GameObject root, PrefabDefinition prefab)
    {
        if (root == null || prefab == null)
        {
            return;
        }

        if (!IsChestPrefab(prefab))
        {
            return;
        }

        var chest = root.GetComponent<ChestInstance>();
        if (chest == null)
        {
            chest = root.AddComponent<ChestInstance>();
        }

        chest.Initialize(prefab);
    }

    private void AttachCompanionInstance(GameObject root, CompanionDefinitionData definition)
    {
        if (root == null || definition == null)
        {
            return;
        }

        var companion = root.GetComponent<CompanionInstance>();
        if (companion == null)
        {
            companion = root.AddComponent<CompanionInstance>();
        }

        companion.Initialize(definition);
    }

    private void AttachEnemyInstance(GameObject root, EnemyDefinitionData definition)
    {
        if (root == null || definition == null)
        {
            return;
        }

        var enemy = root.GetComponent<EnemyInstance>();
        if (enemy == null)
        {
            enemy = root.AddComponent<EnemyInstance>();
        }

        enemy.Initialize(definition);
    }

    private static bool IsChestPrefab(PrefabDefinition prefab)
    {
        if (prefab == null)
        {
            return false;
        }

        if (!string.IsNullOrWhiteSpace(prefab.type) && prefab.type.Equals("chest", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return !string.IsNullOrWhiteSpace(prefab.id) && prefab.id.StartsWith("chest_", StringComparison.OrdinalIgnoreCase);
    }

    private Vector2 GetPrefabGridCenterOffset(PrefabDefinition prefab, float tileScale, Dictionary<string, TilesetAnchor> tilesetAnchors)
    {
        if (!string.IsNullOrWhiteSpace(prefab?.type) && prefab.type.Equals("tree", StringComparison.OrdinalIgnoreCase))
        {
            var treeOffset = GetTreeLowLayerCenterOffset(prefab, tilesetAnchors, tileScale);
            if (treeOffset != Vector2.zero)
            {
                return treeOffset;
            }
        }

        if (prefab?.parts == null || prefab.parts.Count == 0)
        {
            return Vector2.zero;
        }

        var maxRows = 0;
        var maxCols = 0;
        for (var partIndex = 0; partIndex < prefab.parts.Count; partIndex++)
        {
            var part = prefab.parts[partIndex];
            if (part?.tileGrid == null)
            {
                continue;
            }

            maxRows = Mathf.Max(maxRows, part.tileGrid.Count);
            for (var rowIndex = 0; rowIndex < part.tileGrid.Count; rowIndex++)
            {
                var row = part.tileGrid[rowIndex];
                if (row == null)
                {
                    continue;
                }
                maxCols = Mathf.Max(maxCols, row.Count);
            }
        }

        if (maxRows <= 0 || maxCols <= 0)
        {
            return Vector2.zero;
        }

        return new Vector2((maxCols - 1) * tileScale * 0.5f, (maxRows - 1) * tileScale * 0.5f);
    }

    private Vector2 GetTreeLowLayerCenterOffset(PrefabDefinition prefab, Dictionary<string, TilesetAnchor> tilesetAnchors, float tileScale)
    {
        if (prefab?.parts == null || prefab.parts.Count == 0)
        {
            return Vector2.zero;
        }

        var minCol = int.MaxValue;
        var maxCol = int.MinValue;
        var minRow = int.MaxValue;
        var maxRow = int.MinValue;
        var anchor = default(TilesetAnchor);
        var anchorSet = false;

        for (var partIndex = 0; partIndex < prefab.parts.Count; partIndex++)
        {
            var part = prefab.parts[partIndex];
            if (part == null || part.tileGrid == null || part.tileGrid.Count == 0)
            {
                continue;
            }

            if (!string.IsNullOrWhiteSpace(part.layer) && part.layer.Equals("high", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            for (var rowIndex = 0; rowIndex < part.tileGrid.Count; rowIndex++)
            {
                var row = part.tileGrid[rowIndex];
                if (row == null)
                {
                    continue;
                }

                for (var colIndex = 0; colIndex < row.Count; colIndex++)
                {
                    var spec = row[colIndex];
                    if (string.IsNullOrWhiteSpace(spec))
                    {
                        continue;
                    }

                    if (!TryGetTilesetToken(spec, out var tilesetName, out var token))
                    {
                        continue;
                    }

                    var tileset = GetProceduralTileset(tilesetName);
                    if (tileset == null || tileset.columns <= 0)
                    {
                        continue;
                    }

                    if (tilesetAnchors != null && tilesetAnchors.TryGetValue(tilesetName, out var tilesetAnchor))
                    {
                        anchor = tilesetAnchor;
                        anchorSet = true;
                    }

                    if (int.TryParse(token, out var tileId))
                    {
                        UpdateTileBounds(tileset, tileId, ref minCol, ref maxCol, ref minRow, ref maxRow);
                        continue;
                    }

                    if (tileset.typeToIds.TryGetValue(token, out var ids))
                    {
                        for (var idIndex = 0; idIndex < ids.Count; idIndex++)
                        {
                            UpdateTileBounds(tileset, ids[idIndex], ref minCol, ref maxCol, ref minRow, ref maxRow);
                        }
                    }
                }
            }
        }

        if (minCol == int.MaxValue || maxCol == int.MinValue || minRow == int.MaxValue || maxRow == int.MinValue)
        {
            return Vector2.zero;
        }

        if (!anchorSet)
        {
            anchor.minCol = minCol;
            anchor.maxRow = maxRow;
        }

        var centerCol = (minCol + maxCol) * 0.5f;
        var centerRow = (minRow + maxRow) * 0.5f;
        return new Vector2((centerCol - anchor.minCol) * tileScale, (anchor.maxRow - centerRow) * tileScale);
    }

    private void AddColliderOutline(GameObject root, BoxCollider2D collider)
    {
        if (root == null || collider == null)
        {
            return;
        }

        var outline = root.transform.Find("ColliderOutline");
        if (outline != null)
        {
            Destroy(outline.gameObject);
        }

        var outlineObject = new GameObject("ColliderOutline");
        outlineObject.transform.SetParent(root.transform, false);
        outlineObject.transform.localPosition = Vector3.zero;

        var line = outlineObject.AddComponent<LineRenderer>();
        line.useWorldSpace = false;
        line.loop = true;
        line.positionCount = 4;
        line.startWidth = 0.03f;
        line.endWidth = 0.03f;
        line.numCapVertices = 0;
        line.numCornerVertices = 0;
        line.sortingOrder = 999;
        line.material = GetPrefabColliderMaterial();
        line.startColor = new Color(1f, 0.15f, 0.6f, 0.9f);
        line.endColor = line.startColor;

        var halfSize = collider.size * 0.5f;
        var offset = collider.offset;
        line.SetPosition(0, new Vector3(offset.x - halfSize.x, offset.y - halfSize.y, 0f));
        line.SetPosition(1, new Vector3(offset.x - halfSize.x, offset.y + halfSize.y, 0f));
        line.SetPosition(2, new Vector3(offset.x + halfSize.x, offset.y + halfSize.y, 0f));
        line.SetPosition(3, new Vector3(offset.x + halfSize.x, offset.y - halfSize.y, 0f));
    }

    private static Material GetPrefabColliderMaterial()
    {
        if (prefabColliderMaterial != null)
        {
            return prefabColliderMaterial;
        }

        prefabColliderMaterial = new Material(Shader.Find("Sprites/Default"));
        return prefabColliderMaterial;
    }

    private bool TryCreateChestSprite(string chestId, int seed, int x, int y, out Sprite sprite, out float tileScale)
    {
        sprite = null;
        tileScale = 1f;

        if (!string.IsNullOrWhiteSpace(chestId) && chestId.Contains("-"))
        {
            if (TryCreateProceduralTileSprite(chestId, seed, x, y, out sprite, out tileScale))
            {
                return true;
            }
        }

        var tileset = GetProceduralTileset("chests");
        if (tileset == null)
        {
            return false;
        }

        tileScale = tileset.tileWidth > 0 ? TargetTilePixelSize / tileset.tileWidth : 1f;
        var tileId = 0;
        if (!string.IsNullOrWhiteSpace(chestId) && tileset.typeToIds != null && tileset.typeToIds.TryGetValue(chestId, out var ids) && ids.Count > 0)
        {
            var index = GetDeterministicIndex(seed, x, y, ids.Count);
            tileId = ids[index];
        }
        else
        {
            var hash = string.IsNullOrWhiteSpace(chestId) ? seed : chestId.GetHashCode();
            if (hash == int.MinValue)
            {
                hash = 0;
            }
            tileId = Mathf.Abs(hash) % Mathf.Max(1, tileset.tileCount);
        }

        sprite = proceduralRenderer.CreateSpriteFromTileset(tileset, tileId, tileset.sourcePath, tileset.tileWidth);
        return sprite != null;
    }

    private static bool PrefabHasRenderableTiles(PrefabDefinition prefab)
    {
        if (prefab?.parts == null)
        {
            return false;
        }

        foreach (var part in prefab.parts)
        {
            if (part?.tileGrid == null)
            {
                continue;
            }

            foreach (var row in part.tileGrid)
            {
                if (row == null)
                {
                    continue;
                }

                foreach (var spec in row)
                {
                    if (!string.IsNullOrWhiteSpace(spec) && !string.Equals(spec, "generate", StringComparison.OrdinalIgnoreCase))
                    {
                        return true;
                    }
                }
            }
        }

        return false;
    }

    private void EnsureWorldCamera(WorldConfig config)
    {
        var camera = Camera.main;
        if (camera == null)
        {
            var cameraObject = new GameObject("GameCamera");
            camera = cameraObject.AddComponent<Camera>();
        }

        camera.orthographic = true;
        camera.clearFlags = CameraClearFlags.SolidColor;
        camera.backgroundColor = new Color(0.08f, 0.08f, 0.1f, 1f);
        var tileScale = GetProceduralTileScale();
        var halfHeight = config.height * tileScale * 0.5f;
        camera.orthographicSize = Mathf.Max(8f, halfHeight + 1f);
        camera.transform.position = new Vector3((config.width - 1) * tileScale * 0.5f, (config.height - 1) * tileScale * 0.5f, -10f);
    }

    private float GetProceduralTileScale()
    {
        var groundTiles = WorldSystem.Instance?.CurrentPrefabData?.groundTiles;
        if (groundTiles == null)
        {
            return TargetTilePixelSize / DefaultTilePixelSize;
        }

        var spec = GetFirstGroundTileSpec(groundTiles);
        if (string.IsNullOrWhiteSpace(spec))
        {
            return TargetTilePixelSize / DefaultTilePixelSize;
        }

        var dashIndex = spec.IndexOf('-');
        if (dashIndex <= 0 || dashIndex >= spec.Length - 1)
        {
            return TargetTilePixelSize / DefaultTilePixelSize;
        }

        var tilesetName = spec.Substring(0, dashIndex);
        var tileset = GetProceduralTileset(tilesetName);
        if (tileset == null || tileset.tileWidth <= 0)
        {
            return TargetTilePixelSize / DefaultTilePixelSize;
        }

        return TargetTilePixelSize / tileset.tileWidth;
    }

    private static string GetFirstGroundTileSpec(PrefabGroundTiles groundTiles)
    {
        if (groundTiles == null)
        {
            return null;
        }

        if (groundTiles.grass != null && groundTiles.grass.Count > 0)
        {
            return groundTiles.grass[0];
        }

        if (groundTiles.water != null && groundTiles.water.Count > 0)
        {
            return groundTiles.water[0];
        }

        if (groundTiles.dirt != null && groundTiles.dirt.Count > 0)
        {
            return groundTiles.dirt[0];
        }

        if (groundTiles.stone != null && groundTiles.stone.Count > 0)
        {
            return groundTiles.stone[0];
        }

        return null;
    }

    private void EnsureWorldCameraForBounds(Bounds bounds)
    {
        var camera = Camera.main;
        if (camera == null)
        {
            var cameraObject = new GameObject("GameCamera");
            camera = cameraObject.AddComponent<Camera>();
        }

        camera.orthographic = true;
        camera.clearFlags = CameraClearFlags.SolidColor;
        camera.backgroundColor = new Color(0.08f, 0.08f, 0.1f, 1f);

        var halfHeight = bounds.extents.y + 1f;
        var halfWidth = bounds.extents.x + 1f;
        var sizeByWidth = halfWidth / Mathf.Max(0.1f, camera.aspect);
        camera.orthographicSize = Mathf.Max(8f, halfHeight, sizeByWidth);
        camera.transform.position = new Vector3(bounds.center.x, bounds.center.y, -10f);
    }

    private bool TryRenderTiledMap()
    {
        var worldSystem = WorldSystem.Instance;
        if (worldSystem == null)
        {
            return false;
        }

        var tmxName = worldSystem.CurrentPrefabData?.tmxFile;
        if (string.IsNullOrWhiteSpace(tmxName))
        {
            return false;
        }

        return LoadTiledMap(tmxName, null, false, false);
    }

    private string ResolveTmxPath(string tmxName)
    {
        var fileName = tmxName.EndsWith(".tmx") ? tmxName : $"{tmxName}.tmx";
        var candidate = Path.Combine(Application.dataPath, "XcodeImport/FableForge Shared/Prefabs/Maps/TMX", fileName);
        if (File.Exists(candidate))
        {
            return candidate;
        }

        var resourcesPath = Path.Combine(Application.dataPath, "Resources/Prefabs/Maps/TMX", fileName);
        if (File.Exists(resourcesPath))
        {
            return resourcesPath;
        }

        var customMapsPath = Path.Combine(Application.dataPath, "Resources/Maps/CustomMaps", fileName);
        if (File.Exists(customMapsPath))
        {
            return customMapsPath;
        }

        return null;
    }

    private bool LoadTiledMap(string tmxName, string doorId, bool spawnAtDoor, bool preferExitDoor)
    {
        var tmxPath = ResolveTmxPath(tmxName);
        if (string.IsNullOrWhiteSpace(tmxPath))
        {
            return false;
        }

        var map = TiledMapLoader.LoadFromFile(tmxPath);
        if (map == null)
        {
            return false;
        }

        ClearWorldVisuals();

        tiledMapTileScale = map.tileWidth > 0 ? TargetTilePixelSize / map.tileWidth : 1f;
        tiledMapTileScale = Mathf.Max(0.01f, tiledMapTileScale);
        var root = new GameObject("TiledMap");
        var renderer = new TiledMapRenderer();
        if (!renderer.Render(map, root.transform, tiledMapTileScale, out var bounds))
        {
            Destroy(root);
            return false;
        }

        tiledMapCenter = bounds.center;
        BuildTiledMapMetadata(map);
        EnsureWorldCameraForBounds(bounds);
        ConfigureGameplayCamera(tiledMapTileScale, bounds.center);
        isTiledMapActive = true;
        currentTmxName = tmxName;

        var saveData = GameState.Instance != null ? GameState.Instance.CurrentSave : null;
        if (saveData != null)
        {
            saveData.currentMapFileName = tmxName;
            saveData.useProceduralWorld = false;
            var worldSystem = WorldSystem.Instance;
            if (worldSystem != null)
            {
                saveData.worldPrefabId = worldSystem.CurrentPrefabId;
            }
        }

        if (playerTransform != null)
        {
            ApplyPlayerScale(playerTransform);
            EnsurePlayerMovement(playerTransform.gameObject);
            if (spawnAtDoor)
            {
                var spawnPosition = FindDoorSpawnPosition(doorId, preferExitDoor);
                playerTransform.position = spawnPosition ?? bounds.center;
            }
            ConfigureGameplayCamera(tiledMapTileScale, playerTransform.position);
            SetSortingOrder(playerTransform.gameObject, ResolvePlayerSortingOrder());
        }

        return true;
    }

    private void ClearWorldVisuals()
    {
        var tiledMap = GameObject.Find("TiledMap");
        if (tiledMap != null)
        {
            Destroy(tiledMap);
        }

        var worldPreview = GameObject.Find("WorldPreview");
        if (worldPreview != null)
        {
            Destroy(worldPreview);
        }

        var worldEntities = GameObject.Find("WorldEntities");
        if (worldEntities != null)
        {
            Destroy(worldEntities);
        }

        proceduralWorldRoot = null;
        proceduralEntitiesRoot = null;
        proceduralBlocks.Clear();
        proceduralEntityBlocks.Clear();
        proceduralCenterBlock = null;
    }

    private void ApplyPlayerScale(Transform target)
    {
        if (target == null)
        {
            return;
        }

        var scale = isTiledMapActive ? tiledMapTileScale : GetProceduralTileScale();
        target.localScale = playerBaseScale * scale;
    }

    private int ResolvePlayerSortingOrder()
    {
        if (isTiledMapActive)
        {
            return tiledCharacterSortingOrder > 0 ? tiledCharacterSortingOrder : 120;
        }

        return 120;
    }

    private void BuildTiledMapMetadata(TiledMapData map)
    {
        tiledDoorTiles.Clear();
        tiledCollisionTiles.Clear();
        tiledCharacterSortingOrder = 120;
        lastDoorTile = null;
        tiledSpawnTile = null;

        if (map == null)
        {
            return;
        }

        var maxLayerOrder = 0;
        for (var layerIndex = 0; layerIndex < map.layers.Count; layerIndex++)
        {
            var layer = map.layers[layerIndex];
            var properties = layer.properties ?? new Dictionary<string, string>();
            var zOffset = GetFloatProperty(properties, "zOffset", 0f);
            var layerOrder = Mathf.RoundToInt(layerIndex * 10f + zOffset);
            if (layerOrder > maxLayerOrder)
            {
                maxLayerOrder = layerOrder;
            }

            var hasCharacterLayer = GetBoolProperty(properties, "characterLayer", false) || GetFloatProperty(properties, "characterLayer", -1f) >= 0f;
            if (hasCharacterLayer)
            {
                // Use the lowest characterLayer order + 1 so the character is just in front of the walk layer; all higher-order layers (foreground, etc.) draw in front of the character
                tiledCharacterSortingOrder = Mathf.Min(layerOrder + 1, tiledCharacterSortingOrder);
                if (tiledSpawnTile == null
                    && TryGetIntProperty(properties, "spawnX", out var spawnX)
                    && TryGetIntProperty(properties, "spawnY", out var spawnY))
                {
                    tiledSpawnTile = new Vector2Int(spawnX, spawnY);
                }
            }

            var isCollision = GetBoolProperty(properties, "collision", false);
            var doorId = GetStringProperty(properties, "doorId");
            if (string.IsNullOrWhiteSpace(doorId))
            {
                doorId = GetStringProperty(properties, "door_id");
            }
            if (string.IsNullOrWhiteSpace(doorId))
            {
                doorId = layer.name ?? "Door";
            }

            var interior = GetStringProperty(properties, "interior");
            var prefabsFile = GetStringProperty(properties, "prefabsFile");
            var isExit = GetBoolProperty(properties, "exit", false);
            var proceduralTrigger = GetBoolProperty(properties, "proceduralWorldTrigger", false);
            var isDoorLayer = !string.IsNullOrWhiteSpace(interior) || isExit || proceduralTrigger || properties.ContainsKey("doorId") || properties.ContainsKey("door_id");

            foreach (var chunk in layer.chunks)
            {
                var tilesWide = chunk.width;
                var tilesHigh = chunk.height;
                var expected = tilesWide * tilesHigh;
                if (chunk.gids == null || chunk.gids.Length < expected)
                {
                    continue;
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

                        var tileX = chunk.x + col;
                        var tileY = chunk.y + row;
                        var tileKey = new Vector2Int(tileX, tileY);

                        if (isCollision)
                        {
                            tiledCollisionTiles.Add(tileKey);
                        }

                        if (isDoorLayer)
                        {
                            tiledDoorTiles[tileKey] = new TiledDoorInfo
                            {
                                doorId = doorId,
                                interior = interior,
                                prefabsFile = prefabsFile,
                                isExit = isExit,
                                proceduralWorldTrigger = proceduralTrigger,
                                tile = tileKey
                            };
                        }
                    }
                }
            }
        }

        // Character draws in front of the layer marked characterLayer (where they walk) but behind higher-order layers (foreground, etc.)
        if (tiledCharacterSortingOrder <= 0)
        {
            tiledCharacterSortingOrder = maxLayerOrder + 1;
        }
    }

    private void CheckDoorTrigger()
    {
        if (playerTransform == null || tiledDoorTiles.Count == 0)
        {
            return;
        }

        if (Time.time < doorTriggerCooldownUntil)
        {
            return;
        }

        var footPosition = GetPlayerFootWorldPoint();
        var tileCoord = WorldToTileCoord(footPosition, tiledMapTileScale);
        if (!tiledDoorTiles.TryGetValue(tileCoord, out var door))
        {
            lastDoorTile = null;
            return;
        }

        if (lastDoorTile.HasValue && lastDoorTile.Value == tileCoord)
        {
            return;
        }

        lastDoorTile = tileCoord;
        doorTriggerCooldownUntil = Time.time + DoorTriggerCooldownSeconds;

        if (door.proceduralWorldTrigger)
        {
            TransitionToProceduralWorld(door.prefabsFile);
            return;
        }

        if (door.isExit)
        {
            if (!string.IsNullOrWhiteSpace(previousTmxName))
            {
                LoadTiledMap(previousTmxName, door.doorId, true, true);
            }
            return;
        }

        if (!string.IsNullOrWhiteSpace(door.interior))
        {
            previousTmxName = currentTmxName;
            LoadTiledMap(door.interior, door.doorId, true, true);
        }
    }

    public bool CanMoveTo(Vector3 worldPosition)
    {
        if (!isTiledMapActive)
        {
            return CanMoveToProcedural(worldPosition);
        }

        if (tiledCollisionTiles.Count == 0)
        {
            return true;
        }

        return CanMoveToTiled(worldPosition);
    }

    private bool CanMoveToProcedural(Vector3 worldPosition)
    {
        var collider = playerCollider != null ? playerCollider : playerTransform != null ? playerTransform.GetComponent<BoxCollider2D>() : null;
        if (collider == null)
        {
            return true;
        }

        if (!EnsureProceduralBoundsForPosition(worldPosition))
        {
            return false;
        }

        var scale = collider.transform.lossyScale;
        var size = new Vector2(Mathf.Abs(scale.x) * collider.size.x, Mathf.Abs(scale.y) * collider.size.y);
        var offset = new Vector2(collider.offset.x * scale.x, collider.offset.y * scale.y);
        var center = (Vector2)worldPosition + offset;

        var hits = Physics2D.OverlapBoxAll(center, size, 0f);
        if (hits == null || hits.Length == 0)
        {
            return true;
        }

        for (var i = 0; i < hits.Length; i++)
        {
            var hit = hits[i];
            if (hit == null || hit == collider || hit.isTrigger)
            {
                continue;
            }

            if (hit.transform == collider.transform || hit.transform.IsChildOf(collider.transform))
            {
                continue;
            }

            if (TryOpenChestFromHit(hit))
            {
                return false;
            }

            if (TryInteractCompanionFromHit(hit))
            {
                return false;
            }

            if (TryTriggerEnemyFromHit(hit))
            {
                return false;
            }

            if (Time.time - lastCollisionLogTime > 1f)
            {
                lastCollisionLogTime = Time.time;
                Debug.Log($"[Collision] Procedural blocked by {hit.name} at {center} size {size}");
            }

            return false;
        }

        return true;
    }

    private bool TryOpenChestFromHit(Collider2D hit)
    {
        if (hit == null)
        {
            return false;
        }

        var chest = hit.GetComponentInParent<ChestInstance>();
        if (chest == null)
        {
            return false;
        }

        if (chest.IsOpen)
        {
            return true;
        }

        var ui = FindFirstObjectByType<RuntimeGameUIBootstrap>();
        if (ui == null)
        {
            return true;
        }

        ui.OpenChest(chest);
        return true;
    }

    private bool TryInteractCompanionFromHit(Collider2D hit)
    {
        if (hit == null)
        {
            return false;
        }

        var companion = hit.GetComponentInParent<CompanionInstance>();
        if (companion == null)
        {
            return false;
        }

        var ui = FindFirstObjectByType<RuntimeGameUIBootstrap>();
        if (ui == null)
        {
            return true;
        }

        ui.OpenCompanion(companion);
        return true;
    }

    private bool TryTriggerEnemyFromHit(Collider2D hit)
    {
        if (hit == null)
        {
            return false;
        }

        var enemy = hit.GetComponentInParent<EnemyInstance>();
        if (enemy == null || enemy.InBattle)
        {
            return false;
        }

        var ui = FindFirstObjectByType<RuntimeGameUIBootstrap>();
        if (ui == null)
        {
            return true;
        }

        var enemyGroup = GetNearbyEnemies(enemy);
        for (var i = 0; i < enemyGroup.Count; i++)
        {
            enemyGroup[i].InBattle = true;
        }

        ui.OpenBattle(enemyGroup, enemy);
        return true;
    }

    private List<EnemyInstance> GetNearbyEnemies(EnemyInstance centerEnemy)
    {
        var result = new List<EnemyInstance>();
        if (centerEnemy == null)
        {
            return result;
        }

        var tileScale = GetProceduralTileScale();
        if (tileScale <= 0f)
        {
            tileScale = 1f;
        }

        var radius = tileScale * 2.5f;
        var hits = Physics2D.OverlapCircleAll(centerEnemy.transform.position, radius);
        if (hits == null || hits.Length == 0)
        {
            result.Add(centerEnemy);
            return result;
        }

        var unique = new HashSet<EnemyInstance>();
        foreach (var hit in hits)
        {
            if (hit == null)
            {
                continue;
            }

            var enemy = hit.GetComponentInParent<EnemyInstance>();
            if (enemy == null || enemy.InBattle)
            {
                continue;
            }

            if (unique.Add(enemy))
            {
                result.Add(enemy);
            }
        }

        if (!unique.Contains(centerEnemy))
        {
            result.Add(centerEnemy);
        }

        return result;
    }

    private bool EnsureProceduralBoundsForPosition(Vector3 worldPosition)
    {
        var worldSystem = WorldSystem.Instance;
        if (worldSystem == null || isTiledMapActive)
        {
            return true;
        }

        var tileScale = GetProceduralTileScale();
        if (tileScale <= 0f)
        {
            tileScale = 1f;
        }

        var width = Mathf.Max(1, worldSystem.Config.width);
        var height = Mathf.Max(1, worldSystem.Config.height);
        var blockWorldSizeX = width * tileScale;
        var blockWorldSizeY = height * tileScale;
        if (blockWorldSizeX <= 0f || blockWorldSizeY <= 0f)
        {
            return true;
        }

        var targetCoord = new Vector2Int(
            Mathf.FloorToInt(worldPosition.x / blockWorldSizeX),
            Mathf.FloorToInt(worldPosition.y / blockWorldSizeY));

        if (!proceduralCenterBlock.HasValue || proceduralCenterBlock.Value != targetCoord)
        {
            proceduralCenterBlock = targetCoord;
            RefreshProceduralBlocks(targetCoord);
        }

        return true;
    }

    public bool TryAddCompanionToParty(CompanionInstance companion)
    {
        if (companion == null || companion.Definition == null)
        {
            return false;
        }

        var player = GameState.Instance != null ? GameState.Instance.CurrentSave?.player : null;
        if (player == null)
        {
            return false;
        }

        if (!player.CanAddCompanion())
        {
            return false;
        }

        var animal = new FableForge.Models.Animal
        {
            id = companion.Definition.id,
            name = companion.Definition.name,
            level = companion.Definition.level
        };
        player.AddCompanion(animal);

        SpawnCompanionFollower(companion.Definition, Mathf.Max(0, player.companions.Count - 1));
        Destroy(companion.gameObject);
        return true;
    }

    public void BeginBattleEncounter(List<EnemyInstance> enemies, EnemyInstance primaryEnemy)
    {
        if (enemies == null || enemies.Count == 0 || isInBattle)
        {
            return;
        }

        isInBattle = true;
        battleOriginalPositions.Clear();
        battleFollowers.Clear();

        var tileScale = GetProceduralTileScale();
        if (tileScale <= 0f)
        {
            tileScale = 1f;
        }

        var center = primaryEnemy != null ? primaryEnemy.transform.position : enemies[0].transform.position;
        if (playerTransform != null)
        {
            battleOriginalPositions[playerTransform] = playerTransform.position;
            var battlePosition = center + new Vector3(-2.5f * tileScale, 0f, 0f);
            if (CanMoveTo(battlePosition))
            {
                playerTransform.position = battlePosition;
            }
            else
            {
                var offsets = new[] { new Vector3(0f, 0.5f * tileScale, 0f), new Vector3(0f, -0.5f * tileScale, 0f), new Vector3(0f, tileScale, 0f), new Vector3(0f, -tileScale, 0f), new Vector3(0.5f * tileScale, 0f, 0f), new Vector3(-0.5f * tileScale, 0f, 0f) };
                var moved = false;
                for (var i = 0; i < offsets.Length && !moved; i++)
                {
                    var candidate = battlePosition + offsets[i];
                    if (CanMoveTo(candidate))
                    {
                        playerTransform.position = candidate;
                        moved = true;
                    }
                }
                if (!moved)
                {
                    playerTransform.position = battleOriginalPositions[playerTransform];
                }
            }
        }

        for (var i = 0; i < enemies.Count; i++)
        {
            var enemy = enemies[i];
            if (enemy == null)
            {
                continue;
            }

            battleOriginalPositions[enemy.transform] = enemy.transform.position;
            var offsetY = (-0.6f * tileScale * (i - (enemies.Count - 1) * 0.5f));
            enemy.transform.position = center + new Vector3(2.5f * tileScale, offsetY, 0f);
        }

        if (companionFollowersRoot != null)
        {
            var index = 0;
            foreach (Transform child in companionFollowersRoot)
            {
                if (child == null)
                {
                    continue;
                }

                battleOriginalPositions[child] = child.position;
                child.position = center + new Vector3(-3.5f * tileScale, -0.6f * tileScale * (index + 1), 0f);
                var follower = child.GetComponent<CompanionFollower>();
                if (follower != null)
                {
                    follower.enabled = false;
                    battleFollowers.Add(follower);
                }
                index++;
            }
        }
    }

    public void EndBattleEncounter(List<EnemyInstance> enemies)
    {
        if (!isInBattle)
        {
            return;
        }

        foreach (var entry in battleOriginalPositions)
        {
            if (entry.Key != null)
            {
                entry.Key.position = entry.Value;
            }
        }

        TrySnapPlayerToWalkable();

        for (var i = 0; i < battleFollowers.Count; i++)
        {
            if (battleFollowers[i] != null)
            {
                battleFollowers[i].enabled = true;
            }
        }

        battleFollowers.Clear();
        battleOriginalPositions.Clear();
        if (enemies != null)
        {
            for (var i = 0; i < enemies.Count; i++)
            {
                if (enemies[i] != null)
                {
                    enemies[i].InBattle = false;
                }
            }
        }
        isInBattle = false;
    }

    private void TrySnapPlayerToWalkable()
    {
        if (playerTransform == null || isTiledMapActive)
        {
            return;
        }

        var current = playerTransform.position;
        if (CanMoveTo(current))
        {
            return;
        }

        var tileScale = GetProceduralTileScale();
        if (tileScale <= 0f)
        {
            tileScale = 1f;
        }

        var radii = new[] { 0.5f * tileScale, tileScale, 1.5f * tileScale };
        for (var r = 0; r < radii.Length; r++)
        {
            var radius = radii[r];
            for (var i = 0; i < 8; i++)
            {
                var angle = i * Mathf.PI * 0.25f;
                var offset = new Vector3(Mathf.Cos(angle) * radius, Mathf.Sin(angle) * radius, 0f);
                var candidate = current + offset;
                if (CanMoveTo(candidate))
                {
                    playerTransform.position = candidate;
                    return;
                }
            }
        }
    }

    private void SpawnCompanionFollower(CompanionDefinitionData definition, int index)
    {
        if (definition?.prefab == null || playerTransform == null)
        {
            return;
        }

        var parent = GetCompanionFollowersRoot();
        var tileScale = GetProceduralTileScale();
        var root = CreatePrefabAtTile(parent, definition.prefab, Vector2Int.zero, WorldSystem.Instance?.Config.seed ?? 0, tileScale, ResolvePlayerSortingOrder() - 1);
        if (root == null)
        {
            return;
        }

        root.name = $"{definition.id}_Follower";
        root.transform.position = playerTransform.position;
        var collider = root.GetComponent<Collider2D>();
        if (collider != null)
        {
            Destroy(collider);
        }

        var follower = root.AddComponent<CompanionFollower>();
        follower.target = playerTransform;
        follower.offset = new Vector3(-0.6f * (index + 1), -0.4f * (index + 1), 0f);
    }

    private Transform GetCompanionFollowersRoot()
    {
        if (companionFollowersRoot != null)
        {
            return companionFollowersRoot;
        }

        var root = new GameObject("CompanionFollowers");
        root.transform.SetParent(transform, false);
        companionFollowersRoot = root.transform;
        return companionFollowersRoot;
    }

    private Vector3 GetPlayerFootWorldPoint()
    {
        if (playerTransform == null)
        {
            return Vector3.zero;
        }

        var collider = playerCollider != null ? playerCollider : playerTransform.GetComponent<BoxCollider2D>();
        if (collider == null)
        {
            return playerTransform.position;
        }

        var localExtents = collider.size * 0.5f;
        var insetY = localExtents.y * 0.1f;
        var localFoot = new Vector3(collider.offset.x, collider.offset.y - localExtents.y + insetY, 0f);
        return collider.transform.TransformPoint(localFoot);
    }

    private bool CanMoveToTiled(Vector3 worldPosition)
    {
        if (playerTransform != null)
        {
            var collider = playerCollider != null ? playerCollider : playerTransform.GetComponent<BoxCollider2D>();
            if (collider != null)
            {
                playerCollider = collider;
            }
            else
            {
                EnsurePlayerCollider(playerTransform.gameObject);
                collider = playerCollider != null ? playerCollider : playerTransform.GetComponent<BoxCollider2D>();
            }
            if (collider != null)
            {
                var delta = worldPosition - playerTransform.position;
                var localExtents = collider.size * 0.5f;
                var insetX = localExtents.x * 0.1f;
                var insetY = localExtents.y * 0.1f;
                var localY = collider.offset.y - localExtents.y + insetY;
                var localLeft = collider.offset.x - localExtents.x + insetX;
                var localRight = collider.offset.x + localExtents.x - insetX;
                var localCenterX = collider.offset.x;
                var transform = collider.transform;

                var samplePoints = new[]
                {
                    transform.TransformPoint(new Vector3(localLeft, localY, 0f)) + delta,
                    transform.TransformPoint(new Vector3(localRight, localY, 0f)) + delta,
                    transform.TransformPoint(new Vector3(localCenterX, localY, 0f)) + delta
                };

                for (var i = 0; i < samplePoints.Length; i++)
                {
                    var tileCoord = WorldToTileCoord(samplePoints[i], tiledMapTileScale);
                    if (tiledCollisionTiles.Contains(tileCoord) && !tiledDoorTiles.ContainsKey(tileCoord))
                    {
                        if (Time.time - lastCollisionLogTime > 1f)
                        {
                            lastCollisionLogTime = Time.time;
                            Debug.Log($"[Collision] Blocked at tile {tileCoord} sample {samplePoints[i]} colliderCenter {collider.bounds.center} size {collider.size} offset {collider.offset} owner {collider.gameObject.name}");
                        }
                        return false;
                    }
                }

                return true;
            }
        }

        var fallbackOffsets = BuildRadiusOffsets();
        for (var i = 0; i < fallbackOffsets.Length; i++)
        {
            var sample = worldPosition + fallbackOffsets[i];
            var tileCoord = WorldToTileCoord(sample, tiledMapTileScale);
            if (tiledCollisionTiles.Contains(tileCoord) && !tiledDoorTiles.ContainsKey(tileCoord))
            {
                return false;
            }
        }

        return true;
    }

    private Vector3[] BuildRadiusOffsets()
    {
        var radius = Mathf.Max(0.1f, tiledMapTileScale * 0.35f);
        return new[]
        {
            new Vector3(-radius, -radius, 0f),
            new Vector3(radius, -radius, 0f),
            new Vector3(-radius, radius, 0f),
            new Vector3(radius, radius, 0f)
        };
    }

    private void TransitionToProceduralWorld(string prefabsFile)
    {
        var worldSystem = WorldSystem.Instance;
        if (worldSystem == null)
        {
            return;
        }

        var targetPrefab = string.IsNullOrWhiteSpace(prefabsFile) ? "prefabs_grassland" : prefabsFile;
        worldSystem.InitializeFromPrefab(targetPrefab, 64, 64);
        isTiledMapActive = false;
        currentTmxName = null;
        tiledDoorTiles.Clear();
        tiledCollisionTiles.Clear();
        ClearWorldVisuals();
        RenderWorldPreview();
        RenderEntityPreview();

        var saveData = GameState.Instance != null ? GameState.Instance.CurrentSave : null;
        if (saveData != null)
        {
            saveData.useProceduralWorld = true;
            saveData.currentMapFileName = null;
            saveData.worldPrefabId = targetPrefab;
        }

        if (playerTransform != null)
        {
            ApplyPlayerScale(playerTransform);
            SetSortingOrder(playerTransform.gameObject, ResolvePlayerSortingOrder());
            EnsurePlayerMovement(playerTransform.gameObject);
            var enter = worldSystem.CurrentPrefabData?.enterConfig;
            var spawnX = enter != null ? enter.x : worldSystem.Config.width / 2;
            var spawnY = enter != null ? enter.y : worldSystem.Config.height / 2;
            var tileScale = GetProceduralTileScale();
            playerTransform.position = new Vector3(spawnX * tileScale, spawnY * tileScale, 0f);
            ConfigureGameplayCamera(tileScale, playerTransform.position);
        }
    }

    private void UpdateSavePlayerSnapshot()
    {
        var gameState = GameState.Instance;
        if (gameState == null || gameState.CurrentSave?.player == null || playerTransform == null)
        {
            return;
        }

        var position = playerTransform.position;
        gameState.CurrentSave.player.position = new Vector2(position.x, position.y);
        gameState.CurrentSave.hasPlayerPosition = true;
    }

    private Vector3? FindDoorSpawnPosition(string doorId, bool preferExitDoor)
    {
        if (string.IsNullOrWhiteSpace(doorId) || tiledDoorTiles.Count == 0)
        {
            return null;
        }

        Vector2Int? candidate = null;
        foreach (var entry in tiledDoorTiles)
        {
            if (!string.Equals(entry.Value.doorId, doorId))
            {
                continue;
            }

            if (preferExitDoor && entry.Value.isExit)
            {
                candidate = entry.Key;
                break;
            }

            if (candidate == null)
            {
                candidate = entry.Key;
            }
        }

        if (candidate == null)
        {
            return null;
        }

        var tile = candidate.Value;
        var spawnTile = new Vector2Int(tile.x, tile.y - 1);
        return TileToWorldCenter(spawnTile, tiledMapTileScale);
    }

    private static Vector2Int WorldToTileCoord(Vector3 worldPosition, float tileScale)
    {
        var scale = Mathf.Max(0.01f, tileScale);
        var tileX = Mathf.FloorToInt(worldPosition.x / scale);
        var tileY = Mathf.FloorToInt(-worldPosition.y / scale);
        return new Vector2Int(tileX, tileY);
    }

    private static Vector3 TileToWorldCenter(Vector2Int tileCoord, float tileScale)
    {
        var scale = Mathf.Max(0.01f, tileScale);
        var worldX = (tileCoord.x + 0.5f) * scale;
        var worldY = (-tileCoord.y - 0.5f) * scale;
        return new Vector3(worldX, worldY, 0f);
    }

    private static bool GetBoolProperty(Dictionary<string, string> properties, string key, bool fallback)
    {
        if (properties == null || !properties.TryGetValue(key, out var value))
        {
            return fallback;
        }

        if (bool.TryParse(value, out var parsedBool))
        {
            return parsedBool;
        }

        if (int.TryParse(value, out var parsedInt))
        {
            return parsedInt != 0;
        }

        return fallback;
    }

    private static float GetFloatProperty(Dictionary<string, string> properties, string key, float fallback)
    {
        if (properties == null || !properties.TryGetValue(key, out var value))
        {
            return fallback;
        }

        return float.TryParse(value, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var parsed)
            ? parsed
            : fallback;
    }

    private static bool TryGetIntProperty(Dictionary<string, string> properties, string key, out int value)
    {
        value = 0;
        if (properties == null || !properties.TryGetValue(key, out var raw) || string.IsNullOrWhiteSpace(raw))
        {
            return false;
        }

        if (int.TryParse(raw, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out value))
        {
            return true;
        }

        if (float.TryParse(raw, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var parsedFloat))
        {
            value = Mathf.RoundToInt(parsedFloat);
            return true;
        }

        return false;
    }

    private static string GetStringProperty(Dictionary<string, string> properties, string key)
    {
        if (properties == null || !properties.TryGetValue(key, out var value))
        {
            return null;
        }

        return value;
    }

    private struct TiledDoorInfo
    {
        public string doorId;
        public string interior;
        public string prefabsFile;
        public bool isExit;
        public bool proceduralWorldTrigger;
        public Vector2Int tile;
    }

    private void RenderEntityPreview()
    {
        var worldSystem = WorldSystem.Instance;
        if (worldSystem == null || worldSystem.Tiles == null)
        {
            return;
        }

        var data = worldSystem.CurrentPrefabData;
        if (data == null || data.entities == null)
        {
            return;
        }

        if (proceduralEntitiesRoot == null)
        {
            proceduralEntitiesRoot = new GameObject("WorldEntities");
        }
        proceduralEntityBlocks.Clear();
    }

    private void SpawnPlayerFromSave()
    {
        var gameState = GameState.Instance;
        var worldSystem = WorldSystem.Instance;
        if (gameState == null || worldSystem == null)
        {
            return;
        }

        if (GameObject.Find("PlayerCharacter") != null)
        {
            return;
        }

        var enter = worldSystem.CurrentPrefabData?.enterConfig;
        var spawnX = enter != null ? enter.x : worldSystem.Config.width / 2;
        var spawnY = enter != null ? enter.y : worldSystem.Config.height / 2;
        Vector3 spawnPosition;
        if (isTiledMapActive)
        {
            spawnPosition = tiledSpawnTile.HasValue
                ? TileToWorldCenter(tiledSpawnTile.Value, tiledMapTileScale)
                : new Vector3(tiledMapCenter.x, tiledMapCenter.y, 0f);
        }
        else
        {
            var scale = GetProceduralTileScale();
            spawnPosition = new Vector3(spawnX * scale, spawnY * scale, 0f);
        }

        if (gameState.CurrentSave != null && gameState.CurrentSave.hasPlayerPosition && gameState.CurrentSave.player != null)
        {
            var saved = gameState.CurrentSave.player.position;
            spawnPosition = new Vector3(saved.x, saved.y, 0f);
        }

        var prefab = Resources.Load<GameObject>("CharacterRigs/DefaultPreviewRig");
        GameObject playerObject;
        if (prefab != null)
        {
            playerObject = Instantiate(prefab, spawnPosition, Quaternion.identity);
            playerObject.name = "PlayerCharacter";
            var customizer = playerObject.GetComponent<CharacterCustomizer>();
            if (customizer == null)
            {
                customizer = playerObject.AddComponent<CharacterCustomizer>();
            }

            var presetJson = gameState.CurrentSave?.character?.presetJson;
            if (!string.IsNullOrWhiteSpace(presetJson))
            {
                var preset = CharacterPreset.FromJson(presetJson);
                if (preset != null)
                {
                    customizer.ApplyPreset(preset);
                }
            }
        }
        else
        {
            playerObject = PrefabFactory.CreateMarker("PlayerCharacter", spawnPosition, new Color(1f, 1f, 1f, 1f), 1f, 5);
        }

        if (playerBaseScale == Vector3.one)
        {
            playerBaseScale = playerObject.transform.localScale;
        }
        ApplyPlayerScale(playerObject.transform);
        playerTransform = playerObject.transform;

        ApplyGameplayLayer(playerObject);
        SetSortingOrder(playerObject, ResolvePlayerSortingOrder());
        EnsurePlayerMovement(playerObject);
        EnsurePlayerCollider(playerObject);
        LogColliderState();
        var cameraScale = isTiledMapActive ? tiledMapTileScale : GetProceduralTileScale();
        ConfigureGameplayCamera(cameraScale, playerObject.transform.position);
        EnsureCameraFollow(playerObject.transform);

        if (gameState.CurrentSave?.player != null && !gameState.CurrentSave.hasPlayerPosition)
        {
            gameState.CurrentSave.player.position = new Vector2(spawnPosition.x, spawnPosition.y);
            gameState.CurrentSave.hasPlayerPosition = true;
        }
    }

    private void ConfigureGameplayCamera(float tileScale, Vector3 focusPosition)
    {
        var camera = Camera.main;
        if (camera == null)
        {
            return;
        }

        camera.orthographic = true;
        camera.clearFlags = CameraClearFlags.SolidColor;
        camera.backgroundColor = new Color(0.08f, 0.08f, 0.1f, 1f);
        camera.cullingMask = ~0;
        var targetSize = Mathf.Max(8f, (targetTilesOnScreenY * tileScale) * 0.5f);
        camera.orthographicSize = targetSize;
        camera.transform.position = new Vector3(focusPosition.x, focusPosition.y, -10f);
    }

    private void EnsureCameraFollow(Transform target)
    {
        var camera = Camera.main;
        if (camera == null)
        {
            return;
        }

        var follow = camera.GetComponent<CameraFollow>();
        if (follow == null)
        {
            follow = camera.gameObject.AddComponent<CameraFollow>();
        }

        follow.SetTarget(target);
    }

    private void EnsurePlayerMovement(GameObject playerObject)
    {
        if (playerObject == null)
        {
            return;
        }

        var movement = playerObject.GetComponent<PlayerMovementController>();
        if (movement == null)
        {
            movement = playerObject.AddComponent<PlayerMovementController>();
        }

        var scale = isTiledMapActive ? tiledMapTileScale : GetProceduralTileScale();
        movement.SetTileScale(scale);
    }

    private void EnsurePlayerCollider(GameObject playerObject)
    {
        if (playerObject == null)
        {
            return;
        }

        playerTransform = playerObject.transform;
        loggedColliderState = false;
        Debug.LogWarning("[Collision] EnsurePlayerCollider called.");

        var existingCollider = playerObject.GetComponent<BoxCollider2D>();
        if (existingCollider != null)
        {
            playerCollider = existingCollider;
        }

        AuditAndCleanupColliders(true);

        var collider = playerObject.GetComponent<BoxCollider2D>();
        if (collider == null)
        {
            collider = playerObject.AddComponent<BoxCollider2D>();
        }
        if (collider == null)
        {
            Debug.LogError("[Collision] Failed to create BoxCollider2D on player.");
            return;
        }

        var spriteRenderer = GetLargestSpriteRenderer(playerObject);
        var colliderSize = new Vector2(0.35f, 0.4f);
        var colliderOffset = new Vector2(0f, -0.25f + playerColliderYOffset);
        if (spriteRenderer != null)
        {
            var bounds = spriteRenderer.bounds;
            var kneeHeightWorld = bounds.size.y * playerColliderHeightFactor;
            var widthWorld = bounds.size.x * playerColliderWidthFactor;
            var worldFootCenter = new Vector3(bounds.center.x, bounds.min.y + (kneeHeightWorld * 0.5f), bounds.center.z);

            var rootTransform = playerObject.transform;
            var localCenter = rootTransform.InverseTransformPoint(worldFootCenter);
            var scale = rootTransform.lossyScale;
            var scaleX = Mathf.Abs(scale.x) > 0.001f ? Mathf.Abs(scale.x) : 1f;
            var scaleY = Mathf.Abs(scale.y) > 0.001f ? Mathf.Abs(scale.y) : 1f;
            colliderSize = new Vector2(widthWorld / scaleX, kneeHeightWorld / scaleY);
            colliderOffset = new Vector2(localCenter.x, localCenter.y + playerColliderYOffset);
        }

        collider.size = colliderSize;
        collider.offset = colliderOffset;
        playerCollider = collider;

        RefreshPlayerColliderOutline();

        if (!loggedColliderState)
        {
            loggedColliderState = true;
            Debug.Log($"[Collision] Player collider set on {playerObject.name} size {collider.size} offset {collider.offset}");
            var all2D = playerObject.GetComponentsInChildren<Collider2D>(true);
            foreach (var extra in all2D)
            {
                if (extra == null)
                {
                    continue;
                }
                Debug.Log($"[Collision] Collider2D found on {extra.gameObject.name} type {extra.GetType().Name} size {GetColliderSize(extra)} offset {GetColliderOffset(extra)}");
            }
            var all3D = playerObject.GetComponentsInChildren<Collider>(true);
            foreach (var extra in all3D)
            {
                if (extra == null)
                {
                    continue;
                }
                Debug.Log($"[Collision] Collider3D found on {extra.gameObject.name} type {extra.GetType().Name}");
            }
        }
    }

    private void AuditAndCleanupColliders(bool verbose)
    {
        if (playerTransform == null)
        {
            return;
        }

        var root = playerTransform.gameObject;
        var extraColliders2D = root.GetComponentsInChildren<Collider2D>(true);
        foreach (var extra in extraColliders2D)
        {
            if (extra == null || extra == playerCollider)
            {
                continue;
            }

            if (verbose)
            {
                Debug.Log($"[Collision] Removing Collider2D on {extra.gameObject.name} type {extra.GetType().Name}");
            }
            Destroy(extra);
        }

        var extraColliders3D = root.GetComponentsInChildren<Collider>(true);
        foreach (var extra in extraColliders3D)
        {
            if (extra == null)
            {
                continue;
            }

            if (verbose)
            {
                Debug.Log($"[Collision] Removing Collider3D on {extra.gameObject.name} type {extra.GetType().Name}");
            }
            Destroy(extra);
        }

        var rigidbody2D = root.GetComponentsInChildren<Rigidbody2D>(true);
        foreach (var body in rigidbody2D)
        {
            if (body != null)
            {
                Destroy(body);
            }
        }

        var rigidbody3D = root.GetComponentsInChildren<Rigidbody>(true);
        foreach (var body in rigidbody3D)
        {
            if (body != null)
            {
                Destroy(body);
            }
        }
    }

    private void LogColliderState()
    {
        if (playerTransform == null)
        {
            Debug.LogWarning("[Collision] No playerTransform yet.");
            return;
        }

        var root = playerTransform.gameObject;
        var colliders2D = root.GetComponentsInChildren<Collider2D>(true);
        Debug.LogWarning($"[Collision] Collider audit: {colliders2D.Length} Collider2D on {root.name}");
        foreach (var col in colliders2D)
        {
            if (col == null)
            {
                continue;
            }
            Debug.LogWarning($"[Collision] Collider2D {col.GetType().Name} on {col.gameObject.name} size {GetColliderSize(col)} offset {GetColliderOffset(col)}");
        }
    }

    private Vector2 GetColliderSize(Collider2D collider)
    {
        if (collider is BoxCollider2D box)
        {
            return box.size;
        }
        if (collider is CapsuleCollider2D capsule)
        {
            return capsule.size;
        }
        if (collider is CircleCollider2D circle)
        {
            return new Vector2(circle.radius * 2f, circle.radius * 2f);
        }
        return Vector2.zero;
    }

    private Vector2 GetColliderOffset(Collider2D collider)
    {
        if (collider is BoxCollider2D box)
        {
            return box.offset;
        }
        if (collider is CapsuleCollider2D capsule)
        {
            return capsule.offset;
        }
        if (collider is CircleCollider2D circle)
        {
            return circle.offset;
        }
        return Vector2.zero;
    }

    private SpriteRenderer GetLargestSpriteRenderer(GameObject playerObject)
    {
        if (playerObject == null)
        {
            return null;
        }

        SpriteRenderer best = null;
        var bestArea = 0f;
        var renderers = playerObject.GetComponentsInChildren<SpriteRenderer>(true);
        foreach (var renderer in renderers)
        {
            if (renderer == null || renderer.sprite == null)
            {
                continue;
            }

            var bounds = renderer.sprite.bounds;
            var area = bounds.size.x * bounds.size.y;
            if (area > bestArea)
            {
                bestArea = area;
                best = renderer;
            }
        }

        return best;
    }

    private void RefreshPlayerColliderOutline()
    {
        if (!showPlayerColliderOutline || playerTransform == null)
        {
            return;
        }

        var collider = playerCollider != null ? playerCollider : playerTransform.GetComponent<BoxCollider2D>();
        if (collider == null)
        {
            return;
        }

        playerCollider = collider;
        var spriteRenderer = GetLargestSpriteRenderer(playerTransform.gameObject);
        EnsureColliderOutline(collider, spriteRenderer);
    }

    private void EnsureColliderOutline(BoxCollider2D collider, SpriteRenderer spriteRenderer)
    {
        if (collider == null)
        {
            return;
        }

        var ownerTransform = collider.transform;
        if (ownerTransform == null)
        {
            return;
        }

        var existing = ownerTransform.Find("ColliderOutline");
        if (existing != null)
        {
            Destroy(existing.gameObject);
        }

        var outlineObject = new GameObject("ColliderOutline");
        outlineObject.transform.SetParent(ownerTransform, false);
        outlineObject.transform.localPosition = collider.offset;
        outlineObject.transform.localRotation = Quaternion.identity;
        outlineObject.transform.localScale = Vector3.one;

        var lineRenderer = outlineObject.AddComponent<LineRenderer>();
        lineRenderer.material = new Material(Shader.Find("Sprites/Default"));
        lineRenderer.startColor = Color.red;
        lineRenderer.endColor = Color.red;
        lineRenderer.startWidth = 0.05f;
        lineRenderer.endWidth = 0.05f;
        lineRenderer.useWorldSpace = false;
        lineRenderer.loop = true;
        if (spriteRenderer != null)
        {
            lineRenderer.sortingLayerID = spriteRenderer.sortingLayerID;
            lineRenderer.sortingOrder = spriteRenderer.sortingOrder + 50;
        }
        else
        {
            lineRenderer.sortingLayerName = "Default";
            lineRenderer.sortingOrder = 10000;
        }
        lineRenderer.alignment = LineAlignment.View;

        var size = collider.size;
        var halfWidth = size.x * 0.5f;
        var halfHeight = size.y * 0.5f;
        lineRenderer.positionCount = 5;
        lineRenderer.SetPositions(new[]
        {
            new Vector3(-halfWidth, -halfHeight, 0f),
            new Vector3(halfWidth, -halfHeight, 0f),
            new Vector3(halfWidth, halfHeight, 0f),
            new Vector3(-halfWidth, halfHeight, 0f),
            new Vector3(-halfWidth, -halfHeight, 0f)
        });
    }

    private void ApplyGameplayLayer(GameObject target)
    {
        if (target == null)
        {
            return;
        }

        var transforms = target.GetComponentsInChildren<Transform>(true);
        foreach (var child in transforms)
        {
            child.gameObject.layer = 0;
        }
    }

    /// <summary>
    /// Applies base sorting order so the character draws in front of the map, while preserving
    /// relative order of parts (body &lt; bottom &lt; top &lt; hair/face). Without this, all parts
    /// would get the same order and the map could cover the character.
    /// </summary>
    private void SetSortingOrder(GameObject target, int baseOrder)
    {
        PlayerSortingBaseOrder = baseOrder;
        if (target == null)
        {
            return;
        }

        var renderers = target.GetComponentsInChildren<SpriteRenderer>(true);
        if (renderers == null || renderers.Length == 0)
        {
            return;
        }

        int minOrder = int.MaxValue;
        foreach (var r in renderers)
        {
            if (r != null && r.sortingOrder < minOrder)
                minOrder = r.sortingOrder;
        }
        foreach (var renderer in renderers)
        {
            if (renderer != null)
                renderer.sortingOrder = baseOrder + (renderer.sortingOrder - minOrder);
        }
    }

    private void PlaceDensityEntities(Transform parent, WorldSystem worldSystem, float density, List<string> blocked, Color color, string name, System.Random random, int sortingOrder)
    {
        if (density <= 0f)
        {
            return;
        }

        var width = worldSystem.Tiles.GetLength(0);
        var height = worldSystem.Tiles.GetLength(1);
        var total = width * height;
        var count = Mathf.Clamp(Mathf.RoundToInt(total * density), 0, total);
        PlaceCountEntities(parent, worldSystem, count, blocked, color, name, random, sortingOrder);
    }

    private void PlaceCountEntities(Transform parent, WorldSystem worldSystem, int count, List<string> blocked, Color color, string name, System.Random random, int sortingOrder)
    {
        if (count <= 0)
        {
            return;
        }

        var width = worldSystem.Tiles.GetLength(0);
        var height = worldSystem.Tiles.GetLength(1);
        var attempts = 0;
        var placed = 0;
        var maxAttempts = count * 10;

        while (placed < count && attempts < maxAttempts)
        {
            attempts++;
            var x = random.Next(0, width);
            var y = random.Next(0, height);
            var terrain = worldSystem.Tiles[x, y];
            if (IsBlocked(terrain, blocked))
            {
                continue;
            }

            var marker = PrefabFactory.CreateMarker(name, new Vector3(x, y, 0f), color, 1f, sortingOrder);
            marker.transform.SetParent(parent, true);
            placed++;
        }
    }

    private bool IsBlocked(int terrain, List<string> blocked)
    {
        if (blocked == null || blocked.Count == 0)
        {
            return false;
        }

        var terrainName = terrain switch
        {
            0 => "water",
            1 => "grass",
            2 => "dirt",
            _ => "stone"
        };

        return blocked.Contains(terrainName);
    }
}
