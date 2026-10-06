// Copyright Epic Games, Inc. All Rights Reserved.

#include "FableForgeGameMode.h"

#include "FableForgePlayerController.h"
#include "GameFramework/Pawn.h"
#include "UObject/ConstructorHelpers.h"
#include "Combat/TrainingEnemy.h"
#include "Engine/World.h"

AFableForgeGameMode::AFableForgeGameMode()
{
	PlayerControllerClass = AFableForgePlayerController::StaticClass();

	// Keep the template pawn blueprint so the shared base skeleton + animations stay intact.
	static ConstructorHelpers::FClassFinder<APawn> ThirdPersonPawnClass(TEXT("/Game/ThirdPerson/Blueprints/BP_ThirdPersonCharacter"));
	if (ThirdPersonPawnClass.Class != nullptr)
	{
		DefaultPawnClass = ThirdPersonPawnClass.Class;
	}
}

void AFableForgeGameMode::EnsureTrainingEnemy(AActor* Player)
{
	if (Player == nullptr || GetWorld() == nullptr || IsValid(TrainingEnemy)) return;

	const FVector PlayerLocation = Player->GetActorLocation();
	const FVector SpawnLocation = PlayerLocation + Player->GetActorForwardVector() * 280.0f + Player->GetActorRightVector() * 80.0f;
	const FRotator SpawnRotation = (PlayerLocation - SpawnLocation).Rotation();
	FActorSpawnParameters SpawnParams;
	SpawnParams.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AdjustIfPossibleButAlwaysSpawn;
	TrainingEnemy = GetWorld()->SpawnActor<ATrainingEnemy>(ATrainingEnemy::StaticClass(), SpawnLocation, SpawnRotation, SpawnParams);
	if (IsValid(TrainingEnemy))
	{
		UE_LOG(LogTemp, Display, TEXT("TRAINING_ENEMY_SPAWNED name=%s location=%s"), *GetNameSafe(TrainingEnemy), *TrainingEnemy->GetActorLocation().ToString());
	}
}
