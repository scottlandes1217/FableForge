using System;
using System.Collections.Generic;
using UnityEngine;
using FableForge.Models;

public class CharacterCreationController : MonoBehaviour
{
    private const int MaxSaveSlotsPerCharacter = 5;
    private const string CharacterKeyPrefix = "FableForge_Character_";
    private const string SaveSlotKeyPrefix = "FableForge_SaveSlot_";
    public enum CreationStep
    {
        RaceSelection,
        Appearance
    }

    public enum Gender
    {
        Male,
        Female,
        Other
    }

    public enum Ability
    {
        Strength,
        Dexterity,
        Constitution,
        Intelligence,
        Wisdom,
        Charisma
    }

    [Header("State")]
    public CreationStep CurrentStep = CreationStep.RaceSelection;
    public string CharacterName = string.Empty;
    public int RemainingAttributePoints = 20;
    public string RigId { get; private set; } = "humanoid_v1";
    public List<EquippedAttachment> EquippedAttachments { get; } = new List<EquippedAttachment>();

    public RaceDefinition SelectedRace { get; private set; }
    public ClassDefinition SelectedClass { get; private set; }
    public Gender? SelectedGender { get; private set; }
    public AbilityScores AllocatedAttributes { get; private set; } = new AbilityScores();
    public AbilityScores BaseAttributes { get; private set; } = new AbilityScores();
    public AbilityScores RaceBonuses { get; private set; } = new AbilityScores();
    public bool IsGeneratingImage { get; set; }
    public string GenerationError { get; set; }
    public string LastGeneratedPath { get; set; }

    public CharacterCreationData Data { get; private set; }
    public List<AppearanceSelection> AppearanceSelections { get; } = new List<AppearanceSelection>();

    private readonly Dictionary<string, List<AppearanceCategoryDefinition>> appearanceByKey = new Dictionary<string, List<AppearanceCategoryDefinition>>();
    private readonly Dictionary<AppearanceCategory, List<AppearanceOptionDefinition>> generatedOptions = new Dictionary<AppearanceCategory, List<AppearanceOptionDefinition>>();
    private readonly Dictionary<AppearanceCategory, float> sliderValues = new Dictionary<AppearanceCategory, float>();

    private void Awake()
    {
        Data = CharacterCreationDataLoader.LoadFromResources();
        BuildDefaultAppearances();
    }

    public bool SelectRace(string raceId)
    {
        var race = Data.GetRaceById(raceId);
        if (race == null)
        {
            return false;
        }

        SelectedRace = race;
        ApplyRaceBonuses(race);
        EnsureAppearanceSelections();
        EnsureBodySelection();
        return true;
    }

    public void SelectGender(Gender gender)
    {
        SelectedGender = gender;
        EnsureAppearanceSelections();
        EnsureBodySelection();
    }

    public bool SelectClass(string classId)
    {
        var characterClass = Data.GetClassById(classId);
        if (characterClass == null)
        {
            return false;
        }

        SelectedClass = characterClass;
        ApplyClassStartingAttributes(characterClass);
        return true;
    }

    public void SetRigId(string rigId)
    {
        RigId = string.IsNullOrWhiteSpace(rigId) ? "humanoid_v1" : rigId;
    }

    public IReadOnlyList<AppearanceCategoryDefinition> GetAppearanceDefinitions()
    {
        var key = GetAppearanceKey();
        if (appearanceByKey.TryGetValue(key, out var definitions))
        {
            return MergeGeneratedOptions(definitions);
        }

        return MergeGeneratedOptions(GetFallbackAppearanceDefinitions());
    }

    public AppearanceOptionDefinition AddGeneratedOption(AppearanceCategory category, AppearanceOptionDefinition option)
    {
        if (option == null)
        {
            return null;
        }

        if (!generatedOptions.TryGetValue(category, out var options))
        {
            options = new List<AppearanceOptionDefinition>();
            generatedOptions[category] = options;
        }

        options.Add(option);
        SelectAppearanceOption(category, option.id);
        return option;
    }

    public AppearanceOptionDefinition SelectAppearanceOption(AppearanceCategory category, string optionId)
    {
        var definitions = GetAppearanceDefinitions();
        AppearanceOptionDefinition selectedOption = null;
        for (var i = 0; i < definitions.Count; i++)
        {
            var definition = definitions[i];
            if (definition.category != category)
            {
                continue;
            }

            selectedOption = definition.options.Find(option => option.id == optionId);
            break;
        }

        if (selectedOption == null)
        {
            return null;
        }

        var existingIndex = AppearanceSelections.FindIndex(selection => selection.category == category);
        var selection = new AppearanceSelection { category = category, optionId = selectedOption.id };
        if (existingIndex >= 0)
        {
            AppearanceSelections[existingIndex] = selection;
        }
        else
        {
            AppearanceSelections.Add(selection);
        }

        return selectedOption;
    }

