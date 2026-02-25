// Copyright Epic Games, Inc. All Rights Reserved.

#include "FableForgePlayerController.h"

#include "Blueprint/AIBlueprintHelperLibrary.h"
#include "EnhancedInputSubsystems.h"
#include "Engine/LocalPlayer.h"
#include "InputMappingContext.h"
#include "InputCoreTypes.h"
#include "NavigationSystem.h"
#include "Blueprint/UserWidget.h"
#include "Components/InputComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "FableForgeCharacter.h"
#include "FableForge.h"
#include "GameFramework/Character.h"
#include "GameFramework/PawnMovementComponent.h"
#include "Interaction/FFChestInteractable.h"
#include "Interaction/FFInteractable.h"
#include "RPG/Save/FableSaveSubsystem.h"
#include "RPG/UI/FableCharacterMenuWidget.h"
#include "RPG/UI/FableChestWidget.h"
#include "RPG/UI/FableMainMenuWidget.h"
#include "RPG/UI/FablePartyHudWidget.h"
#include "Widgets/Input/SVirtualJoystick.h"

namespace
{
	const TCHAR* BaseCharacterMeshPath = TEXT("/Game/Characters/PlayableCharacter/Meshes/basecharacter.basecharacter");
	const TCHAR* LegacyBaseCharacterMeshPath = TEXT("/Game/Characters/Mannequins/Meshes/basecharacter.basecharacter");
}

void AFableForgePlayerController::BeginPlay()
{
	Super::BeginPlay();

	PrimaryActorTick.bCanEverTick = true;

	// only spawn touch controls on local player controllers
	if (ShouldUseTouchControls() && IsLocalPlayerController())
	{
		MobileControlsWidget = CreateWidget<UUserWidget>(this, MobileControlsWidgetClass);
		if (MobileControlsWidget)
		{
			MobileControlsWidget->AddToPlayerScreen(0);
		}
		else
		{
			UE_LOG(LogFableForge, Error, TEXT("Could not spawn mobile controls widget."));
		}
	}

	if (bShowMainMenuOnBeginPlay)
	{
		ShowMainMenu();
	}
	else
	{
		FInputModeGameAndUI InputMode;
		InputMode.SetHideCursorDuringCapture(false);
		InputMode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
		SetInputMode(InputMode);
		bShowMouseCursor = true;
		bEnableClickEvents = true;
		bEnableMouseOverEvents = true;
	}
}

void AFableForgePlayerController::OnPossess(APawn* InPawn)
{
	Super::OnPossess(InPawn);
	ApplyActiveCharacterMesh();
}

void AFableForgePlayerController::SetupInputComponent()
{
	Super::SetupInputComponent();

	if (IsLocalPlayerController())
	{
		// Fallback defaults so gameplay input still works if these arrays were never configured in editor.
		auto AddContextIfMissing = [](TArray<UInputMappingContext*>& ContextArray, UInputMappingContext* Context)
		{
			if (Context != nullptr && !ContextArray.Contains(Context))
			{
				ContextArray.Add(Context);
			}
		};

		if (DefaultMappingContexts.IsEmpty())
		{
			AddContextIfMissing(DefaultMappingContexts, LoadObject<UInputMappingContext>(nullptr, TEXT("/Game/Input/IMC_Default.IMC_Default")));
		}

		if (MobileExcludedMappingContexts.IsEmpty())
		{
			AddContextIfMissing(MobileExcludedMappingContexts, LoadObject<UInputMappingContext>(nullptr, TEXT("/Game/Input/IMC_MouseLook.IMC_MouseLook")));
		}

		if (UEnhancedInputLocalPlayerSubsystem* Subsystem = ULocalPlayer::GetSubsystem<UEnhancedInputLocalPlayerSubsystem>(GetLocalPlayer()))
		{
			for (UInputMappingContext* CurrentContext : DefaultMappingContexts)
			{
				Subsystem->AddMappingContext(CurrentContext, 0);
			}

			if (!ShouldUseTouchControls())
			{
				for (UInputMappingContext* CurrentContext : MobileExcludedMappingContexts)
				{
					Subsystem->AddMappingContext(CurrentContext, 0);
				}
			}
		}
	}

	if (InputComponent != nullptr)
	{
		InputComponent->BindKey(EKeys::I, IE_Pressed, this, &AFableForgePlayerController::ToggleCharacterMenu);
		FInputKeyBinding& InteractClickBinding = InputComponent->BindKey(EKeys::LeftMouseButton, IE_Released, this, &AFableForgePlayerController::HandlePrimaryInteractClick);
		InteractClickBinding.bConsumeInput = false;
	}
}

