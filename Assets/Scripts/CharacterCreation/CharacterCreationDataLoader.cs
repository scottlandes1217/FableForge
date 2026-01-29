using System;
using System.Collections.Generic;
using UnityEngine;

public static class CharacterCreationDataLoader
{
    private const string RacesResourcePath = "Prefabs/Character/races";
    private const string ClassesResourcePath = "Prefabs/Character/classes";

    public static CharacterCreationData LoadFromResources()
    {
        var data = new CharacterCreationData();
        data.Races = LoadListFromResources<RaceList, RaceDefinition>(RacesResourcePath, list => list.races);
        data.Classes = LoadListFromResources<ClassList, ClassDefinition>(ClassesResourcePath, list => list.classes);

        return data;
    }

    private static List<TItem> LoadListFromResources<TList, TItem>(string resourcePath, Func<TList, List<TItem>> selector)
    {
        var asset = Resources.Load<TextAsset>(resourcePath);
        if (asset == null)
        {
            Debug.LogWarning($"Character creation data not found in Resources: {resourcePath}");
            return new List<TItem>();
        }

        var json = asset.text;
        var parsed = JsonUtility.FromJson<TList>(json);
        var result = selector(parsed) ?? new List<TItem>();
        return result;
    }

    [Serializable]
    private class RaceList
    {
        public List<RaceDefinition> races;
    }

    [Serializable]
    private class ClassList
    {
        public List<ClassDefinition> classes;
    }
}