    public float GetSliderValue(AppearanceCategory category, float defaultValue = 5f)
    {
        if (sliderValues.TryGetValue(category, out var value))
        {
            return value;
        }

        sliderValues[category] = defaultValue;
        return defaultValue;
    }

    public void SetSliderValue(AppearanceCategory category, float value)
    {
        sliderValues[category] = Mathf.Clamp(value, 0f, 10f);
    }

    public AppearanceOptionDefinition GetSelectedAppearanceOption(AppearanceCategory category)
    {
        var selection = AppearanceSelections.Find(entry => entry.category == category);
        if (string.IsNullOrWhiteSpace(selection.optionId))
        {
            return null;
        }

        var definitions = GetAppearanceDefinitions();
        foreach (var definition in definitions)
        {
            if (definition.category != category)
            {
                continue;
            }

            return definition.options.Find(option => option.id == selection.optionId);
        }

        return null;
    }

    public void ApplyClassStartingAttributes(ClassDefinition characterClass)
    {
        BaseAttributes = characterClass?.startingAttributes?.Clone() ?? new AbilityScores();
        AllocatedAttributes = BaseAttributes.Clone();
        RemainingAttributePoints = 20;
    }

    public void ApplyRaceBonuses(RaceDefinition race)
    {
        RaceBonuses = race?.abilityScoreBonuses?.Clone() ?? new AbilityScores();
    }

    public int GetScore(Ability ability)
    {
        switch (ability)
        {
            case Ability.Strength:
                return AllocatedAttributes.strength;
            case Ability.Dexterity:
                return AllocatedAttributes.dexterity;
            case Ability.Constitution:
                return AllocatedAttributes.constitution;
            case Ability.Intelligence:
                return AllocatedAttributes.intelligence;
            case Ability.Wisdom:
                return AllocatedAttributes.wisdom;
            case Ability.Charisma:
                return AllocatedAttributes.charisma;
            default:
                return 0;
        }
    }

    public int GetTotalScore(Ability ability)
    {
        return GetScore(ability) + GetRaceBonus(ability);
    }

    public int GetRaceBonus(Ability ability)
    {
        switch (ability)
        {
            case Ability.Strength:
                return RaceBonuses.strength;
            case Ability.Dexterity:
                return RaceBonuses.dexterity;
            case Ability.Constitution:
                return RaceBonuses.constitution;
            case Ability.Intelligence:
                return RaceBonuses.intelligence;
            case Ability.Wisdom:
                return RaceBonuses.wisdom;
            case Ability.Charisma:
                return RaceBonuses.charisma;
            default:
                return 0;
        }
    }

    public int GetBaseScore(Ability ability)
    {
        switch (ability)
        {
            case Ability.Strength:
                return BaseAttributes.strength;
            case Ability.Dexterity:
                return BaseAttributes.dexterity;
            case Ability.Constitution:
                return BaseAttributes.constitution;
            case Ability.Intelligence:
                return BaseAttributes.intelligence;
            case Ability.Wisdom:
                return BaseAttributes.wisdom;
            case Ability.Charisma:
                return BaseAttributes.charisma;
            default:
                return 0;
        }
    }

    public bool TryIncrease(Ability ability)
    {
        if (RemainingAttributePoints <= 0)
        {
            return false;
        }

        SetScore(ability, GetScore(ability) + 1);
        RemainingAttributePoints -= 1;
        return true;
    }

    public bool TryDecrease(Ability ability)
    {
        var baseScore = GetBaseScore(ability);
        var currentScore = GetScore(ability);
        if (currentScore <= baseScore)
        {
            return false;
        }

        SetScore(ability, currentScore - 1);
        RemainingAttributePoints += 1;
        return true;
    }

    private void SetScore(Ability ability, int value)
    {
        switch (ability)
        {
            case Ability.Strength:
                AllocatedAttributes.strength = value;
                break;
            case Ability.Dexterity:
                AllocatedAttributes.dexterity = value;
                break;
            case Ability.Constitution:
                AllocatedAttributes.constitution = value;
                break;
            case Ability.Intelligence:
                AllocatedAttributes.intelligence = value;
                break;
            case Ability.Wisdom:
                AllocatedAttributes.wisdom = value;
                break;
            case Ability.Charisma:
                AllocatedAttributes.charisma = value;
                break;
        }
    }

