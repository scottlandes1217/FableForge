#pragma once

#include "Animation/AnimationAsset.h"
#include "CoreMinimal.h"
#include "Engine/DataTable.h"
#include "Engine/Texture2D.h"
#include "FableSkillSystemTableRows.generated.h"

UENUM(BlueprintType)
enum class EFableSkillType : uint8
{
	Active,
	Passive,
	Triggered
};

UENUM(BlueprintType)
enum class EFableSkillResourceType : uint8
{
	None,
	Mana,
	Stamina,
	Energy,
	Rage
};

UENUM(BlueprintType)
enum class EFableSkillTargetingMode : uint8
{
	Self,
	TargetUnit,
	Ground,
	Object,
	Weapon,
	Equipment,
	Area
};

UENUM(BlueprintType)
enum class EFableSkillMasteryStage : uint8
{
	Dormant,
	Stirring,
	Awakening,
	Manifested
};

UENUM(BlueprintType)
enum class EFableSkillCategory : uint8
{
	Basic,
	Light,
	Elemental,
	Arcane,
	Sword,
	Shield,
	Support,
	Movement,
	Utility,
	// Elemental/time schools are appended to preserve serialized values of the
	// original journal categories. These are the canonical starter school tabs.
	Fire,
	Water,
	Earth,
	Air,
	TimeManipulation
};

UENUM(BlueprintType)
enum class EFableSkillEffectType : uint8
{
	Damage,
	DamageOverTime,
	AreaDamage,
	CrowdControl,
	Buff,
	Debuff,
	Movement,
	ForcedMovement,
	Pull,
	Push,
	Shield,
	Heal
};

UENUM(BlueprintType)
enum class EFablePatternWindowType : uint8
{
	LastNActions,
	LastNSeconds,
	LastNTurns
};

UENUM(BlueprintType)
enum class EFableDiscoveryPatternType : uint8
{
	Sequence,
	ContextRepeat,
	EnvironmentInteraction,
	Observation,
	Reading,
	Hybrid
};

USTRUCT(BlueprintType)
struct FFableSkillDefinitionTableRow : public FTableRowBase
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Skill")
	FString SkillId;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Skill")
	FString DisplayName;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Skill")
	FString Summary;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Skill")
	FString Description;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Skill")
	EFableSkillType SkillType = EFableSkillType::Active;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Skill")
	EFableSkillTargetingMode TargetingMode = EFableSkillTargetingMode::TargetUnit;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Skill")
	EFableSkillCategory Category = EFableSkillCategory::Basic;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Costs")
	EFableSkillResourceType ResourceType = EFableSkillResourceType::None;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Costs")
	float ResourceCost = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Timing")
	float CooldownSeconds = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Timing")
	float CastTimeSeconds = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Ranges")
	float RangeUnits = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Ranges")
	float RadiusUnits = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Scaling")
	FString ScalingPrimaryStat;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Scaling")
	float ScalingPrimaryCoefficient = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Scaling")
	FString ScalingSecondaryStat;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Scaling")
	float ScalingSecondaryCoefficient = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Tags")
	FString TagsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Effects")
	FString EffectIdsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Synergy")
	FString SynergyRuleIdsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Discovery")
	FString DiscoveryRuleIdsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Mastery")
	EFableSkillMasteryStage StartingMasteryStage = EFableSkillMasteryStage::Dormant;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Mastery")
	int32 StirringProgressThreshold = 20;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Mastery")
	int32 AwakeningProgressThreshold = 60;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Mastery")
	int32 ManifestedProgressThreshold = 120;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Learning")
	FString LearningSourcesCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Learning")
	FString WitnessSkillIdsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Learning")
	FString BookIdsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "UI")
	FString IconToken;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "UI")
	TSoftObjectPtr<UTexture2D> SkillIconTexture;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Animation")
	TSoftObjectPtr<UAnimationAsset> CharacterAnimationAsset;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Animation")
	FSoftObjectPath EffectAnimationAsset;
};

