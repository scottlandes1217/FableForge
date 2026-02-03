using System;
using System.Collections.Generic;
using UnityEngine;

namespace FableForge.Models
{
    [Serializable]
    public struct AbilityScores
    {
        public int strength;
        public int dexterity;
        public int constitution;
        public int intelligence;
        public int wisdom;
        public int charisma;

        public int ScoreFor(Ability ability)
        {
            switch (ability)
            {
                case Ability.Strength:
                    return strength;
                case Ability.Dexterity:
                    return dexterity;
                case Ability.Constitution:
                    return constitution;
                case Ability.Intelligence:
                    return intelligence;
                case Ability.Wisdom:
                    return wisdom;
                case Ability.Charisma:
                    return charisma;
                default:
                    return 10;
            }
        }

        public int ModifierFor(Ability ability)
        {
            var score = ScoreFor(ability);
            return (score - 10) / 2;
        }
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

    public enum Race
    {
        Human,
        Elf,
        Dwarf,
        Halfling,
        Orc,
        Tiefling
    }

    public enum CharacterClass
    {
        Unknown,
        Fighter,
        Rogue,
        Wizard,
        Cleric,
        Ranger,
        Paladin,
        Barbarian,
        Bard
    }

    public enum AppearanceCategory
    {
        Body,
        Height,
        Weight,
        Build,
        HairStyle,
        HairColor,
        SkinColor,
        Face,
        Eyes,
        Eyebrows,
        Mouth,
        EyeColor,
        Ears,
        Horns,
        Tail,
        Tusks,
        // Kept for backward compatibility with saved appearance selections.
        Nose,
        Chin
    }

    public enum AppearanceValueType
    {
        Number,
        Boolean,
        Trigger
    }

    [Serializable]
    public class AppearanceOptionDefinition
    {
        public string id;
        public string label;
        public AppearanceValueType valueType = AppearanceValueType.Number;
        public float numberValue;
        public bool booleanValue;
        public string slotCategory;
        public string slotLabel;
        public string slotCategorySecondary;
        public string slotLabelSecondary;
        public string tintKey;
        public string tintHex;
        [NonSerialized] public Sprite runtimeSprite;
    }

    [Serializable]
    public class AppearanceCategoryDefinition
    {
        public AppearanceCategory category;
        public string label;
        public List<AppearanceOptionDefinition> options = new List<AppearanceOptionDefinition>();
    }

    [Serializable]
    public struct AppearanceSelection
    {
        public AppearanceCategory category;
        public string optionId;
    }

    public enum AttachmentSlot
    {
        Head,
        Chest,
        Legs,
        Hands,
        Feet,
        Back,
        Accessory,
        WeaponMainHand,
        WeaponOffHand
    }

    [Serializable]
    public struct EquippedAttachment
    {
        public AttachmentSlot slot;
        public string itemId;
    }

    public enum Skill
    {
        Athletics,
        Acrobatics,
        SleightOfHand,
        Stealth,
        Arcana,
        History,
        Investigation,
        Nature,
        Religion,
        AnimalHandling,
        Insight,
        Medicine,
        Perception,
        Survival,
        Deception,
        Intimidation,
        Performance,
        Persuasion
    }

    [Serializable]
    public struct SkillProficiency
    {
        public Skill skill;
        public int proficiencyBonus;
        public bool isProficient;

        public int Roll(AbilityScores abilityScores)
        {
            var ability = GetAssociatedAbility(skill);
            var abilityMod = abilityScores.ModifierFor(ability);
            var proficiency = isProficient ? proficiencyBonus : 0;
            return UnityEngine.Random.Range(1, 21) + abilityMod + proficiency;
        }

        private static Ability GetAssociatedAbility(Skill skill)
        {
            switch (skill)
            {
                case Skill.Athletics:
                    return Ability.Strength;
                case Skill.Acrobatics:
                case Skill.SleightOfHand:
                case Skill.Stealth:
                    return Ability.Dexterity;
                case Skill.Arcana:
                case Skill.History:
                case Skill.Investigation:
                case Skill.Nature:
                case Skill.Religion:
                    return Ability.Intelligence;
                case Skill.AnimalHandling:
                case Skill.Insight:
                case Skill.Medicine:
                case Skill.Perception:
                case Skill.Survival:
                    return Ability.Wisdom;
                case Skill.Deception:
                case Skill.Intimidation:
                case Skill.Performance:
                case Skill.Persuasion:
                    return Ability.Charisma;
                default:
                    return Ability.Strength;
            }
        }
    }

    [Serializable]
    public class GameCharacter
    {
        public string id = Guid.NewGuid().ToString();
        public string name;
        public Race race;
        public CharacterClass characterClass;
        public string creationDateIso = DateTime.UtcNow.ToString("O");
        public string rigId = "humanoid_v1";
        public string presetJson;
        public List<AppearanceSelection> appearanceSelections = new List<AppearanceSelection>();
        public List<EquippedAttachment> equippedAttachments = new List<EquippedAttachment>();

        public string DisplayName => $"{name} - {characterClass}";
    }

    [Serializable]
    public class Item
    {
        public string id;
        public string name;
        public string description;
        public int value;
        public int quantity = 1;
    }

    [Serializable]
    public class Weapon : Item
    {
        public int damageMin;
        public int damageMax;
        public Ability scalingAbility = Ability.Strength;
    }

    [Serializable]
    public class Armor : Item
    {
        public int armorClass;
    }

    [Serializable]
    public class Animal
    {
        public string id;
        public string name;
        public int level;
    }

    [Serializable]
    public class Structure
    {
        public string id;
        public string name;
        public Vector2 position;
    }

    [Serializable]
    public class Player
    {
        public string name;
        public CharacterClass characterClass;
        public int level = 1;
        public int experiencePoints;
        public AbilityScores abilityScores;
        public int attributePoints;
        public int hitPoints;
        public int maxHitPoints;
        public int armorClass = 10;

        public int mana;
        public int maxMana;
        public int rage;
        public int maxRage;
        public int energy;
        public int maxEnergy;

        public List<SkillProficiency> skills = new List<SkillProficiency>();
        public List<Item> inventory = new List<Item>();
        public Weapon equippedWeapon;
        public Armor equippedArmor;
        public List<Animal> companions = new List<Animal>();
        public Vector2 position;

        public List<string> learnedSkills = new List<string>();
        public const int MaxCompanions = 5;

        public bool CanAddCompanion()
        {
            return companions.Count < MaxCompanions;
        }

        public bool AddCompanion(Animal animal)
        {
            if (!CanAddCompanion())
            {
                return false;
            }

            companions.Add(animal);
            return true;
        }

        public void RemoveCompanion(Animal animal)
        {
            companions.Remove(animal);
        }
    }
}