    public void SaveToSelectedSlot()
    {
        var characterIndex = PlayerPrefs.GetInt("FableForge_SelectedCharacter", 0);
        var saveSlotIndex = PlayerPrefs.GetInt("FableForge_SelectedSaveSlot", 0);
        SaveToSlot(characterIndex, saveSlotIndex);
    }

    public void SaveToSlot(int characterIndex, int saveSlotIndex)
    {
        var name = string.IsNullOrWhiteSpace(CharacterName) ? "Adventurer" : CharacterName;
        var characterClass = SelectedClass != null ? SelectedClass.name : "Unknown";
        PlayerPrefs.SetString($"{CharacterKeyPrefix}{characterIndex}_Name", name);
        PlayerPrefs.SetString($"{CharacterKeyPrefix}{characterIndex}_Class", characterClass);

        var globalSlotIndex = GetGlobalSlotIndex(characterIndex, saveSlotIndex);
        PlayerPrefs.SetString($"{SaveSlotKeyPrefix}{globalSlotIndex}_LastPlayed", DateTime.UtcNow.ToString("O"));
        PlayerPrefs.Save();

        CharacterIndexRegistry.Register(characterIndex);
    }

    private int GetGlobalSlotIndex(int characterIndex, int saveSlotIndex)
    {
        return characterIndex * MaxSaveSlotsPerCharacter + saveSlotIndex;
    }

    public GameCharacter BuildGameCharacter()
    {
        var name = string.IsNullOrWhiteSpace(CharacterName) ? "Adventurer" : CharacterName;
        var race = ParseRace(SelectedRace?.name);
        var characterClass = ParseClass(SelectedClass?.name);

        return new GameCharacter
        {
            name = name,
            race = race,
            characterClass = characterClass,
            rigId = RigId,
            presetJson = CharacterPreset.FromSelections(RigId, AppearanceSelections, GetAppearanceDefinitions()).ToJson(),
            appearanceSelections = new List<AppearanceSelection>(AppearanceSelections),
            equippedAttachments = new List<EquippedAttachment>(EquippedAttachments)
        };
    }

    private Race ParseRace(string value)
    {
        if (!string.IsNullOrWhiteSpace(value) && Enum.TryParse(value, true, out Race parsed))
        {
            return parsed;
        }

        return Race.Human;
    }

    private CharacterClass ParseClass(string value)
    {
        if (!string.IsNullOrWhiteSpace(value) && Enum.TryParse(value, true, out CharacterClass parsed))
        {
            return parsed;
        }

        return CharacterClass.Unknown;
    }

    private void EnsureAppearanceSelections()
    {
        var definitions = GetAppearanceDefinitions();
        foreach (var definition in definitions)
        {
            var existing = AppearanceSelections.Find(entry => entry.category == definition.category);
            if (!string.IsNullOrWhiteSpace(existing.optionId))
            {
                continue;
            }

            var defaultOption = definition.options.Count > 0 ? definition.options[0] : null;
            if (defaultOption == null)
            {
                continue;
            }

            AppearanceSelections.Add(new AppearanceSelection
            {
                category = definition.category,
                optionId = defaultOption.id
            });
        }
    }

    private void EnsureBodySelection()
    {
        if (SelectedRace == null || !SelectedGender.HasValue)
        {
            return;
        }

        AppearanceCategoryDefinition bodyDefinition = null;
        var definitions = GetAppearanceDefinitions();
        for (var i = 0; i < definitions.Count; i++)
        {
            if (definitions[i].category == AppearanceCategory.Body)
            {
                bodyDefinition = definitions[i];
                break;
            }
        }

        if (bodyDefinition == null || bodyDefinition.options == null || bodyDefinition.options.Count == 0)
        {
            return;
        }

        var raceSlug = SelectedRace.id != null ? SelectedRace.id.ToLowerInvariant() : "human";
        var genderSlug = SelectedGender.Value.ToString().ToLowerInvariant();
        var targetId = $"body_{raceSlug}_{genderSlug}_01";

        var targetOption = bodyDefinition.options.Find(option => option.id == targetId);
        if (targetOption == null)
        {
            targetOption = bodyDefinition.options[0];
        }

        SelectAppearanceOption(AppearanceCategory.Body, targetOption.id);
    }

