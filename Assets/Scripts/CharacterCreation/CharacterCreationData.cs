using System;
using System.Collections.Generic;

[Serializable]
public class CharacterCreationData
{
    public List<RaceDefinition> Races = new List<RaceDefinition>();
    public List<ClassDefinition> Classes = new List<ClassDefinition>();

    public RaceDefinition GetRaceById(string raceId)
    {
        return Races.Find(race => race.id == raceId);
    }

    public ClassDefinition GetClassById(string classId)
    {
        return Classes.Find(characterClass => characterClass.id == classId);
    }
}

[Serializable]
public class SkinColorOption
{
    public string label;
    public string hex;
}

/// <summary>Options for an additional feature (e.g. horns: ["Short", "Curved"]). Array so Unity JsonUtility can deserialize.</summary>
[Serializable]
public class FeatureOptionSet
{
    public string featureId;
    public string[] options;
}

[Serializable]
public class RaceDefinition
{
    public string id;
    public string name;
    public string description;
    public string image;
    public AbilityScores abilityScoreBonuses;
    public int baseHitPoints = 10;
    public int baseMana;
    public int baseEnergy;
    public int baseRage;
    /// <summary>Skin colors for character creation. Each has label and hex. If empty, fallback options are used.</summary>
    public SkinColorOption[] skinColors;
    /// <summary>Eye colors (label + hex). If empty, fallback options are used.</summary>
    public SkinColorOption[] eyeColors;
    /// <summary>Available face option labels (e.g. "Round", "Soft"). If empty, fallback options are used.</summary>
    public string[] faces;
    /// <summary>Hair colors (label + hex). If empty, fallback options are used.</summary>
    public SkinColorOption[] hairColors;
    /// <summary>Available hair style labels (e.g. "Short", "Long"). If empty, fallback options are used.</summary>
    public string[] hairStyles;
    /// <summary>Available ear option labels (e.g. "Standard", "Pointed"). If empty, fallback options are used.</summary>
    public string[] ears;
    /// <summary>Available eyes option labels (e.g. "Round", "Almond"). If empty, fallback options are used.</summary>
    public string[] eyes;
    /// <summary>Available eyebrows option labels (e.g. "Straight", "Arched"). If empty, fallback options are used.</summary>
    public string[] eyebrows;
    /// <summary>Available mouth option labels (e.g. "Neutral", "Smile"). If empty, fallback options are used.</summary>
    public string[] mouths;
    /// <summary>Available nose option labels (e.g. "Straight", "Button", "Aquiline"). If empty, fallback options are used.</summary>
    public string[] noses;
    /// <summary>Additional feature ids this race has (e.g. "tail", "horns", "tusks").</summary>
    public string[] additionalFeatures;
    /// <summary>Options per additional feature (e.g. { featureId: "horns", options: ["Short", "Curved"] }).</summary>
    public FeatureOptionSet[] featureOptions;
}

[Serializable]
public class ClassDefinition
{
    public string id;
    public string name;
    public string description;
    public string image;
    public int hitDie;
    public string primaryAbility;
    public string resourceType;
    public string[] startingSkills;
    public string[] startingEquipment;
    public AbilityScores startingAttributes;
}

[Serializable]
public class AbilityScores
{
    public int strength;
    public int dexterity;
    public int constitution;
    public int intelligence;
    public int wisdom;
    public int charisma;

    public AbilityScores Clone()
    {
        return new AbilityScores
        {
            strength = strength,
            dexterity = dexterity,
            constitution = constitution,
            intelligence = intelligence,
            wisdom = wisdom,
            charisma = charisma
        };
    }

    public void Add(AbilityScores other)
    {
        if (other == null)
        {
            return;
        }

        strength += other.strength;
        dexterity += other.dexterity;
        constitution += other.constitution;
        intelligence += other.intelligence;
        wisdom += other.wisdom;
        charisma += other.charisma;
    }
}
