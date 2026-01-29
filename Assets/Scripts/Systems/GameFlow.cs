using System.Collections.Generic;
using FableForge.Models;
using FableForge.Systems;
using UnityEngine;

public static class GameFlow
{
    private const int MaxSaveSlotsPerCharacter = 5;

    public static void StartNewGame(GameCharacter character)
    {
        var characterData = CharacterCreationDataLoader.LoadFromResources();
        var raceId = character != null ? character.race.ToString().ToLowerInvariant() : "human";
        var raceDefinition = characterData != null ? characterData.GetRaceById(raceId) : null;
        var baseHitPoints = raceDefinition != null ? Mathf.Max(1, raceDefinition.baseHitPoints) : 10;
        var baseMana = raceDefinition != null ? Mathf.Max(0, raceDefinition.baseMana) : 0;
        var baseEnergy = raceDefinition != null ? Mathf.Max(0, raceDefinition.baseEnergy) : 0;
        var baseRage = raceDefinition != null ? Mathf.Max(0, raceDefinition.baseRage) : 0;

        var player = new Player
        {
            name = character.name,
            characterClass = character.characterClass,
            abilityScores = new FableForge.Models.AbilityScores
            {
                strength = 10,
                dexterity = 10,
                constitution = 10,
                intelligence = 10,
                wisdom = 10,
                charisma = 10
            },
            attributePoints = 0,
            hitPoints = baseHitPoints,
            maxHitPoints = baseHitPoints,
            mana = baseMana,
            maxMana = baseMana,
            energy = baseEnergy,
            maxEnergy = baseEnergy,
            rage = baseRage,
            maxRage = baseRage,
            skills = new List<SkillProficiency>()
        };

        var saveData = new SaveData
        {
            player = player,
            character = character,
            worldSeed = System.Guid.NewGuid().ToString(),
            savedAtUnix = System.DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
            worldPrefabId = "prefabs_grassland",
            currentMapFileName = "church",
            useProceduralWorld = false,
            hasPlayerPosition = false
        };

        var characterIndex = PlayerPrefs.GetInt("FableForge_SelectedCharacter", 0);
        var saveSlotIndex = PlayerPrefs.GetInt("FableForge_SelectedSaveSlot", 0);
        var slotIndex = characterIndex * MaxSaveSlotsPerCharacter + saveSlotIndex;
        SaveManager.SaveSlot(slotIndex, saveData);
        LaunchGame(saveData);
    }

    public static void ContinueGame(int slotIndex)
    {
        var saveData = SaveManager.LoadSlot(slotIndex);
        if (saveData == null)
        {
            Debug.LogWarning($"No save data found for slot {slotIndex}.");
            return;
        }

        LaunchGame(saveData);
    }

    private static void LaunchGame(SaveData saveData)
    {
        var gameState = Object.FindFirstObjectByType<GameState>();
        if (gameState == null)
        {
            gameState = new GameObject("GameState").AddComponent<GameState>();
        }

        gameState.SetSave(saveData);

        if (Object.FindFirstObjectByType<GameSceneController>() == null)
        {
            new GameObject("GameSceneController").AddComponent<GameSceneController>();
        }

        var startScreen = Object.FindFirstObjectByType<StartScreenController>();
        if (startScreen != null)
        {
            Object.Destroy(startScreen.gameObject);
        }

        var characterCreation = Object.FindFirstObjectByType<CharacterCreationBootstrap>();
        if (characterCreation != null)
        {
            Object.Destroy(characterCreation.gameObject);
        }
    }
}