    private string GetAppearanceKey()
    {
        var raceId = SelectedRace != null ? SelectedRace.id : "default";
        var gender = SelectedGender.HasValue ? SelectedGender.Value.ToString() : "Any";
        return $"{raceId}|{gender}";
    }

    private IReadOnlyList<AppearanceCategoryDefinition> GetFallbackAppearanceDefinitions()
    {
        var fallbackKey = "default|Any";
        if (!appearanceByKey.TryGetValue(fallbackKey, out var definitions))
        {
            definitions = BuildGenericAppearanceDefinitions("default", Gender.Other);
            appearanceByKey[fallbackKey] = definitions;
        }

        return definitions;
    }

    private IReadOnlyList<AppearanceCategoryDefinition> MergeGeneratedOptions(IReadOnlyList<AppearanceCategoryDefinition> baseDefinitions)
    {
        if (generatedOptions.Count == 0 || baseDefinitions == null)
        {
            return baseDefinitions;
        }

        var merged = new List<AppearanceCategoryDefinition>();
        foreach (var definition in baseDefinitions)
        {
            var clone = new AppearanceCategoryDefinition
            {
                category = definition.category,
                label = definition.label,
                options = new List<AppearanceOptionDefinition>(definition.options)
            };

            if (generatedOptions.TryGetValue(definition.category, out var generated))
            {
                clone.options.AddRange(generated);
            }

            merged.Add(clone);
        }

        return merged;
    }

    private void BuildDefaultAppearances()
    {
        appearanceByKey.Clear();
        if (Data == null)
        {
            appearanceByKey["default|Any"] = BuildGenericAppearanceDefinitions("default", Gender.Other);
            return;
        }

        foreach (var race in Data.Races)
        {
            foreach (Gender gender in Enum.GetValues(typeof(Gender)))
            {
                var definitions = BuildGenericAppearanceDefinitions(race.id, gender);
                appearanceByKey[$"{race.id}|{gender}"] = definitions;
            }
        }

        appearanceByKey["default|Any"] = BuildGenericAppearanceDefinitions("default", Gender.Other);
    }

    private List<AppearanceCategoryDefinition> BuildGenericAppearanceDefinitions(string raceId, Gender gender)
    {
        var racePrefix = string.IsNullOrWhiteSpace(raceId) ? "default" : raceId.ToLowerInvariant();
        var hairStyleOptions = gender == Gender.Female
            ? new[] { "Long", "Braided" }
            : new[] { "Short", "Tied" };

        switch (racePrefix)
        {
            case "elf":
                return BuildAppearanceSet(
                    "Elf",
                    raceId,
                    gender,
                    new[] { "Tall", "Graceful" },
                    new[] { "Light", "Feather" },
                    new[] { "Lithe", "Lean" },
                    hairStyleOptions,
                    new[] { "Silver", "Blonde" },
                    new[] { "Fair", "Ivory" },
                    new[] { "Keen", "Soft" },
                    new[] { "Green", "Amber" },
                    new[] { "Serene", "Smile" },
                    new[] { "Fine", "Delicate" },
                    new[] { "Pointed", "Soft" },
                    new[] { "Long", "Longer" }
                );
            case "dwarf":
                return BuildAppearanceSet(
                    "Dwarf",
                    raceId,
                    gender,
                    new[] { "Short", "Stout" },
                    new[] { "Heavy", "Sturdy" },
                    new[] { "Stocky", "Broad" },
                    hairStyleOptions,
                    new[] { "Dark", "Red" },
                    new[] { "Ruddy", "Tan" },
                    new[] { "Focused", "Deep" },
                    new[] { "Brown", "Gray" },
                    new[] { "Grin", "Grim" },
                    new[] { "Broad", "Flat" },
                    new[] { "Square", "Strong" },
                    new[] { "Small", "Hidden" }
                );
            case "orc":
                return BuildAppearanceSet(
                    "Orc",
                    raceId,
                    gender,
                    new[] { "Tall", "Bulky" },
                    new[] { "Heavy", "Warborn" },
                    new[] { "Muscular", "Heavy" },
                    new[] { "Shaved", "Topknot" },
                    new[] { "Black", "Dark" },
                    new[] { "Green", "Gray" },
                    new[] { "Fierce", "Focused" },
                    new[] { "Yellow", "Red" },
                    new[] { "Snarl", "Grim" },
                    new[] { "Wide", "Flat" },
                    new[] { "Jagged", "Strong" },
                    new[] { "Tapered", "Short" }
                );
            case "halfling":
                return BuildAppearanceSet(
                    "Halfling",
                    raceId,
                    gender,
                    new[] { "Short", "Tiny" },
                    new[] { "Light", "Spry" },
                    new[] { "Compact", "Quick" },
                    hairStyleOptions,
                    new[] { "Chestnut", "Honey" },
                    new[] { "Warm", "Tan" },
                    new[] { "Bright", "Playful" },
                    new[] { "Hazel", "Brown" },
                    new[] { "Cheerful", "Smile" },
                    new[] { "Button", "Soft" },
                    new[] { "Rounded", "Soft" },
                    new[] { "Small", "Tucked" }
                );
            case "tiefling":
                return BuildAppearanceSet(
                    "Tiefling",
                    raceId,
                    gender,
                    new[] { "Tall", "Elegant" },
                    new[] { "Light", "Lean" },
                    new[] { "Sleek", "Athletic" },
                    hairStyleOptions,
                    new[] { "Crimson", "Black" },
                    new[] { "Ash", "Umber" },
                    new[] { "Intense", "Cool" },
                    new[] { "Gold", "Violet" },
                    new[] { "Calm", "Smirk" },
                    new[] { "Sharp", "Refined" },
                    new[] { "Sharp", "Smooth" },
                    new[] { "Tapered", "Pierced" }
                );
            default:
                return BuildAppearanceSet(
                    "Human",
                    raceId,
                    gender,
                    new[] { "Average", "Tall" },
                    new[] { "Average", "Sturdy" },
                    new[] { "Athletic", "Lean" },
                    hairStyleOptions,
                    new[] { "Black", "Brown" },
                    new[] { "Light", "Tan" },
                    new[] { "Round", "Almond" },
                    new[] { "Blue", "Brown" },
                    new[] { "Neutral", "Smirk" },
                    new[] { "Straight", "Soft" },
                    new[] { "Square", "Rounded" },
                    new[] { "Standard", "Small" }
                );
        }
    }