USTRUCT(BlueprintType)
struct FFableSkillEffectTableRow : public FTableRowBase
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Effect")
	FString EffectId;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Effect")
	FString DisplayName;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Effect")
	EFableSkillEffectType EffectType = EFableSkillEffectType::Damage;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Effect")
	float BaseMagnitude = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Effect")
	float DurationSeconds = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Effect")
	float RadiusUnits = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Effect")
	float ForceMagnitude = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Effect")
	float TickIntervalSeconds = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Effect")
	int32 MaxStacks = 1;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Effect")
	FString ApplyTagsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Effect")
	FString RequiredTargetTagsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Scaling")
	FString ScalingStat;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Scaling")
	float ScalingCoefficient = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Notes")
	FString Notes;
};

USTRUCT(BlueprintType)
struct FFableSkillSynergyRuleTableRow : public FTableRowBase
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Rule")
	FString RuleId;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Rule")
	FString DisplayName;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sequence")
	FString OrderedActionIdsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sequence")
	FString RequiredTagsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sequence")
	FString RequiredMediumsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sequence")
	FString RequiredContextsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sequence")
	FString RequiredEnvironmentTagsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Sequence")
	FString RequiredOutcomeEventsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Window")
	EFablePatternWindowType WindowType = EFablePatternWindowType::LastNActions;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Window")
	int32 WindowValue = 2;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Progression")
	int32 ThresholdOne = 5;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Progression")
	int32 ThresholdTwo = 15;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Progression")
	int32 ThresholdThree = 30;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Progression")
	FString BonusStepOne;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Progression")
	FString BonusStepTwo;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Progression")
	FString BonusStepThree;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Progression")
	float SameEncounterRepeatPenalty = 0.35f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Progression")
	float UnusedDecayPerMinute = 0.05f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Progression")
	float RiskContextBonusMultiplier = 1.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Progression")
	FString UnlockCandidateSkillIdsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Progression")
	FString CounterpartOrderRuleId;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Notes")
	FString Notes;
};

USTRUCT(BlueprintType)
struct FFableSkillDiscoveryRuleTableRow : public FTableRowBase
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Rule")
	FString RuleId;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Rule")
	FString DisplayName;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Rule")
	FString UnlockSkillId;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Pattern")
	EFableDiscoveryPatternType PatternType = EFableDiscoveryPatternType::Sequence;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Pattern")
	FString OrderedActionIdsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Pattern")
	FString RequiredTagsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Pattern")
	FString RequiredMediumsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Pattern")
	FString RequiredContextsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Pattern")
	FString RequiredEnvironmentTagsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Pattern")
	FString RequiredOutcomeEventsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Learning")
	FString LearningSourceTypesCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Learning")
	FString RequiredWitnessSkillIdsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Learning")
	FString RequiredBookIdsCsv;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Windows")
	int32 RequiredRepetitions = 10;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Windows")
	int32 RequiredEncounterCount = 3;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Windows")
	int32 RequiredDistinctEncounterVariance = 3;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Windows")
	int32 ActionWindowCount = 3;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Windows")
	float TimeWindowSeconds = 8.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Windows")
	int32 TurnWindowCount = 2;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Scoring")
	float OutOfCombatProgressMultiplier = 0.25f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Scoring")
	float EliteOrBossProgressMultiplier = 1.5f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Scoring")
	float LowHealthProgressMultiplier = 1.25f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Scoring")
	int32 PerEncounterFullCreditCap = 5;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Mastery")
	int32 DormantToStirringThreshold = 20;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Mastery")
	int32 StirringToAwakeningThreshold = 60;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Mastery")
	int32 AwakeningToManifestedThreshold = 120;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Mastery")
	float ProgressDecayPerHour = 0.5f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Notes")
	FString Notes;
};

struct FFableStarterSkillDefinition
{
	const TCHAR* SkillId = TEXT("");
	EFableSkillCategory School = EFableSkillCategory::Basic;
};

