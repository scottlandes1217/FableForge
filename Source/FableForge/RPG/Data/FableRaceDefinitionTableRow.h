#pragma once

#include "CoreMinimal.h"
#include "Engine/DataTable.h"
#include "FableRaceDefinitionTableRow.generated.h"

USTRUCT(BlueprintType)
struct FFableRaceDefinitionTableRow : public FTableRowBase
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Race")
	FString Id;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Race")
	FString DisplayName;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Race")
	FString Description;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Race")
	FString Image;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Vitals")
	int32 BaseHitPoints = 10;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Vitals")
	int32 BaseMana = 0;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Vitals")
	int32 BaseEnergy = 0;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Vitals")
	int32 BaseRage = 0;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Ability Bonuses")
	int32 Strength = 0;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Ability Bonuses")
	int32 Dexterity = 0;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Ability Bonuses")
	int32 Constitution = 0;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Ability Bonuses")
	int32 Intelligence = 0;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Ability Bonuses")
	int32 Wisdom = 0;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Ability Bonuses")
	int32 Charisma = 0;
};