    private List<AppearanceCategoryDefinition> BuildAppearanceSet(
        string labelPrefix,
        string raceId,
        Gender gender,
        string[] height,
        string[] weight,
        string[] build,
        string[] hairStyle,
        string[] hairColor,
        string[] skinColor,
        string[] eyes,
        string[] eyeColor,
        string[] mouth,
        string[] nose,
        string[] chin,
        string[] ears)
    {
        return new List<AppearanceCategoryDefinition>
        {
            BuildBodyCategory(raceId, gender),
            BuildCategory(AppearanceCategory.Height, $"{labelPrefix} Height", height, null, null, null),
            BuildCategory(AppearanceCategory.Weight, $"{labelPrefix} Weight", weight, null, null, null),
            BuildCategory(AppearanceCategory.Build, $"{labelPrefix} Build", build, null, null, null),
            BuildDualSlotCategory(AppearanceCategory.HairStyle, "Hair Style", hairStyle, "HairFront", "hair_front", "HairBack", "hair_back"),
            BuildTintCategory(AppearanceCategory.HairColor, "Hair Color", hairColor, "Hair"),
            BuildTintCategory(AppearanceCategory.SkinColor, "Skin Color", skinColor, "Skin"),
            BuildCategory(AppearanceCategory.Eyes, "Eyes", eyes, "Eyes", "eyes", null),
            BuildTintCategory(AppearanceCategory.EyeColor, "Eye Color", eyeColor, "Eyes"),
            BuildCategory(AppearanceCategory.Mouth, "Mouth", mouth, "Mouth", "mouth", null),
            BuildCategory(AppearanceCategory.Nose, "Nose", nose, "Nose", "nose", null),
            BuildCategory(AppearanceCategory.Chin, "Chin", chin, "Head", "head_chin", null),
            BuildCategory(AppearanceCategory.Ears, "Ears", ears, "Head", "head_ears", null)
        };
    }

    private AppearanceCategoryDefinition BuildBodyCategory(string raceId, Gender gender)
    {
        var raceSlug = string.IsNullOrWhiteSpace(raceId) ? "human" : raceId.ToLowerInvariant();
        var genderSlug = gender.ToString().ToLowerInvariant();
        var slotLabel = $"body_{raceSlug}_{genderSlug}_front_01";

        var definition = new AppearanceCategoryDefinition
        {
            category = AppearanceCategory.Body,
            label = "Body"
        };

        definition.options.Add(new AppearanceOptionDefinition
        {
            id = $"body_{raceSlug}_{genderSlug}_01",
            label = $"{raceSlug} {genderSlug}",
            slotCategory = "Body",
            slotLabel = slotLabel
        });

        return definition;
    }