void AFableForgePlayerController::PlayerTick(float DeltaTime)
{
	Super::PlayerTick(DeltaTime);

	UpdateHoveredInteractable();

	if (!IsValid(PendingInteractionActor))
	{
		return;
	}

	if (IsGameInteractionBlocked())
	{
		return;
	}

	TryInteractWithActor(PendingInteractionActor);
}

void AFableForgePlayerController::EnterGameFromCharacterSlot(const FGuid& CharacterId, int32 SlotIndex, bool bCreateNewSave)
{
	UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	if (SaveSubsystem == nullptr || !CharacterId.IsValid())
	{
		return;
	}

	const FString MapName = GetWorld() ? GetWorld()->GetMapName() : TEXT("");
	bool bSuccess = false;
	if (bCreateNewSave)
	{
		bSuccess = SaveSubsystem->SaveCharacterToSlot(CharacterId, SlotIndex, MapName);
		if (bSuccess)
		{
			bSuccess = SaveSubsystem->LoadCharacterFromSlot(CharacterId, SlotIndex) != nullptr;
		}
	}
	else
	{
		bSuccess = SaveSubsystem->LoadCharacterFromSlot(CharacterId, SlotIndex) != nullptr;
	}

	if (!bSuccess)
	{
		UE_LOG(LogFableForge, Warning, TEXT("Could not load/save character slot. CharacterId=%s Slot=%d"), *CharacterId.ToString(), SlotIndex);
		return;
	}

	ApplyActiveCharacterMesh();

	EnsureUiWidgets();
	RefreshHudData();

	if (MainMenuWidget != nullptr)
	{
		MainMenuWidget->RemoveFromParent();
	}

	if (PartyHudWidget != nullptr)
	{
		PartyHudWidget->SetVisibility(ESlateVisibility::Visible);
	}
	if (CharacterMenuWidget != nullptr)
	{
		CharacterMenuWidget->Close();
	}
	CloseChest();

	FInputModeGameAndUI InputMode;
	InputMode.SetHideCursorDuringCapture(false);
	InputMode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
	InputMode.SetWidgetToFocus(ChestWidget->TakeWidget());
	SetInputMode(InputMode);
	bShowMouseCursor = true;
	bEnableClickEvents = true;
	bEnableMouseOverEvents = true;
}

void AFableForgePlayerController::ShowMainMenu()
{
	EnsureUiWidgets();

	if (MainMenuWidget == nullptr)
	{
		MainMenuWidget = CreateWidget<UFableMainMenuWidget>(this, UFableMainMenuWidget::StaticClass());
	}

	if (MainMenuWidget == nullptr)
	{
		return;
	}

	if (!MainMenuWidget->IsInViewport())
	{
		MainMenuWidget->AddToViewport(100);
	}

	MainMenuWidget->OpenMainMenu();

	if (PartyHudWidget != nullptr)
	{
		PartyHudWidget->SetVisibility(ESlateVisibility::Collapsed);
	}

	if (CharacterMenuWidget != nullptr)
	{
		CharacterMenuWidget->Close();
	}

	CloseChest();

	FInputModeUIOnly InputMode;
	SetInputMode(InputMode);
	bShowMouseCursor = true;
}

void AFableForgePlayerController::NotifyManualMoveInput()
{
	if (ChestWidget != nullptr && ChestWidget->IsChestOpen())
	{
		CloseChest();
	}

	if (!IsValid(PendingInteractionActor))
	{
		return;
	}

	StopMovement();
	if (APawn* ControlledPawn = GetPawn())
	{
		if (UPawnMovementComponent* MovementComponent = ControlledPawn->GetMovementComponent())
		{
			MovementComponent->StopMovementImmediately();
		}
	}

	UE_LOG(LogFableForge, Log, TEXT("Interaction move canceled by manual movement input."));
	ClearPendingInteraction();
}