/** Shared starter-school registry for save seeding, runtime fallback, and UI tabs. */
namespace FableSkillCatalog
{
	inline const TArray<FFableStarterSkillDefinition>& GetStarterSkills()
	{
		static const TArray<FFableStarterSkillDefinition> StarterSkills = {
			{ TEXT("fireball"), EFableSkillCategory::Fire },
			{ TEXT("fire_tornado"), EFableSkillCategory::Fire },
			{ TEXT("heal_wave"), EFableSkillCategory::Water },
			{ TEXT("stone_spike"), EFableSkillCategory::Earth },
			{ TEXT("gust"), EFableSkillCategory::Air },
			{ TEXT("time_step"), EFableSkillCategory::TimeManipulation },
			{ TEXT("slow_time"), EFableSkillCategory::TimeManipulation }
		};
		return StarterSkills;
	}

	inline const TCHAR* GetStarterSkillId(EFableSkillCategory School)
	{
		for (const FFableStarterSkillDefinition& Starter : GetStarterSkills())
		{
			if (Starter.School == School) return Starter.SkillId;
		}
		return TEXT("");
	}

	inline bool IsStarterSkillId(const FString& SkillId)
	{
		for (const FFableStarterSkillDefinition& Starter : GetStarterSkills())
		{
			if (SkillId.Equals(Starter.SkillId, ESearchCase::IgnoreCase)) return true;
		}
		return false;
	}

	inline bool IsAssignableSkillId(const FString& SkillId)
	{
		return !SkillId.Equals(TEXT("basic_attack"), ESearchCase::IgnoreCase);
	}

