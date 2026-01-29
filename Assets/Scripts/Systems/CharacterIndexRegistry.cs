using System.Collections.Generic;
using System.Linq;
using UnityEngine;

public static class CharacterIndexRegistry
{
    private const string CharacterKeyPrefix = "FableForge_Character_";
    private const string CharacterListKey = "FableForge_Character_Indices";
    private const int ScanLimit = 200;

    public static int Count => GetIndices().Count;

    public static List<int> GetIndices()
    {
        var raw = PlayerPrefs.GetString(CharacterListKey, string.Empty);
        var list = ParseIndices(raw);

        if (list.Count == 0)
        {
            for (var i = 0; i < ScanLimit; i++)
            {
                if (PlayerPrefs.HasKey($"{CharacterKeyPrefix}{i}_Name"))
                {
                    list.Add(i);
                }
            }

            if (list.Count > 0)
            {
                SaveIndices(list);
            }
        }
        else
        {
            var cleaned = list.Where(index => PlayerPrefs.HasKey($"{CharacterKeyPrefix}{index}_Name")).Distinct().OrderBy(index => index).ToList();
            if (!Enumerable.SequenceEqual(list, cleaned))
            {
                SaveIndices(cleaned);
                list = cleaned;
            }
        }

        return list;
    }

    public static int GetNextAvailableIndex()
    {
        var list = GetIndices();
        return list.Count == 0 ? 0 : list[list.Count - 1] + 1;
    }

    public static void Register(int index)
    {
        var list = GetIndices();
        if (list.Contains(index))
        {
            return;
        }

        list.Add(index);
        SaveIndices(list);
    }

    public static void Remove(int index)
    {
        var list = GetIndices();
        if (list.Remove(index))
        {
            SaveIndices(list);
        }
    }

    private static List<int> ParseIndices(string raw)
    {
        var list = new List<int>();
        if (string.IsNullOrWhiteSpace(raw))
        {
            return list;
        }

        var parts = raw.Split(',');
        foreach (var part in parts)
        {
            if (int.TryParse(part, out var value))
            {
                list.Add(value);
            }
        }

        return list.Distinct().OrderBy(index => index).ToList();
    }

    private static void SaveIndices(List<int> indices)
    {
        indices.Sort();
        var raw = string.Join(",", indices);
        PlayerPrefs.SetString(CharacterListKey, raw);
        PlayerPrefs.Save();
    }
}