void AFableForgePlayerController::ToggleCharacterMenu()
{
	EnsureUiWidgets();
	if (CharacterMenuWidget != nullptr)
	{
		CharacterMenuWidget->Toggle();

		if (CharacterMenuWidget->IsOpen())
		{
			FInputModeGameAndUI InputMode;
			InputMode.SetHideCursorDuringCapture(false);
			InputMode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
			SetInputMode(InputMode);
			bShowMouseCursor = true;
			bEnableClickEvents = true;
			bEnableMouseOverEvents = true;
			SetIgnoreLookInput(true);
			SetIgnoreMoveInput(true);
		}
		else
		{
			FInputModeGameAndUI InputMode;
			InputMode.SetHideCursorDuringCapture(false);
			InputMode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
			SetInputMode(InputMode);
			bShowMouseCursor = true;
			bEnableClickEvents = true;
			bEnableMouseOverEvents = true;
			ResetIgnoreLookInput();
			ResetIgnoreMoveInput();
		}
	}
}

void AFableForgePlayerController::OpenChest(AFFChestInteractable* Chest)
{
	if (!IsValid(Chest))
	{
		return;
	}

	EnsureUiWidgets();
	if (ChestWidget == nullptr)
	{
		return;
	}

	ChestWidget->OpenForChest(Chest, this);

	FInputModeGameAndUI InputMode;
	InputMode.SetHideCursorDuringCapture(false);
	InputMode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
	InputMode.SetWidgetToFocus(ChestWidget->TakeWidget());
	SetInputMode(InputMode);
	bShowMouseCursor = true;
	bEnableClickEvents = true;
	bEnableMouseOverEvents = true;
}

void AFableForgePlayerController::CloseChest()
{
	if (ChestWidget != nullptr)
	{
		ChestWidget->CloseChest();
	}

	FInputModeGameAndUI InputMode;
	InputMode.SetHideCursorDuringCapture(false);
	InputMode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
	SetInputMode(InputMode);
	bShowMouseCursor = true;
	bEnableClickEvents = true;
	bEnableMouseOverEvents = true;
}

bool AFableForgePlayerController::ShouldUseTouchControls() const
{
	return SVirtualJoystick::ShouldDisplayTouchInterface() || bForceTouchControls;
}

void AFableForgePlayerController::ApplyActiveCharacterMesh()
{
	ACharacter* ControlledCharacter = Cast<ACharacter>(GetPawn());
	if (ControlledCharacter == nullptr || ControlledCharacter->GetMesh() == nullptr)
	{
		return;
	}

	USkeletalMesh* CharacterMesh = LoadObject<USkeletalMesh>(nullptr, BaseCharacterMeshPath);
	if (CharacterMesh == nullptr)
	{
		CharacterMesh = LoadObject<USkeletalMesh>(nullptr, LegacyBaseCharacterMeshPath);
	}
	if (CharacterMesh == nullptr)
	{
		UE_LOG(LogFableForge, Warning, TEXT("Failed to load base character mesh. Tried '%s' and '%s'."),
			BaseCharacterMeshPath, LegacyBaseCharacterMeshPath);
		return;
	}

	USkeletalMeshComponent* MeshComponent = ControlledCharacter->GetMesh();
	UClass* ExistingAnimClass = MeshComponent->GetAnimClass();
	MeshComponent->SetSkeletalMesh(CharacterMesh);
	if (ExistingAnimClass != nullptr)
	{
		MeshComponent->SetAnimInstanceClass(ExistingAnimClass);
	}

	if (AFableForgeCharacter* ForgeCharacter = Cast<AFableForgeCharacter>(ControlledCharacter))
	{
		ForgeCharacter->RefreshEquipmentVisualsFromSave();
	}

	UE_LOG(LogFableForge, Log, TEXT("Applied base character mesh to pawn '%s'."),
		*GetNameSafe(ControlledCharacter));
}

