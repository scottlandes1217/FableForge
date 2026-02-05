using System;
using System.Collections.Generic;
using FableForge.Models;
using FableForge.Systems;
using UnityEngine;

public class ChestInstance : MonoBehaviour
{
    private static Dictionary<string, ItemDefinitionData> cachedItemDefinitions;
    private static float nextDefinitionRefreshTime;

    [SerializeField] private string chestId;
    private PrefabDefinition prefabDefinition;
    private readonly List<Item> items = new List<Item>();
    private bool lootGenerated;
    private bool isOpen;

    public string ChestId => chestId;
    public IReadOnlyList<Item> Items => items;
    public bool IsOpen => isOpen;
    public string DisplayName => prefabDefinition != null && !string.IsNullOrWhiteSpace(prefabDefinition.name)
        ? prefabDefinition.name
        : chestId;

    public void Initialize(PrefabDefinition prefab)
    {
        prefabDefinition = prefab;
        chestId = prefab?.id;
        EnsureLootGenerated();
    }

    public void SetOpen(bool open)
    {
        isOpen = open;
    }

    public bool TryTakeItem(Item item)
    {
        if (item == null)
        {
            return false;
        }

        return items.Remove(item);
    }

    public Item TryTakeItemById(string itemId)
    {
        if (string.IsNullOrWhiteSpace(itemId))
        {
            return null;
        }

        for (var i = 0; i < items.Count; i++)
        {
            if (items[i] != null && string.Equals(items[i].id, itemId, StringComparison.OrdinalIgnoreCase))
            {
                var taken = items[i];
                items.RemoveAt(i);
                return taken;
            }
        }

        return null;
    }

