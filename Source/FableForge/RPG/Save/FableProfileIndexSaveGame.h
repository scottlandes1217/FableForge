#pragma once

#include "CoreMinimal.h"
#include "GameFramework/SaveGame.h"
#include "RPG/Data/FableForgeRPGTypes.h"
#include "FableProfileIndexSaveGame.generated.h"

UCLASS()
class UFableProfileIndexSaveGame : public USaveGame
{
	GENERATED_BODY()

public:
	UPROPERTY()
	TArray<FFableCharacterProfile> Characters;

	UPROPERTY()
	FGuid ActiveCharacterId;

	UPROPERTY()
	int32 ActiveSlotIndex = INDEX_NONE;
};