void AFableForgePlayerController::EnsureUiWidgets()
{
	if (CharacterMenuWidget == nullptr)
	{
		CharacterMenuWidget = CreateWidget<UFableCharacterMenuWidget>(this, UFableCharacterMenuWidget::StaticClass());
		if (CharacterMenuWidget != nullptr)
		{
			CharacterMenuWidget->AddToViewport(25);
			CharacterMenuWidget->Close();
		}
	}

	if (PartyHudWidget == nullptr)
	{
		PartyHudWidget = CreateWidget<UFablePartyHudWidget>(this, UFablePartyHudWidget::StaticClass());
		if (PartyHudWidget != nullptr)
		{
			PartyHudWidget->AddToViewport(10);
			PartyHudWidget->SetCharacterMenuWidget(CharacterMenuWidget);
			PartyHudWidget->SetVisibility(ESlateVisibility::Collapsed);
		}
	}

	if (ChestWidgetClass == nullptr)
	{
		ChestWidgetClass = UFableChestWidget::StaticClass();
	}

	if (ChestWidget == nullptr)
	{
		ChestWidget = CreateWidget<UFableChestWidget>(this, ChestWidgetClass);
		if (ChestWidget != nullptr)
		{
			ChestWidget->AddToViewport(40);
			ChestWidget->SetVisibility(ESlateVisibility::Collapsed);
		}
	}
}

void AFableForgePlayerController::RefreshHudData()
{
	if (PartyHudWidget != nullptr)
	{
		PartyHudWidget->RefreshFromSaveData();
	}
}

void AFableForgePlayerController::HandlePrimaryInteractClick()
{
	if (IsGameInteractionBlocked())
	{
		UE_LOG(LogFableForge, Log, TEXT("Interact click ignored: game interaction currently blocked by UI."));
		return;
	}

	FHitResult HitResult;
	if (!GetHitResultUnderCursor(ECC_Visibility, false, HitResult))
	{
		UE_LOG(LogFableForge, Log, TEXT("Interact click missed: no visibility hit under cursor."));
		ClearPendingInteraction();
		return;
	}

	AActor* HitActor = HitResult.GetActor();
	if (!IsActorInteractable(HitActor))
	{
		UE_LOG(LogFableForge, Log, TEXT("Interact click hit non-interactable actor: %s (%s)"),
			*GetNameSafe(HitActor),
			*GetNameSafe(HitActor ? HitActor->GetClass() : nullptr));
		ClearPendingInteraction();
		return;
	}

	if (!IsActorWithinSelectionDistance(HitActor))
	{
		UE_LOG(LogFableForge, Log, TEXT("Interact click ignored: %s is beyond max selection distance %.1f"),
			*GetNameSafe(HitActor),
			MaxInteractableSelectionDistance);
		ClearPendingInteraction();
		return;
	}

	PendingInteractionActor = HitActor;
	TryInteractWithActor(HitActor);

	if (!IsValid(PendingInteractionActor))
	{
		return;
	}

	FVector MoveLocation = HitResult.ImpactPoint;
	if (!HitResult.bBlockingHit)
	{
		MoveLocation = IFFInteractable::Execute_GetInteractionLocation(HitActor);
	}

	if (UNavigationSystemV1* NavSystem = FNavigationSystem::GetCurrent<UNavigationSystemV1>(GetWorld()))
	{
		FNavLocation ProjectedLocation;
		if (NavSystem->ProjectPointToNavigation(MoveLocation, ProjectedLocation, FVector(250.0f, 250.0f, 500.0f)))
		{
			MoveLocation = ProjectedLocation.Location;
		}
		else
		{
			UE_LOG(LogFableForge, Warning, TEXT("Interact click: could not project interaction point to navmesh for %s. Using raw location."),
				*GetNameSafe(HitActor));
		}
	}

	PendingInteractionApproachLocation = MoveLocation;
	bHasPendingInteractionApproachLocation = true;

	UAIBlueprintHelperLibrary::SimpleMoveToLocation(this, MoveLocation);
	UE_LOG(LogFableForge, Log, TEXT("Interact click: moving toward %s at %s"),
		*GetNameSafe(HitActor),
		*MoveLocation.ToCompactString());
}