	/** Builds a starter definition when an editor-generated DataTable is absent. */
	inline bool TryGetStarterSkillDefinition(const FString& SkillId, FFableSkillDefinitionTableRow& OutDefinition)
	{
		OutDefinition = FFableSkillDefinitionTableRow();
		if (SkillId.Equals(TEXT("fireball"), ESearchCase::IgnoreCase))
		{
			OutDefinition.SkillId = TEXT("fireball"); OutDefinition.DisplayName = TEXT("Fireball"); OutDefinition.Summary = TEXT("Explosive fire projectile");
			OutDefinition.Description = TEXT("Hurls a fire projectile that damages the impact area."); OutDefinition.Category = EFableSkillCategory::Fire;
			OutDefinition.TargetingMode = EFableSkillTargetingMode::TargetUnit; OutDefinition.ResourceType = EFableSkillResourceType::Mana; OutDefinition.ResourceCost = 20.f; OutDefinition.RangeUnits = 1200.f; OutDefinition.RadiusUnits = 180.f; OutDefinition.EffectIdsCsv = TEXT("eff_fireball_burst"); OutDefinition.TagsCsv = TEXT("fire|projectile|spell");
			return true;
		}
		if (SkillId.Equals(TEXT("fire_tornado"), ESearchCase::IgnoreCase))
		{
			OutDefinition.SkillId = TEXT("fire_tornado"); OutDefinition.DisplayName = TEXT("Fire Tornado"); OutDefinition.Summary = TEXT("A spiraling vortex of flame");
			OutDefinition.Description = TEXT("Shapes fire into a vortex at the aimed ground point."); OutDefinition.Category = EFableSkillCategory::Fire;
			OutDefinition.TargetingMode = EFableSkillTargetingMode::Area; OutDefinition.ResourceType = EFableSkillResourceType::Mana; OutDefinition.ResourceCost = 35.f; OutDefinition.RangeUnits = 1000.f; OutDefinition.RadiusUnits = 360.f; OutDefinition.EffectIdsCsv = TEXT("eff_fireball_burst|eff_burn_dot|eff_gust_pull_light"); OutDefinition.TagsCsv = TEXT("fire|wind|spell");
			return true;
		}
		if (SkillId.Equals(TEXT("heal_wave"), ESearchCase::IgnoreCase))
		{
			OutDefinition.SkillId = TEXT("heal_wave"); OutDefinition.DisplayName = TEXT("Heal Wave"); OutDefinition.Summary = TEXT("Starter healing pulse");
			OutDefinition.Description = TEXT("Restores health in a small area around the target point."); OutDefinition.Category = EFableSkillCategory::Water;
			OutDefinition.TargetingMode = EFableSkillTargetingMode::Area; OutDefinition.ResourceType = EFableSkillResourceType::Mana; OutDefinition.ResourceCost = 18.f; OutDefinition.RangeUnits = 500.f; OutDefinition.RadiusUnits = 220.f; OutDefinition.EffectIdsCsv = TEXT("eff_heal_wave_pulse"); OutDefinition.TagsCsv = TEXT("water|heal|support");
			return true;
		}
		if (SkillId.Equals(TEXT("stone_spike"), ESearchCase::IgnoreCase))
		{
			OutDefinition.SkillId = TEXT("stone_spike"); OutDefinition.DisplayName = TEXT("Stone Spike"); OutDefinition.Summary = TEXT("Earth spike from ground");
			OutDefinition.Description = TEXT("Raises a damaging spike from the selected ground point."); OutDefinition.Category = EFableSkillCategory::Earth;
			OutDefinition.TargetingMode = EFableSkillTargetingMode::Ground; OutDefinition.ResourceType = EFableSkillResourceType::Mana; OutDefinition.ResourceCost = 22.f; OutDefinition.RangeUnits = 900.f; OutDefinition.RadiusUnits = 180.f; OutDefinition.EffectIdsCsv = TEXT("eff_stone_spike_upthrust"); OutDefinition.TagsCsv = TEXT("earth|ground|spell");
			return true;
		}
		if (SkillId.Equals(TEXT("gust"), ESearchCase::IgnoreCase))
		{
			OutDefinition.SkillId = TEXT("gust"); OutDefinition.DisplayName = TEXT("Gust"); OutDefinition.Summary = TEXT("Directional wind burst");
			OutDefinition.Description = TEXT("Pushes nearby enemies and objects away from the target point."); OutDefinition.Category = EFableSkillCategory::Air;
			OutDefinition.TargetingMode = EFableSkillTargetingMode::Area; OutDefinition.ResourceType = EFableSkillResourceType::Mana; OutDefinition.ResourceCost = 15.f; OutDefinition.RangeUnits = 850.f; OutDefinition.RadiusUnits = 260.f; OutDefinition.EffectIdsCsv = TEXT("eff_gust_push|eff_gust_pull_light"); OutDefinition.TagsCsv = TEXT("air|wind|control");
			return true;
		}
		if (SkillId.Equals(TEXT("time_step"), ESearchCase::IgnoreCase))
		{
			OutDefinition.SkillId = TEXT("time_step"); OutDefinition.DisplayName = TEXT("Time Step"); OutDefinition.Summary = TEXT("Teleport to a chosen destination");
			OutDefinition.Description = TEXT("Equip with L1, then press L3 to choose a destination up to 6.5 m away. Move the cursor with the right stick. Press X to teleport, or Circle to cancel."); OutDefinition.Category = EFableSkillCategory::TimeManipulation;
			OutDefinition.TargetingMode = EFableSkillTargetingMode::Ground; OutDefinition.ResourceType = EFableSkillResourceType::None; OutDefinition.ResourceCost = 0.f; OutDefinition.RangeUnits = 1200.f; OutDefinition.EffectIdsCsv = TEXT("eff_time_step_move"); OutDefinition.TagsCsv = TEXT("time|movement|utility");
			return true;
		}
		if (SkillId.Equals(TEXT("slow_time"), ESearchCase::IgnoreCase))
		{
			OutDefinition.SkillId = TEXT("slow_time"); OutDefinition.DisplayName = TEXT("Slow Time"); OutDefinition.Summary = TEXT("Slow the world around you");
			OutDefinition.Description = TEXT("Select this power in the L1 wheel to equip it. Press L3 to toggle slow time on or off. Drains Cosmic while active."); OutDefinition.Category = EFableSkillCategory::TimeManipulation;
			OutDefinition.TargetingMode = EFableSkillTargetingMode::Self; OutDefinition.ResourceType = EFableSkillResourceType::None; OutDefinition.ResourceCost = 0.f; OutDefinition.RangeUnits = 0.f; OutDefinition.RadiusUnits = 0.f; OutDefinition.TagsCsv = TEXT("cosmic|time|toggle|drain");
			return true;
		}
		return false;
	}
}
