// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "FableForgeGameMode.generated.h"

class ATrainingEnemy;

/**
 *  Core GameMode for FableForge runtime flow.
 */
UCLASS()
class AFableForgeGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	AFableForgeGameMode();
	void EnsureTrainingEnemy(AActor* Player);

private:
	UPROPERTY(Transient)
	TObjectPtr<class ATrainingEnemy> TrainingEnemy;
};
