#pragma once

#include "CoreMinimal.h"
#include "GameFramework/SaveGame.h"
#include "RPG/Data/FableForgeRPGTypes.h"
#include "FableCharacterSaveGame.generated.h"

UCLASS()
class UFableCharacterSaveGame : public USaveGame
{
	GENERATED_BODY()

public:
	UPROPERTY()
	FGuid CharacterId;

	UPROPERTY()
	FString CharacterName;

	UPROPERTY()
	FString RaceId;

	UPROPERTY()
	EFableGender Gender = EFableGender::Male;

	UPROPERTY()
	int32 SlotIndex = 0;

	UPROPERTY()
	FString SavedAtUtc;

	UPROPERTY()
	FString MapName;

	UPROPERTY()
	TArray<FString> CompanionNames;

	UPROPERTY()
	float HealthPercent = 1.0f;

	UPROPERTY()
	float ManaPercent = 1.0f;

	UPROPERTY()
	float ExperiencePercent = 0.0f;

	UPROPERTY()
	TArray<FString> EquippedItems;

	UPROPERTY()
	TArray<FString> InventoryItems;

	UPROPERTY()
	TArray<FString> LearnedSkills;

	UPROPERTY()
	TArray<FString> BuildQueue;

	UPROPERTY()
	TArray<FFableActionBarData> ActionBars;
};