void AFableForgePlayerController::UpdateHoveredInteractable()
{
	if (IsGameInteractionBlocked())
	{
		ClearHoveredInteractable();
		return;
	}

	FHitResult HitResult;
	AActor* NewHoveredActor = nullptr;
	if (GetHitResultUnderCursor(ECC_Visibility, false, HitResult))
	{
		AActor* HitActor = HitResult.GetActor();
		if (IsActorInteractable(HitActor) && IsActorWithinSelectionDistance(HitActor))
		{
			NewHoveredActor = HitActor;
		}
	}

	if (HoveredInteractableActor == NewHoveredActor)
	{
		return;
	}

	if (IsActorInteractable(HoveredInteractableActor))
	{
		IFFInteractable::Execute_SetHighlighted(HoveredInteractableActor, false);
	}

	HoveredInteractableActor = NewHoveredActor;
	if (IsActorInteractable(HoveredInteractableActor))
	{
		IFFInteractable::Execute_SetHighlighted(HoveredInteractableActor, true);
	}
}

bool AFableForgePlayerController::IsActorInteractable(const AActor* Actor) const
{
	return IsValid(Actor) && Actor->GetClass()->ImplementsInterface(UFFInteractable::StaticClass());
}

bool AFableForgePlayerController::IsActorWithinSelectionDistance(const AActor* Actor) const
{
	if (!IsActorInteractable(Actor))
	{
		return false;
	}

	const APawn* ControlledPawn = GetPawn();
	if (!IsValid(ControlledPawn))
	{
		return false;
	}

	const FVector InteractionLocation = IFFInteractable::Execute_GetInteractionLocation(const_cast<AActor*>(Actor));
	const float DistanceToTarget = FVector::Dist2D(ControlledPawn->GetActorLocation(), InteractionLocation);
	return DistanceToTarget <= MaxInteractableSelectionDistance;
}

bool AFableForgePlayerController::TryInteractWithActor(AActor* Actor)
{
	if (!IsActorInteractable(Actor))
	{
		return false;
	}

	APawn* ControlledPawn = GetPawn();
	if (!IsValid(ControlledPawn))
	{
		return false;
	}

	if (!IFFInteractable::Execute_CanInteract(Actor, ControlledPawn))
	{
		UE_LOG(LogFableForge, Log, TEXT("Interact attempt blocked by interactable CanInteract: %s"), *GetNameSafe(Actor));
		ClearPendingInteraction();
		return false;
	}

	FVector InteractionLocation = IFFInteractable::Execute_GetInteractionLocation(Actor);
	if (bHasPendingInteractionApproachLocation && PendingInteractionActor == Actor)
	{
		InteractionLocation = PendingInteractionApproachLocation;
	}
	const float RequiredRange = IFFInteractable::Execute_GetInteractionRange(Actor) + InteractionDistancePadding;
	const float DistanceToTarget = FVector::Dist2D(ControlledPawn->GetActorLocation(), InteractionLocation);

	if (DistanceToTarget > RequiredRange)
	{
		UE_LOG(LogFableForge, Log, TEXT("Interact pending: %s out of range (distance %.1f > required %.1f)"),
			*GetNameSafe(Actor),
			DistanceToTarget,
			RequiredRange);
		return false;
	}

	IFFInteractable::Execute_Interact(Actor, ControlledPawn);
	UE_LOG(LogFableForge, Log, TEXT("Interact executed: %s"), *GetNameSafe(Actor));
	ClearPendingInteraction();
	return true;
}

bool AFableForgePlayerController::IsGameInteractionBlocked() const
{
	if (MainMenuWidget != nullptr && MainMenuWidget->IsInViewport() && MainMenuWidget->GetVisibility() != ESlateVisibility::Collapsed)
	{
		return true;
	}

	if (CharacterMenuWidget != nullptr && CharacterMenuWidget->IsInViewport() && CharacterMenuWidget->IsOpen())
	{
		return true;
	}

	return ChestWidget != nullptr && ChestWidget->IsInViewport() && ChestWidget->IsChestOpen();
}

void AFableForgePlayerController::ClearHoveredInteractable()
{
	if (IsActorInteractable(HoveredInteractableActor))
	{
		IFFInteractable::Execute_SetHighlighted(HoveredInteractableActor, false);
	}

	HoveredInteractableActor = nullptr;
}

void AFableForgePlayerController::ClearPendingInteraction()
{
	PendingInteractionActor = nullptr;
	PendingInteractionApproachLocation = FVector::ZeroVector;
	bHasPendingInteractionApproachLocation = false;
}
