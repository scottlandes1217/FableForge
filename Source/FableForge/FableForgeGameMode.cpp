// Copyright Epic Games, Inc. All Rights Reserved.

#include "FableForgeGameMode.h"

#include "FableForgePlayerController.h"
#include "GameFramework/Pawn.h"
#include "UObject/ConstructorHelpers.h"

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