    public Item TakeAllById(string itemId)
    {
        if (string.IsNullOrWhiteSpace(itemId))
        {
            return null;
        }

        Item first = null;
        var totalCount = 0;
        for (var i = items.Count - 1; i >= 0; i--)
        {
            var entry = items[i];
            if (entry == null || !string.Equals(entry.id, itemId, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (first == null)
            {
                first = entry;
            }

            totalCount += Mathf.Max(1, entry.quantity);
            items.RemoveAt(i);
        }

        if (first != null)
        {
            first.quantity = Mathf.Max(1, totalCount);
        }

        return first;
    }

    public void TakeAll(List<Item> target)
    {
        if (target == null)
        {
            return;
        }

        target.AddRange(items);
        items.Clear();
    }

    private void EnsureLootGenerated()
    {
        if (lootGenerated)
        {
            return;
        }

        lootGenerated = true;
        items.Clear();

        if (prefabDefinition == null)
        {
            return;
        }

        var itemDefinitions = GetItemDefinitions();
        AddFixedItems(itemDefinitions);
        AddLootTableItems(itemDefinitions);
        AddRandomItems(itemDefinitions);

        if (items.Count == 0)
        {
            EnsureFallbackItem(itemDefinitions);
        }

        Debug.Log($"[Chest] {chestId} loot generated: {items.Count} items (fixed {prefabDefinition?.fixedItems?.Count ?? 0}, table {prefabDefinition?.lootTable?.Count ?? 0})");
    }

    private void AddFixedItems(Dictionary<string, ItemDefinitionData> definitions)
    {
        if (prefabDefinition.fixedItems == null)
        {
            return;
        }

        foreach (var entry in prefabDefinition.fixedItems)
        {
            var quantity = Mathf.Max(1, entry.quantity);
            for (var i = 0; i < quantity; i++)
            {
                var item = CreateItem(entry.itemId, definitions);
                if (item != null)
                {
                    items.Add(item);
                }
            }
        }
    }

    private void AddLootTableItems(Dictionary<string, ItemDefinitionData> definitions)
    {
        if (prefabDefinition.lootTable == null)
        {
            return;
        }

        foreach (var entry in prefabDefinition.lootTable)
        {
            if (entry == null || string.IsNullOrWhiteSpace(entry.itemId))
            {
                continue;
            }

            if (UnityEngine.Random.value > entry.dropRate)
            {
                continue;
            }

            var quantity = GetQuantity(entry.minQuantity, entry.maxQuantity);
            for (var i = 0; i < quantity; i++)
            {
                var item = CreateItem(entry.itemId, definitions);
                if (item != null)
                {
                    items.Add(item);
                }
            }
        }
    }

    private void AddRandomItems(Dictionary<string, ItemDefinitionData> definitions)
    {
        if (prefabDefinition.randomItems == null || definitions == null || definitions.Count == 0)
        {
            return;
        }

        var candidates = new List<ItemDefinitionData>();
        var typesFilter = prefabDefinition.randomItems.types ?? new List<string>();
        var categoriesFilter = prefabDefinition.randomItems.categories ?? new List<string>();
        var excludeIds = prefabDefinition.randomItems.excludeItemIds ?? new List<string>();

        foreach (var definition in definitions.Values)
        {
            if (definition == null)
            {
                continue;
            }

            if (excludeIds.Count > 0 && excludeIds.Exists(id => string.Equals(id, definition.id, StringComparison.OrdinalIgnoreCase)))
            {
                continue;
            }

            if (categoriesFilter.Count > 0 || typesFilter.Count > 0)
            {
                var matchesType = false;
                for (var i = 0; i < categoriesFilter.Count && !matchesType; i++)
                {
                    if (string.Equals(definition.type, categoriesFilter[i], StringComparison.OrdinalIgnoreCase))
                        matchesType = true;
                }
                for (var i = 0; i < typesFilter.Count && !matchesType; i++)
                {
                    if (string.Equals(definition.type, typesFilter[i], StringComparison.OrdinalIgnoreCase))
                        matchesType = true;
                }
                if (!matchesType)
                {
                    continue;
                }
            }

            if (prefabDefinition.randomItems.minValue > 0 || prefabDefinition.randomItems.maxValue > 0)
            {
                if (definition.value < prefabDefinition.randomItems.minValue ||
                    (prefabDefinition.randomItems.maxValue > 0 && definition.value > prefabDefinition.randomItems.maxValue))
                {
                    continue;
                }
            }

            candidates.Add(definition);
        }

        if (candidates.Count == 0)
        {
            Debug.Log($"[Chest] {chestId} randomItems had no candidates.");
            return;
        }

        var count = ParseRangeCount(prefabDefinition.randomItems.count);
        for (var i = 0; i < count; i++)
        {
            var definition = candidates[UnityEngine.Random.Range(0, candidates.Count)];
            var item = CreateItem(definition.id, definitions);
            if (item != null)
            {
                items.Add(item);
            }
        }
    }

    private void EnsureFallbackItem(Dictionary<string, ItemDefinitionData> definitions)
    {
        if (prefabDefinition == null)
        {
            return;
        }

        if (prefabDefinition.fixedItems != null && prefabDefinition.fixedItems.Count > 0)
        {
            var fallback = CreateItem(prefabDefinition.fixedItems[0].itemId, definitions);
            if (fallback != null)
            {
                items.Add(fallback);
                return;
            }
        }

        if (prefabDefinition.lootTable != null && prefabDefinition.lootTable.Count > 0)
        {
            var fallback = CreateItem(prefabDefinition.lootTable[0].itemId, definitions);
            if (fallback != null)
            {
                items.Add(fallback);
                return;
            }
        }

        if (definitions != null && definitions.Count > 0)
        {
            foreach (var definition in definitions.Values)
            {
                if (definition == null || string.IsNullOrWhiteSpace(definition.id))
                {
                    continue;
                }
                var fallback = CreateItem(definition.id, definitions);
                if (fallback != null)
                {
                    items.Add(fallback);
                    return;
                }
            }
        }
    }

    private static int ParseRangeCount(string count)
    {
        if (string.IsNullOrWhiteSpace(count))
        {
            return 0;
        }

        var parts = count.Split('-', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 1 && int.TryParse(parts[0], out var single))
        {
            return Mathf.Max(0, single);
        }

        if (parts.Length >= 2
            && int.TryParse(parts[0], out var min)
            && int.TryParse(parts[1], out var max))
        {
            return UnityEngine.Random.Range(Mathf.Min(min, max), Mathf.Max(min, max) + 1);
        }

        return 0;
    }

    private static int GetQuantity(int min, int max)
    {
        min = Mathf.Max(1, min);
        max = Mathf.Max(min, max);
        return UnityEngine.Random.Range(min, max + 1);
    }

    private static Item CreateItem(string itemId, Dictionary<string, ItemDefinitionData> definitions)
    {
        if (string.IsNullOrWhiteSpace(itemId))
        {
            return null;
        }

        if (definitions != null && definitions.TryGetValue(itemId, out var definition) && definition != null)
        {
            return new Item
            {
                id = definition.id,
                name = definition.name,
                description = definition.description,
                value = definition.value
            };
        }

        return new Item
        {
            id = itemId,
            name = itemId,
            description = string.Empty,
            value = 0
        };
    }

    private static Dictionary<string, ItemDefinitionData> GetItemDefinitions()
    {
        if (Application.isEditor && Time.realtimeSinceStartup >= nextDefinitionRefreshTime)
        {
            cachedItemDefinitions = null;
            nextDefinitionRefreshTime = Time.realtimeSinceStartup + 0.5f;
        }

        if (cachedItemDefinitions != null)
        {
            return cachedItemDefinitions;
        }

        cachedItemDefinitions = WorldPrefabLoader.LoadItemDefinitions();
        if (cachedItemDefinitions == null || cachedItemDefinitions.Count == 0)
        {
            Debug.LogWarning("[Chest] Item definitions not found or empty.");
        }
        return cachedItemDefinitions;
    }
}
