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