    private AppearanceCategoryDefinition BuildCategory(
        AppearanceCategory category,
        string label,
        string[] options,
        string slotCategory,
        string slotPrefix,
        string tintKey)
    {
        var definition = new AppearanceCategoryDefinition
        {
            category = category,
            label = label
        };

        for (var i = 0; i < options.Length; i++)
        {
            var optionLabel = options[i];
            var slotLabel = !string.IsNullOrWhiteSpace(slotPrefix)
                ? $"{slotPrefix}_{Slugify(optionLabel)}_01"
                : null;
            var tintHex = !string.IsNullOrWhiteSpace(tintKey)
                ? LookupTintHex(tintKey, optionLabel)
                : null;
            definition.options.Add(new AppearanceOptionDefinition
            {
                id = $"{category}_{i}",
                label = optionLabel,
                slotCategory = slotCategory,
                slotLabel = slotLabel,
                tintKey = tintKey,
                tintHex = tintHex
            });
        }

        return definition;
    }

    private AppearanceCategoryDefinition BuildDualSlotCategory(
        AppearanceCategory category,
        string label,
        string[] options,
        string primaryCategory,
        string primaryPrefix,
        string secondaryCategory,
        string secondaryPrefix)
    {
        var definition = new AppearanceCategoryDefinition
        {
            category = category,
            label = label
        };

        for (var i = 0; i < options.Length; i++)
        {
            var optionLabel = options[i];
            var primaryLabel = $"{primaryPrefix}_{Slugify(optionLabel)}_01";
            var secondaryLabel = $"{secondaryPrefix}_{Slugify(optionLabel)}_01";
            definition.options.Add(new AppearanceOptionDefinition
            {
                id = $"{category}_{i}",
                label = optionLabel,
                slotCategory = primaryCategory,
                slotLabel = primaryLabel,
                slotCategorySecondary = secondaryCategory,
                slotLabelSecondary = secondaryLabel
            });
        }

        return definition;
    }

    private AppearanceCategoryDefinition BuildTintCategory(
        AppearanceCategory category,
        string label,
        string[] options,
        string tintKey)
    {
        return BuildCategory(category, label, options, null, null, tintKey);
    }

    private string LookupTintHex(string tintKey, string optionLabel)
    {
        switch (tintKey)
        {
            case "Skin":
                return optionLabel switch
                {
                    "Fair" => "#F2D6C3",
                    "Ivory" => "#E7C8A6",
                    "Ruddy" => "#D09A76",
                    "Tan" => "#C08A5A",
                    "Warm" => "#E1B18E",
                    "Ash" => "#9E7B6A",
                    "Umber" => "#7C5A4A",
                    "Green" => "#6E8F6B",
                    "Gray" => "#7A7A7A",
                    _ => "#E7B38C"
                };
            case "Hair":
                return optionLabel switch
                {
                    "Silver" => "#C9C9C9",
                    "Blonde" => "#E6C57A",
                    "Dark" => "#2F2A24",
                    "Red" => "#8B3A2B",
                    "Chestnut" => "#6B3E2E",
                    "Honey" => "#C79B4A",
                    "Crimson" => "#7D2430",
                    "Black" => "#1E1B19",
                    "Brown" => "#4A3327",
                    _ => "#3B2A1E"
                };
            case "Eyes":
                return optionLabel switch
                {
                    "Green" => "#3F6B4F",
                    "Amber" => "#9E6B2C",
                    "Brown" => "#4B3621",
                    "Gray" => "#5C6773",
                    "Hazel" => "#6A5B3D",
                    "Gold" => "#B68E3B",
                    "Violet" => "#5A4A8E",
                    "Blue" => "#2A5B9E",
                    "Yellow" => "#B6A83B",
                    "Red" => "#7C2A2A",
                    _ => "#2A5B9E"
                };
            default:
                return null;
        }
    }

    private string Slugify(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "variant";
        }

        var chars = value.Trim().ToLowerInvariant().ToCharArray();
        for (var i = 0; i < chars.Length; i++)
        {
            if (!char.IsLetterOrDigit(chars[i]))
            {
                chars[i] = '_';
            }
        }

        return new string(chars);
    }

}
