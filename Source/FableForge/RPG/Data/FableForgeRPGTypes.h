#pragma once

#include "CoreMinimal.h"
#include "FableForgeRPGTypes.generated.h"

UENUM(BlueprintType)
enum class EFableGender : uint8
{
	Male,
	Female
};

UENUM(BlueprintType)
enum class EFableActionBarOrientation : uint8
{
	Horizontal,
	Vertical
};

USTRUCT(BlueprintType)
struct FFableActionSlotData
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "ActionBar")
	FString EntryId;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "ActionBar")
	FString EntryLabel;
};

USTRUCT(BlueprintType)
struct FFableActionBarData
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "ActionBar")
	FGuid BarId;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "ActionBar")
	bool bIsMainBar = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "ActionBar")
	EFableActionBarOrientation Orientation = EFableActionBarOrientation::Horizontal;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "ActionBar")
	int32 Columns = 10;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "ActionBar")
	int32 Rows = 1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "ActionBar")
	int32 ExpandedRows = 1;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "ActionBar")
	bool bExpanded = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "ActionBar")
	FVector2D ScreenPosition = FVector2D::ZeroVector;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "ActionBar")
	TArray<FFableActionSlotData> Slots;
};

USTRUCT(BlueprintType)
struct FFableRaceAbilityBonuses
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Race")
	int32 Strength = 0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Race")
	int32 Dexterity = 0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Race")
	int32 Constitution = 0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Race")
	int32 Intelligence = 0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Race")
	int32 Wisdom = 0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Race")
	int32 Charisma = 0;
};

USTRUCT(BlueprintType)
struct FFableRaceDefinition
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Race")
	FString Id;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Race")
	FString Name;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Race")
	FString Description;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Race")
	FString Image;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Race")
	int32 BaseHitPoints = 10;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Race")
	int32 BaseMana = 0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Race")
	int32 BaseEnergy = 0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Race")
	int32 BaseRage = 0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Race")
	FFableRaceAbilityBonuses AbilityScoreBonuses;
};

USTRUCT(BlueprintType)
struct FFableSaveSlotMeta
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Save")
	int32 SlotIndex = INDEX_NONE;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Save")
	bool bHasSave = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Save")
	FString LastPlayedUtc;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Save")
	FString LastMapName;
};

USTRUCT(BlueprintType)
struct FFableCharacterProfile
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Character")
	FGuid CharacterId;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Character")
	FString CharacterName = TEXT("Adventurer");

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Character")
	FString RaceId = TEXT("human");

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Character")
	EFableGender Gender = EFableGender::Male;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Character")
	TArray<FString> CompanionNames;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Vitals")
	float HealthPercent = 1.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Vitals")
	float ManaPercent = 1.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Vitals")
	float ExperiencePercent = 0.0f;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Inventory")
	TArray<FString> EquippedItems;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Inventory")
	TArray<FString> InventorySlots;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Skills")
	TArray<FString> LearnedSkills;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "ActionBars")
	TArray<FFableActionBarData> ActionBars;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Save")
	TArray<FFableSaveSlotMeta> SaveSlots;
};
