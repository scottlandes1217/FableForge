// Copyright Epic Games, Inc. All Rights Reserved.

#include "FableForgePlayerController.h"

#include "Blueprint/AIBlueprintHelperLibrary.h"
#include "EnhancedInputSubsystems.h"
#include "Engine/LocalPlayer.h"
#include "Engine/GameViewportClient.h"
#include "InputMappingContext.h"
#include "InputCoreTypes.h"
#include "NavigationSystem.h"
#include "Blueprint/UserWidget.h"
#include "Blueprint/WidgetBlueprintLibrary.h"
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
#include "RPG/UI/FableTimeWheelWidget.h"
#include "RPG/UI/FableWheelAssignmentWidget.h"
#include "RPG/Data/FableSkillSystemTableRows.h"
#include "RPG/Data/FableItemDefinitionTableRow.h"
#include "RPG/Gameplay/FableSpellRuntime.h"
#include "Variant_Combat/Interfaces/CombatDamageable.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Animation/AnimSequence.h"
#include "Animation/AnimSequenceBase.h"
#include "Animation/AnimMontage.h"
#include "Animation/AnimInstance.h"
#include "TimerManager.h"
#include "DrawDebugHelpers.h"
#include "Engine/DataTable.h"
#include "Widgets/Input/SVirtualJoystick.h"
#include "HAL/PlatformTime.h"
#include "Components/PrimitiveComponent.h"
#include "FableForgeGameMode.h"

namespace
{
	const TCHAR* BaseCharacterMeshPath = TEXT("/Game/Characters/PlayableCharacter/Meshes/basecharacter.basecharacter");
	const TCHAR* LegacyBaseCharacterMeshPath = TEXT("/Game/Characters/Mannequins/Meshes/basecharacter.basecharacter");
}

void AFableForgePlayerController::BeginPlay()
{
	Super::BeginPlay();

	PrimaryActorTick.bCanEverTick = true;
	PrimaryActorTick.bTickEvenWhenPaused = true;
	bShouldPerformFullTickWhenPaused = true;
	MaxCosmicEnergy = FMath::Max(0.0f, MaxCosmicEnergy);
	CosmicDrainPerSecond = FMath::Max(0.0f, CosmicDrainPerSecond);
	CosmicRecoveryPerSecond = FMath::Max(0.0f, CosmicRecoveryPerSecond);
	CosmicEnergy = MaxCosmicEnergy;
	MaxMana = 100.0f;
	Mana = MaxMana;
	LastCosmicWallTimeSeconds = FPlatformTime::Seconds();

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
	if (AFableForgeCharacter* Character = Cast<AFableForgeCharacter>(InPawn))
	{
		// Aim-facing locomotion: looking turns the body, while left-stick input
		// strafes relative to that heading. Override legacy Blueprint defaults too.
		Character->bUseControllerRotationYaw = true;
		Character->GetCharacterMovement()->bOrientRotationToMovement = false;
		Character->GetCharacterMovement()->bUseControllerDesiredRotation = false;
	}
	ApplyActiveCharacterMesh();
	ResetIgnoreLookInput();
	ResetIgnoreMoveInput();
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
		InputComponent->BindKey(EKeys::Escape, IE_Pressed, this, &AFableForgePlayerController::CloseActivePanel);
		FInputKeyBinding& InteractClickBinding = InputComponent->BindKey(EKeys::LeftMouseButton, IE_Released, this, &AFableForgePlayerController::HandlePrimaryInteractClick);
		InteractClickBinding.bConsumeInput = false;

		// DualSense gameplay layer. These bindings intentionally live beside the
		// existing Enhanced Input assets so the prototype remains usable before the
		// new controller actions are authored in the editor.
		InputComponent->BindKey(EKeys::Gamepad_DPad_Up, IE_Pressed, this, &AFableForgePlayerController::HandleDPadUp);
		InputComponent->BindKey(EKeys::Gamepad_DPad_Down, IE_Pressed, this, &AFableForgePlayerController::HandleDPadDown);
		InputComponent->BindKey(EKeys::Gamepad_DPad_Left, IE_Pressed, this, &AFableForgePlayerController::HandleDPadLeft);
		InputComponent->BindKey(EKeys::Gamepad_DPad_Right, IE_Pressed, this, &AFableForgePlayerController::HandleDPadRight);
		InputComponent->BindKey(EKeys::Gamepad_DPad_Up, IE_Released, this, &AFableForgePlayerController::HandleElementReleased);
		InputComponent->BindKey(EKeys::Gamepad_DPad_Down, IE_Released, this, &AFableForgePlayerController::HandleElementReleased);
		InputComponent->BindKey(EKeys::Gamepad_DPad_Left, IE_Released, this, &AFableForgePlayerController::HandleElementReleased);
		InputComponent->BindKey(EKeys::Gamepad_DPad_Right, IE_Released, this, &AFableForgePlayerController::HandleElementReleased);
		InputComponent->BindKey(EKeys::Gamepad_LeftShoulder, IE_Pressed, this, &AFableForgePlayerController::HandleTimePressed);
		InputComponent->BindKey(EKeys::Gamepad_LeftShoulder, IE_Released, this, &AFableForgePlayerController::HandleTimeReleased);
		InputComponent->BindKey(EKeys::Gamepad_RightShoulder, IE_Pressed, this, &AFableForgePlayerController::HandleQuickWheelPressed);
		InputComponent->BindKey(EKeys::Gamepad_RightShoulder, IE_Released, this, &AFableForgePlayerController::HandleQuickWheelReleased);
		InputComponent->BindKey(EKeys::Gamepad_RightTrigger, IE_Pressed, this, &AFableForgePlayerController::HandleRightTriggerPressed);
		InputComponent->BindKey(EKeys::Gamepad_RightTrigger, IE_Released, this, &AFableForgePlayerController::HandleRightTriggerReleased);
		InputComponent->BindKey(EKeys::Gamepad_LeftTrigger, IE_Pressed, this, &AFableForgePlayerController::HandleLeftTriggerPressed);
		InputComponent->BindKey(EKeys::Gamepad_LeftTrigger, IE_Released, this, &AFableForgePlayerController::HandleLeftTriggerReleased);
		InputComponent->BindKey(EKeys::Gamepad_RightThumbstick, IE_Pressed, this, &AFableForgePlayerController::ToggleFirstPersonView);
		InputComponent->BindKey(EKeys::Gamepad_LeftThumbstick, IE_Pressed, this, &AFableForgePlayerController::ToggleSlowTime);
		InputComponent->BindKey(EKeys::Gamepad_FaceButton_Right, IE_Pressed, this, &AFableForgePlayerController::CancelTargetedSkill);
		InputComponent->BindKey(EKeys::Gamepad_FaceButton_Bottom, IE_Pressed, this, &AFableForgePlayerController::HandleControllerActivate);
		InputComponent->BindKey(EKeys::Gamepad_FaceButton_Bottom, IE_Released, this, &AFableForgePlayerController::HandleControllerActivateReleased);
		InputComponent->BindKey(EKeys::Gamepad_FaceButton_Top, IE_Pressed, this, &AFableForgePlayerController::HandleFocusedInteract);
		InputComponent->BindKey(EKeys::Gamepad_Special_Right, IE_Pressed, this, &AFableForgePlayerController::ToggleCharacterMenu);
		// Read stick state once in PlayerTick. Enhanced Input consumes the legacy
		// look mappings, so binding those same axes here can yield zero values.
		InputComponent->BindAxis(TEXT("FF_RightTrigger"), this, &AFableForgePlayerController::HandleRightTrigger);
		InputComponent->BindAxis(TEXT("FF_LeftTrigger"), this, &AFableForgePlayerController::HandleLeftTrigger);
		for (int32 Index = 0; Index < InputComponent->GetNumActionBindings(); ++Index) InputComponent->GetActionBinding(Index).bExecuteWhenPaused = true;
		for (FInputKeyBinding& Binding : InputComponent->KeyBindings) Binding.bExecuteWhenPaused = true;
		for (FInputAxisBinding& Binding : InputComponent->AxisBindings) Binding.bExecuteWhenPaused = true;
	}
}

void AFableForgePlayerController::PlayerTick(float DeltaTime)
{
	Super::PlayerTick(DeltaTime);
	// Recover from a missed release/focus change, but retain the same-frame
	// guard through all legacy and Enhanced Input callbacks.
	if (bJumpPressConsumed && JumpConsumedFrame != GFrameCounter
		&& !IsInputKeyDown(EKeys::Gamepad_FaceButton_Bottom)) bJumpPressConsumed = false;
	// Slate/platform Y is up-positive. FSceneViewport already converts RightY
	// to screen-space down-positive before PlayerInput; do not flip it twice.
	RightStickValue = FVector2D(GetInputAnalogKeyState(EKeys::Gamepad_RightX), GetInputAnalogKeyState(EKeys::Gamepad_RightY));
	const double WallNowSeconds = FPlatformTime::Seconds();
	const float InputDeltaSeconds = LastCosmicWallTimeSeconds > 0.0
		? FMath::Clamp(static_cast<float>(WallNowSeconds - LastCosmicWallTimeSeconds), 0.f, .1f) : DeltaTime;
	UpdateCosmicEnergy(WallNowSeconds);
	if (Mana < MaxMana)
	{
		Mana = FMath::Min(MaxMana, Mana + FMath::Max(0.0f, ManaRecoveryPerSecond) * InputDeltaSeconds);
	}
	if (ChestWidget != nullptr && ChestWidget->IsChestOpen())
	{
		RightStickValue = FVector2D::ZeroVector;
		return;
	}
	if (IsJournalOpen() || IsWheelAssignmentOpen())
	{
		UpdateHoveredInteractable();
		return;
	}
	if (TimeWheelWidget != nullptr && TimeWheelWidget->IsOpen() && !bTargetingSkill && RightStickValue.SizeSquared() > 0.08f)
	{
		TimeWheelWidget->SetSelectionFromStick(RightStickValue);
	}

	if (bTargetingSkill) UpdatePrecisionTarget(InputDeltaSeconds);
	else if (bElementHeld && !bCosmicWheelOpen && !bQuickWheelHeld) UpdateElementGesture(InputDeltaSeconds);

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

void AFableForgePlayerController::HandleDPadUp()
{
	if (IsWheelAssignmentOpen()) return;
	if (MainMenuWidget && MainMenuWidget->IsControllerMenuActive()) { MainMenuWidget->MoveControllerSelection(-1); return; }
	if (ChestWidget && ChestWidget->IsChestOpen()) { if (!ChestWidget->HasAnyUserFocus()) ChestWidget->MoveControllerSelection(-1); return; }
	if (IsJournalOpen())
	{
		if (!IsControllerUiInputHandledByFocusedWidget()) CharacterMenuWidget->MoveControllerSelection(0, -1);
		return;
	}
	BeginElementGesture(TEXT("Air"));
}
void AFableForgePlayerController::HandleDPadDown()
{
	if (IsWheelAssignmentOpen()) return;
	if (MainMenuWidget && MainMenuWidget->IsControllerMenuActive()) { MainMenuWidget->MoveControllerSelection(1); return; }
	if (ChestWidget && ChestWidget->IsChestOpen()) { if (!ChestWidget->HasAnyUserFocus()) ChestWidget->MoveControllerSelection(1); return; }
	if (IsJournalOpen())
	{
		if (!IsControllerUiInputHandledByFocusedWidget()) CharacterMenuWidget->MoveControllerSelection(0, 1);
		return;
	}
	BeginElementGesture(TEXT("Earth"));
}
void AFableForgePlayerController::HandleDPadLeft()
{
	if (IsWheelAssignmentOpen()) return;
	if (MainMenuWidget && MainMenuWidget->IsControllerMenuActive()) { MainMenuWidget->MoveControllerSelection(-1); return; }
	if (ChestWidget && ChestWidget->IsChestOpen()) { if (!ChestWidget->HasAnyUserFocus()) ChestWidget->MoveControllerSelection(-1); return; }
	if (IsJournalOpen())
	{
		if (!IsControllerUiInputHandledByFocusedWidget()) CharacterMenuWidget->MoveControllerSelection(-1, 0);
		return;
	}
	if (TimeWheelWidget && TimeWheelWidget->IsOpen()) { HandleQuickWheelPrevious(); return; }
	BeginElementGesture(TEXT("Water"));
}
void AFableForgePlayerController::HandleDPadRight()
{
	if (IsWheelAssignmentOpen()) return;
	if (MainMenuWidget && MainMenuWidget->IsControllerMenuActive()) { MainMenuWidget->MoveControllerSelection(1); return; }
	if (ChestWidget && ChestWidget->IsChestOpen()) { if (!ChestWidget->HasAnyUserFocus()) ChestWidget->MoveControllerSelection(1); return; }
	if (IsJournalOpen())
	{
		if (!IsControllerUiInputHandledByFocusedWidget()) CharacterMenuWidget->MoveControllerSelection(1, 0);
		return;
	}
	if (TimeWheelWidget && TimeWheelWidget->IsOpen()) { HandleQuickWheelNext(); return; }
	BeginElementGesture(TEXT("Fire"));
}
void AFableForgePlayerController::HandleElementReleased()
{
	if (ChestWidget != nullptr && ChestWidget->IsChestOpen()) { ResetGameplayInputForChest(); return; }
	if (IsJournalOpen() || IsWheelAssignmentOpen())
	{
		bElementHeld = false;
		return;
	}
	// A physical flick commonly returns to center on the D-pad release frame.
	// Finish an already-started stroke before dropping ownership of the stick.
	if (bElementHeld && !bTargetingSkill && !bCosmicWheelOpen && !bQuickWheelHeld)
	{
		RightStickValue = FVector2D(GetInputAnalogKeyState(EKeys::Gamepad_RightX), GetInputAnalogKeyState(EKeys::Gamepad_RightY));
		UpdateElementGesture(0.f);
	}
	bElementHeld = false;
	bGestureHasStroke = false;
	bGestureNeedsNeutral = false;
	if (!bWheelInputCaptured && !bTargetingSkill && !IsGameInteractionBlocked())
	{
		SetInputMode(FInputModeGameAndUI());
		UWidgetBlueprintLibrary::SetFocusToGameViewport();
	}
}

void AFableForgePlayerController::BeginElementGesture(FName Element)
{
	if (bTargetingSkill || bCosmicWheelOpen || bQuickWheelHeld) return;
	ActiveElement = Element;
	bElementHeld = true;
	GestureTravel = GestureTurn = 0.f;
	bGestureHasStroke = false;
	// Accept a stroke started at the same time as the D-pad press. Requiring
	// neutral here silently discarded the first gesture on physical hardware.
	bGestureNeedsNeutral = false;
	SetInputMode(FInputModeGameOnly());
	UWidgetBlueprintLibrary::SetFocusToGameViewport();
}

void AFableForgePlayerController::UpdateElementGesture(float RealDeltaSeconds)
{
	const float Magnitude = RightStickValue.Size();
	if (bGestureNeedsNeutral)
	{
		if (Magnitude < .22f) { bGestureNeedsNeutral = false; bGestureHasStroke = false; GestureTravel = GestureTurn = 0.f; }
		return;
	}
	bool bComplete = false;
	bool bCircle = false;
	if (Magnitude > .45f)
	{
		const float Angle = FMath::Atan2(RightStickValue.Y, RightStickValue.X);
		if (bGestureHasStroke) GestureTurn += FMath::FindDeltaAngleRadians(LastGestureAngle, Angle);
		LastGestureAngle = Angle;
		bGestureHasStroke = true;
		GestureTravel += RealDeltaSeconds;
		bCircle = FMath::Abs(GestureTurn) >= 5.2f;
		bComplete = bCircle;
	}
	else if (Magnitude < .22f && bGestureHasStroke)
	{
		// Returning the stick completes a flick; releasing the element is never
		// required. A full circle resolves immediately while the stick is out.
		bComplete = true; // A fast one-frame flick is still a deliberate stroke.
	}
	if (!bComplete) return;
	const FString Spell = ActiveElement == TEXT("Fire") ? (bCircle ? TEXT("fire_tornado") : TEXT("fireball"))
		: ActiveElement == TEXT("Water") ? TEXT("heal_wave") : ActiveElement == TEXT("Earth") ? TEXT("stone_spike") : TEXT("gust");
	bGestureNeedsNeutral = true;
	bGestureHasStroke = false;
	GestureTravel = GestureTurn = 0.f;
	const bool bAccepted = RequestSkillPayload(TEXT("skill:") + Spell);
	UE_LOG(LogFableForge, Display, TEXT("GESTURE_QA element=%s spell=%s held=%d accepted=%d"), *ActiveElement.ToString(), *Spell, bElementHeld, bAccepted);
}

void AFableForgePlayerController::HandleTimePressed()
{
	if (ChestWidget != nullptr && ChestWidget->IsChestOpen()) { ResetGameplayInputForChest(); return; }
	if (IsJournalOpen())
	{
		if (!IsWheelAssignmentOpen() && !IsControllerUiInputHandledByFocusedWidget()) CharacterMenuWidget->CycleCategoryTab(-1);
		return;
	}
	if (IsJournalOpen() || IsWheelAssignmentOpen()) return;
	if (bTargetingSkill || bQuickWheelHeld) return;
	if (bTimeButtonDown) return;
	bTimeButtonDown = true;
	bCosmicInputCancelled = false;
	bCosmicSelectionActivated = false;
	bTimeStopped = false;
	OpenCosmicWheel();
}

void AFableForgePlayerController::HandleTimeReleased()
{
	if (ChestWidget != nullptr && ChestWidget->IsChestOpen()) { ResetGameplayInputForChest(); return; }
	if (!bTimeButtonDown) return;
	bTimeButtonDown = false;
	if (bCosmicInputCancelled)
	{
		bCosmicInputCancelled = false;
		return;
	}
	if (IsJournalOpen() || IsWheelAssignmentOpen()) return;
	// Releasing L1 ends temporary wheel slow time unless a target is pending.
	CloseCosmicWheel(!bCosmicSelectionActivated);
	if (!bTargetingSkill)
	{
		bTimeStopped = false;
	}
}

void AFableForgePlayerController::ToggleSlowTime()
{
	if (bTargetingSkill && PendingSkillId == TEXT("time_step"))
	{
		CancelTargetedSkill();
		return;
	}
	if (IsJournalOpen() || IsWheelAssignmentOpen() || bTargetingSkill
		|| !GetWorld() || GetWorld()->IsPaused()
		|| (PartyHudWidget && PartyHudWidget->IsModalOpen())
		|| (ChestWidget && ChestWidget->IsChestOpen())
		|| (MainMenuWidget && MainMenuWidget->IsInViewport())
		|| bQuickWheelHeld || bCosmicWheelOpen) return;
	UFableSaveSubsystem* Save = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	const FString Equipped = Save ? Save->GetActiveCosmicSkillId() : TEXT("slow_time");
	if (Equipped != TEXT("slow_time"))
	{
		const bool bAccepted = RequestSkillPayload(TEXT("skill:") + Equipped);
		UE_LOG(LogFableForge, Display, TEXT("COSMIC_L3 skill=%s accepted=%d"), *Equipped, bAccepted);
		return;
	}
	bTimeHeld = !bTimeHeld && CosmicEnergy > KINDA_SMALL_NUMBER;
	ApplyCosmicTimeState();
	UE_LOG(LogFableForge, Display, TEXT("COSMIC_L3 slow=%d"), bTimeHeld);
}

void AFableForgePlayerController::ApplyCosmicTimeState()
{
	if (GetWorld()) GetWorld()->GetWorldSettings()->SetTimeDilation(IsSlowTimeActive() ? SlowTimeDilation : 1.f);
	if (TimeWheelWidget) TimeWheelWidget->SetTimeState(IsSlowTimeActive(), bTimeStopped);
}

void AFableForgePlayerController::SetWheelSlowTime(bool bEnabled)
{
	bWheelSlowTime = bEnabled && CosmicEnergy > KINDA_SMALL_NUMBER;
	ApplyCosmicTimeState();
}

void AFableForgePlayerController::HandleQuickWheelPressed()
{
	if (ChestWidget != nullptr && ChestWidget->IsChestOpen()) { ResetGameplayInputForChest(); return; }
	if (bTargetingSkill) return;
	if (bCosmicWheelOpen) return;
	if (IsJournalOpen())
	{
		if (!IsWheelAssignmentOpen() && !IsControllerUiInputHandledByFocusedWidget()) CharacterMenuWidget->CycleCategoryTab(1);
		return;
	}
	if (IsJournalOpen() || IsWheelAssignmentOpen()) return;
	bQuickWheelHeld = true;
	if (TimeWheelWidget != nullptr)
	{
		RefreshQuickWheelPagesFromSave();
		TimeWheelWidget->SetCosmicWheel(false);
		TimeWheelWidget->Open(QuickWheelPages);
		TimeWheelWidget->SetPage(QuickWheelPage);
		TimeWheelWidget->SetElement(ActiveElement);
		SetWheelInputCapture(true);
		SetWheelSlowTime(true);
	}
}

void AFableForgePlayerController::HandleLeftTriggerPressed()
{
	if (ChestWidget != nullptr && ChestWidget->IsChestOpen()) { ResetGameplayInputForChest(); return; }
	if (bCosmicWheelOpen) return;
	if (IsWheelAssignmentOpen()) return;
	if (IsJournalOpen())
	{
		if (!bLeftTriggerLatched)
		{
			bLeftTriggerLatched = true;
			CharacterMenuWidget->CycleMainTab(-1);
		}
		return;
	}
	HandleQuickWheelPrevious();
}

void AFableForgePlayerController::HandleLeftTriggerReleased()
{
	if (ChestWidget != nullptr && ChestWidget->IsChestOpen()) { ResetGameplayInputForChest(); return; }
	if (IsJournalOpen() || IsWheelAssignmentOpen())
	{
		bLeftTriggerLatched = false;
		return;
	}
	HandleLeftTrigger(0.0f);
}

void AFableForgePlayerController::HandleQuickWheelReleased()
{
	if (ChestWidget != nullptr && ChestWidget->IsChestOpen()) { ResetGameplayInputForChest(); return; }
	if (bTargetingSkill) return;
	if (bCosmicWheelOpen) return;
	if (IsJournalOpen() || IsWheelAssignmentOpen()) return;
	bQuickWheelHeld = false;
	if (!bCosmicWheelOpen && TimeWheelWidget != nullptr && TimeWheelWidget->IsOpen())
	{
		// Key releases run before PlayerTick; include the current frame's stick
		// sample so a fast select-and-release is not lost.
		TimeWheelWidget->SetSelectionFromStick(FVector2D(GetInputAnalogKeyState(EKeys::Gamepad_RightX), GetInputAnalogKeyState(EKeys::Gamepad_RightY)));
		const FString Payload = TimeWheelWidget->GetSelectedPayload();
		TimeWheelWidget->Close();
		SetWheelInputCapture(false);
		// Close the picker before casting: a slow-time cast may replace it with
		// targeting, which must not then be closed by wheel-release cleanup.
		const bool bAccepted = !Payload.IsEmpty() && RequestSkillPayload(Payload);
		UE_LOG(LogFableForge, Display, TEXT("WHEEL_RELEASE payload=%s accepted=%d"), *Payload, bAccepted);
	}
	if (!bTargetingSkill) SetWheelSlowTime(false);
}

void AFableForgePlayerController::HandleQuickWheelNext()
{
	if (ChestWidget != nullptr && ChestWidget->IsChestOpen()) { ResetGameplayInputForChest(); return; }
	if (IsJournalOpen() || IsWheelAssignmentOpen() || TimeWheelWidget == nullptr || !TimeWheelWidget->IsOpen()) return;
	if (bCosmicWheelOpen)
	{
		if (CosmicWheelPages.Num() == 0) return;
		CosmicWheelPage = (CosmicWheelPage + 1) % CosmicWheelPages.Num();
		TimeWheelWidget->SetPage(CosmicWheelPage);
		return;
	}
	if (QuickWheelPages.Num() == 0) return;
	QuickWheelPage = (QuickWheelPage + 1) % QuickWheelPages.Num();
	TimeWheelWidget->SetPage(QuickWheelPage);
}
void AFableForgePlayerController::HandleQuickWheelPrevious()
{
	if (ChestWidget != nullptr && ChestWidget->IsChestOpen()) { ResetGameplayInputForChest(); return; }
	if (IsJournalOpen() || IsWheelAssignmentOpen() || TimeWheelWidget == nullptr || !TimeWheelWidget->IsOpen()) return;
	if (bCosmicWheelOpen)
	{
		if (CosmicWheelPages.Num() == 0) return;
		CosmicWheelPage = (CosmicWheelPage - 1 + CosmicWheelPages.Num()) % CosmicWheelPages.Num();
		TimeWheelWidget->SetPage(CosmicWheelPage);
		return;
	}
	if (QuickWheelPages.Num() == 0) return;
	QuickWheelPage = (QuickWheelPage - 1 + QuickWheelPages.Num()) % QuickWheelPages.Num();
	TimeWheelWidget->SetPage(QuickWheelPage);
}
void AFableForgePlayerController::HandleRightTriggerPressed()
{
	if (ChestWidget != nullptr && ChestWidget->IsChestOpen()) { ResetGameplayInputForChest(); return; }
	if (bTargetingSkill) return;
	if (bCosmicWheelOpen) return;
	if (IsWheelAssignmentOpen()) return;
	if (IsJournalOpen())
	{
		if (!bRightTriggerLatched)
		{
			bRightTriggerLatched = true;
			CharacterMenuWidget->CycleMainTab(1);
		}
		return;
	}
	if (!bCosmicWheelOpen && TimeWheelWidget != nullptr && TimeWheelWidget->IsOpen())
	{
		HandleQuickWheelNext();
		return;
	}
	HandleRightTrigger(1.0f);
}
void AFableForgePlayerController::HandleRightTriggerReleased() { if (ChestWidget != nullptr && ChestWidget->IsChestOpen()) { ResetGameplayInputForChest(); return; } if (!IsJournalOpen() && !IsWheelAssignmentOpen()) HandleRightTrigger(0.0f); else bRightTriggerLatched = false; }
void AFableForgePlayerController::HandleRightStickX(float Value) { if (ChestWidget != nullptr && ChestWidget->IsChestOpen()) { ResetGameplayInputForChest(); return; } RightStickValue.X = Value; if (!IsJournalOpen() && !IsWheelAssignmentOpen()) RouteRightStickToWheel(RightStickValue); }
void AFableForgePlayerController::HandleRightStickY(float Value) { if (ChestWidget != nullptr && ChestWidget->IsChestOpen()) { ResetGameplayInputForChest(); return; } RightStickValue.Y = Value; if (!IsJournalOpen() && !IsWheelAssignmentOpen()) RouteRightStickToWheel(RightStickValue); }
void AFableForgePlayerController::HandleRightTrigger(float Value)
{
	if (ChestWidget != nullptr && ChestWidget->IsChestOpen()) { ResetGameplayInputForChest(); return; }
	if ((bCosmicWheelOpen || bQuickWheelHeld) && !bTargetingSkill)
	{
		if (Value > .85f) bRightTriggerLatched = true;
		else if (Value < .2f) bRightTriggerLatched = false;
		return;
	}
	if (IsWheelAssignmentOpen()) return;
	if (IsJournalOpen())
	{
		// Journal R2 is edge-driven by HandleRightTriggerPressed/Released. Do not
		// also consume the analog axis here: trigger hardware can emit a transient
		// low sample between its key edge and settled value, clearing the latch and
		// causing one physical press to advance two tabs.
		return;
	}
	if (Value > 0.85f && !bRightTriggerLatched)
	{
		bRightTriggerLatched = true;
		if (bTargetingSkill) return;
		else if (IsSlowTimeActive() && !bTimeStopped)
		{
			bPendingWeaponAttack = true;
			bPendingOffHand = false;
			bTargetRequiresGround = false;
			PendingSkillId.Reset();
			BeginPrecisionTarget(230.f, 35.f);
		}
		else if (!IsSlowTimeActive() && !bTimeButtonDown && !(TimeWheelWidget && TimeWheelWidget->IsOpen())) PerformWeaponAttack(false);
	}
	if (Value < 0.2f) bRightTriggerLatched = false;
}
void AFableForgePlayerController::HandleLeftTrigger(float Value)
{
	if (ChestWidget != nullptr && ChestWidget->IsChestOpen()) { ResetGameplayInputForChest(); return; }
	if (bCosmicWheelOpen || bQuickWheelHeld)
	{
		if (Value > .85f) bLeftTriggerLatched = true;
		else if (Value < .2f) bLeftTriggerLatched = false;
		return;
	}
	if (IsWheelAssignmentOpen()) return;
	if (IsJournalOpen())
	{
		// Journal L2 is edge-driven by HandleLeftTriggerPressed/Released; see the
		// R2 path above for why the analog axis is deliberately ignored here.
		return;
	}
	if (Value > 0.85f && !bLeftTriggerLatched)
	{
		bLeftTriggerLatched = true;
		if (bTargetingSkill) return;
		else if (IsSlowTimeActive() && !bTimeStopped)
		{
			bPendingWeaponAttack = true;
			bPendingOffHand = true;
			bTargetRequiresGround = false;
			PendingSkillId.Reset();
			BeginPrecisionTarget(230.f, 35.f);
		}
		else if (!IsSlowTimeActive() && !bTimeButtonDown && !(TimeWheelWidget && TimeWheelWidget->IsOpen())) PerformWeaponAttack(true);
	}
	if (Value < 0.2f) bLeftTriggerLatched = false;
}

FVector AFableForgePlayerController::ResolveAimPoint(FHitResult* OutHit) const
{
	FVector WorldOrigin, WorldDirection;
	int32 SizeX = 0, SizeY = 0;
	GetViewportSize(SizeX, SizeY);
	if (SizeX > 0 && SizeY > 0 && DeprojectScreenPositionToWorld(SizeX * 0.5f, SizeY * 0.5f, WorldOrigin, WorldDirection))
	{
		const FVector End = WorldOrigin + WorldDirection * 2000.0f;
		FCollisionQueryParams Params(SCENE_QUERY_STAT(FableAim), true, GetPawn());
		FHitResult Hit;
		if (GetWorld() && GetWorld()->LineTraceSingleByChannel(Hit, WorldOrigin, End, ECC_Visibility, Params))
		{
			// Visibility can hit the floor behind a character when a mesh or
			// imported collision profile is incomplete. Prefer a damageable pawn
			// intersecting the same crosshair ray before accepting that surface.
			if (Hit.GetActor() == nullptr || Cast<ICombatDamageable>(Hit.GetActor()) == nullptr)
			{
				TArray<FHitResult> PawnHits;
				const FCollisionShape AimShape = FCollisionShape::MakeSphere(28.0f);
				if (GetWorld()->SweepMultiByChannel(PawnHits, WorldOrigin, Hit.ImpactPoint, FQuat::Identity, ECC_Pawn, AimShape, Params))
				{
					for (const FHitResult& PawnHit : PawnHits)
						if (PawnHit.GetActor() != nullptr && Cast<ICombatDamageable>(PawnHit.GetActor()) != nullptr)
						{
							if (OutHit) *OutHit = PawnHit;
							return PawnHit.ImpactPoint;
						}
				}
			}
			if (OutHit) *OutHit = Hit;
			return Hit.ImpactPoint;
		}
		if (OutHit) OutHit->Reset();
		return End;
	}
	return GetPawn() ? GetPawn()->GetActorLocation() + GetPawn()->GetActorForwardVector() * 500.0f : FVector::ZeroVector;
}

void AFableForgePlayerController::PerformWeaponAttack(bool bOffHand)
{
	if (ChestWidget != nullptr && ChestWidget->IsChestOpen()) return;
	APawn* Pawn = GetPawn();
	if (Pawn == nullptr || GetWorld() == nullptr || bWeaponAttackActive) return;
	bWeaponAttackActive = true;
	GetWorld()->GetTimerManager().ClearTimer(WeaponAttackHitTimerHandle);
	GetWorld()->GetTimerManager().ClearTimer(WeaponAttackRestoreTimerHandle);
	UE_LOG(LogFableForge, Display, TEXT("INPUT_QA weapon_attack hand=%s"), bOffHand ? TEXT("off") : TEXT("main"));
	FHitResult AimHit;
	const FVector AimPoint = bPendingWeaponAttack ? PendingTargetLocation : ResolveAimPoint(&AimHit);
	const FVector Start = Pawn->GetActorLocation() + FVector(0, 0, 70);
	const FVector Direction = (AimPoint - Start).GetSafeNormal();
	// Damage lands during the attack animation, not on trigger-down. This keeps
	// the hit and the visible swing in sync and prevents damage before contact.
	TWeakObjectPtr<AFableForgePlayerController> WeakController(this);
	TWeakObjectPtr<APawn> WeakPawn(Pawn);
	GetWorld()->GetTimerManager().SetTimer(WeaponAttackHitTimerHandle, FTimerDelegate::CreateLambda([WeakController, WeakPawn, bOffHand, Start, Direction]()
	{
		if (AFableForgePlayerController* Controller = WeakController.Get())
			if (APawn* AttackPawn = WeakPawn.Get())
				Controller->ExecuteWeaponAttackHit(bOffHand, AttackPawn, Start, Direction);
	}), 0.25f, false);
	if (ACharacter* Character = Cast<ACharacter>(Pawn))
	{
		if (USkeletalMeshComponent* Mesh = Character->GetMesh())
		{
			AFableForgeCharacter* FableCharacter = Cast<AFableForgeCharacter>(Character);
			const bool bFirstPerson = FableCharacter != nullptr && FableCharacter->IsFirstPersonViewActive();
			const bool bMoving = Pawn->GetVelocity().SizeSquared2D() > FMath::Square(10.0f);
			if (FableCharacter != nullptr) FableCharacter->SetFirstPersonAttackPresentation(bFirstPerson);
			if (UAnimationAsset* Attack = LoadObject<UAnimationAsset>(nullptr, TEXT("/Game/Characters/PlayableCharacter/Anims/Unarmed/Attack/MM_Attack_01.MM_Attack_01")))
			{
				const float RestoreDelay = FMath::Max(0.2f, Cast<UAnimSequenceBase>(Attack) ? Cast<UAnimSequenceBase>(Attack)->GetPlayLength() : 0.7f);
				if (bFirstPerson && FableCharacter != nullptr && FableCharacter->GetFirstPersonArmsMesh() != nullptr)
				{
					USkeletalMeshComponent* Arms = FableCharacter->GetFirstPersonArmsMesh();
					Arms->SetAnimationMode(EAnimationMode::AnimationSingleNode);
					Arms->PlayAnimation(Attack, false);
				}
				else if (bMoving)
				{
					if (FableCharacter != nullptr && FableCharacter->GetAttackOverlayMesh() != nullptr)
					{
						USkeletalMeshComponent* Overlay = FableCharacter->GetAttackOverlayMesh();
						if (Overlay->GetSkeletalMeshAsset() != Mesh->GetSkeletalMeshAsset())
						{
							Overlay->SetSkeletalMesh(Mesh->GetSkeletalMeshAsset());
							for (int32 MaterialIndex = 0; MaterialIndex < Mesh->GetNumMaterials(); ++MaterialIndex)
							{
								Overlay->SetMaterial(MaterialIndex, Mesh->GetMaterial(MaterialIndex));
							}
							for (const FName BoneName : { FName(TEXT("head")), FName(TEXT("neck_01")), FName(TEXT("thigh_l")), FName(TEXT("calf_l")), FName(TEXT("foot_l")), FName(TEXT("ball_l")), FName(TEXT("thigh_r")), FName(TEXT("calf_r")), FName(TEXT("foot_r")), FName(TEXT("ball_r")) })
							{
								Overlay->HideBoneByName(BoneName, PBO_None);
							}
						}
						Overlay->SetAnimationMode(EAnimationMode::AnimationSingleNode);
						Overlay->SetVisibility(true, true);
						Overlay->PlayAnimation(Attack, false);
					}
					else if (UAnimSequence* Sequence = Cast<UAnimSequence>(Attack))
					{
						if (UAnimInstance* AnimInstance = Mesh->GetAnimInstance())
						{
							UAnimMontage* Montage = NewObject<UAnimMontage>(Mesh, NAME_None, RF_Transient);
							FAnimSegment Segment;
							Segment.SetAnimReference(Sequence, true);
							Segment.AnimEndTime = Sequence->GetPlayLength();
							Segment.LoopingCount = 1;
							FSlotAnimationTrack SlotTrack;
							SlotTrack.SlotName = TEXT("DefaultSlot");
							SlotTrack.AnimTrack.AnimSegments.Add(Segment);
							Montage->SlotAnimTracks.Add(SlotTrack);
							Montage->CalculateSequenceLength();
							AnimInstance->Montage_Play(Montage, 1.0f);
						}
					}
				}
				else
				{
					Mesh->SetAnimationMode(EAnimationMode::AnimationSingleNode);
					Mesh->PlayAnimation(Attack, false);
				}
				GetWorld()->GetTimerManager().SetTimer(WeaponAttackRestoreTimerHandle, this, &AFableForgePlayerController::RestoreWeaponAttackAnimation, RestoreDelay, false);
			}
			else
			{
				bWeaponAttackActive = false;
			}
		}
		else
		{
			bWeaponAttackActive = false;
		}
	}
	else
	{
		bWeaponAttackActive = false;
	}
}

void AFableForgePlayerController::RestoreWeaponAttackAnimation()
{
	bWeaponAttackActive = false;
	if (AFableForgeCharacter* Character = Cast<AFableForgeCharacter>(GetPawn()))
	{
		Character->SetFirstPersonAttackPresentation(false);
		if (Character->GetAttackOverlayMesh() != nullptr)
		{
			Character->GetAttackOverlayMesh()->SetVisibility(false, true);
		}
		if (Character->IsFirstPersonViewActive())
		{
			return;
		}
		if (USkeletalMeshComponent* Mesh = Character->GetMesh())
		{
			Mesh->SetAnimationMode(EAnimationMode::AnimationBlueprint);
			Mesh->InitAnim(true);
		}
	}
}

void AFableForgePlayerController::ExecuteWeaponAttackHit(bool bOffHand, APawn* Pawn, const FVector& Start, const FVector& Direction)
{
	if (!Pawn || !GetWorld()) return;
	const FVector End = Start + Direction * 180.0f;
	const FCollisionShape Shape = FCollisionShape::MakeSphere(65.0f);
	FCollisionQueryParams Params(SCENE_QUERY_STAT(FableWeaponAttack), false, Pawn);
	TArray<FHitResult> Hits;
	if (!GetWorld()->SweepMultiByChannel(Hits, Start, End, FQuat::Identity, ECC_Pawn, Shape, Params)) return;
	TSet<AActor*> DamagedActors;
	for (const FHitResult& Hit : Hits)
	{
		AActor* HitActor = Hit.GetActor();
		if (HitActor && DamagedActors.Contains(HitActor)) continue;
		if (ICombatDamageable* Damageable = Cast<ICombatDamageable>(HitActor))
		{
			DamagedActors.Add(HitActor);
			Damageable->ApplyDamage(bOffHand ? 16.0f : 22.0f, Pawn, Hit.ImpactPoint, Direction * (bOffHand ? 120.0f : 180.0f) + FVector(0, 0, 80));
		}
	}
}

bool AFableForgePlayerController::RequestSkillPayload(const FString& PayloadId)
{
	if (PayloadId.StartsWith(TEXT("item:")))
	{
		const FString ItemId = PayloadId.RightChop(5);
		FFableCharacterProfile Profile;
		UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
		if (SaveSubsystem == nullptr || !SaveSubsystem->TryGetActiveCharacterProfile(Profile)) return false;
		for (int32 InventorySlot = 0; InventorySlot < Profile.InventorySlots.Num(); ++InventorySlot)
		{
			if (Profile.InventorySlots[InventorySlot].Equals(ItemId, ESearchCase::IgnoreCase))
			{
				return ConsumeInventoryItem(InventorySlot);
			}
		}
		UE_LOG(LogFableForge, Display, TEXT("Quick wheel consumable rejected: item '%s' not found"), *ItemId);
		return false;
	}
	if (!PayloadId.StartsWith(TEXT("skill:"))) return false;
	if (bTargetingSkill) return false;
	if (PayloadId == TEXT("skill:slow_time"))
	{
		bTimeHeld = !bTimeHeld && CosmicEnergy > KINDA_SMALL_NUMBER;
		ApplyCosmicTimeState();
		return true;
	}
	PendingSkillId = PayloadId;
	PendingSkillId.RemoveFromStart(TEXT("skill:"));
	FString SkillPath = TEXT("/Game/Data/DT_Skills.DT_Skills");
	UDataTable* Table = LoadObject<UDataTable>(nullptr, *SkillPath);
	FFableSkillDefinitionTableRow FallbackSkill;
	const FFableSkillDefinitionTableRow* Skill = nullptr;
	if (FableSkillCatalog::TryGetStarterSkillDefinition(PendingSkillId, FallbackSkill)) Skill = &FallbackSkill;
	if (!Skill && Table)
	{
		TArray<FFableSkillDefinitionTableRow*> Rows;
		Table->GetAllRows(TEXT("FableForgePlayerController::RequestSkillPayload"), Rows);
		for (const FFableSkillDefinitionTableRow* Row : Rows) if (Row && Row->SkillId == PendingSkillId) { Skill = Row; break; }
	}
	if (!Skill)
	{
		UE_LOG(LogFableForge, Warning, TEXT("Quick wheel skill rejected: no definition for %s"), *PendingSkillId);
		return false;
	}
	if (Skill->ResourceType == EFableSkillResourceType::Mana && Mana + KINDA_SMALL_NUMBER < Skill->ResourceCost)
	{
		UE_LOG(LogFableForge, Display, TEXT("SPELL_REJECTED skill=%s reason=not_enough_mana mana=%.1f cost=%.1f"), *PendingSkillId, Mana, Skill->ResourceCost);
		return false;
	}
	PendingSkillManaCost = Skill->ResourceType == EFableSkillResourceType::Mana ? Skill->ResourceCost : 0.0f;
	FHitResult Hit;
	PendingTargetLocation = ResolveAimPoint(&Hit);
	PendingTargetActor = Hit.GetActor();
	const bool bAimedAtDamageable = Hit.GetActor() != nullptr && Cast<ICombatDamageable>(Hit.GetActor()) != nullptr;
	if (PendingSkillId == TEXT("time_step") || (IsSlowTimeActive() && Skill->TargetingMode != EFableSkillTargetingMode::Self && Skill->TargetingMode != EFableSkillTargetingMode::Weapon && Skill->TargetingMode != EFableSkillTargetingMode::Equipment))
	{
		bPendingWeaponAttack = false;
		bTargetRequiresGround = Skill->TargetingMode == EFableSkillTargetingMode::Ground;
		BeginPrecisionTarget(Skill->RangeUnits, Skill->RadiusUnits);
		return bTargetingSkill;
	}
	// Keep normal-time casts in range, with ground spells actually on the ground
	// even when the camera center looks at the horizon instead of a surface.
	if (APawn* Caster = GetPawn())
	{
		const FVector Origin = Caster->GetActorLocation();
		const float CastRange = FMath::Max(100.f, Skill->RangeUnits);
		if (!Hit.bBlockingHit || FVector::Dist(Origin, PendingTargetLocation) > CastRange)
		{
			PendingTargetLocation = Origin + (PendingTargetLocation - Origin).GetSafeNormal() * FMath::Min(CastRange, 850.f);
			PendingTargetActor.Reset();
		}
		if (Skill->TargetingMode == EFableSkillTargetingMode::Ground
			|| (Skill->TargetingMode == EFableSkillTargetingMode::Area && !bAimedAtDamageable))
		{
			AActor* AimedTarget = bAimedAtDamageable ? PendingTargetActor.Get() : nullptr;
			FHitResult GroundHit;
			FCollisionQueryParams Params(SCENE_QUERY_STAT(FableSpellGround), false, Caster);
			if (AimedTarget != nullptr) Params.AddIgnoredActor(AimedTarget);
			if (GetWorld()->LineTraceSingleByChannel(GroundHit, PendingTargetLocation + FVector(0, 0, 400), PendingTargetLocation - FVector(0, 0, 2000), ECC_Visibility, Params))
			{
				PendingTargetLocation = GroundHit.ImpactPoint;
				PendingTargetActor = AimedTarget != nullptr ? AimedTarget : GroundHit.GetActor();
			}
		}
	}
	if (ACharacter* Character = Cast<ACharacter>(GetPawn()))
		if (USkeletalMeshComponent* Mesh = Character->GetMesh())
			if (UAnimationAsset* Animation = Skill->CharacterAnimationAsset.LoadSynchronous()) Mesh->PlayAnimation(Animation, false);
	const bool bCast = FFableSpellRuntime::ExecuteSkill(GetWorld(), GetPawn(), PendingSkillId, Skill->TargetingMode == EFableSkillTargetingMode::Self ? GetPawn()->GetActorLocation() : PendingTargetLocation, PendingTargetActor.Get());
	if (bCast && PendingSkillId == TEXT("heal_wave") && PartyHudWidget) PartyHudWidget->RefreshFromSaveData();
	if (bCast && PendingSkillManaCost > 0.0f) { SpendMana(PendingSkillManaCost); PendingSkillManaCost = 0.0f; }
	return bCast;
}

bool AFableForgePlayerController::SpendMana(float Amount)
{
	if (Amount <= 0.0f) return true;
	if (Mana + KINDA_SMALL_NUMBER < Amount) return false;
	Mana = FMath::Clamp(Mana - Amount, 0.0f, MaxMana);
	UE_LOG(LogFableForge, Display, TEXT("MANA_SPENT amount=%.1f remaining=%.1f/%.1f"), Amount, Mana, MaxMana);
	return true;
}

bool AFableForgePlayerController::ConsumeInventoryItem(int32 InventorySlot)
{
	UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	if (SaveSubsystem == nullptr || !SaveSubsystem->ConsumeActiveInventoryItem(InventorySlot)) return false;

	if (PartyHudWidget != nullptr) PartyHudWidget->RefreshFromSaveData();
	return true;
}

void AFableForgePlayerController::BeginPrecisionTarget(float Range, float Radius)
{
	if (!GetWorld() || !GetPawn()) return;
	EnsureUiWidgets();
	ClearHoveredInteractable();
	ClearPendingInteraction();
	TargetRange = FMath::Max(50.f, Range);
	TargetRadius = FMath::Max(12.f, Radius);
	int32 Width, Height; GetViewportSize(Width, Height);
	TargetCursorPixels = FVector2D(Width * .5f, Height * .5f);
	bTargetOwnsPause = !GetWorld()->IsPaused() && SetPause(true);
	if (!bTargetOwnsPause) { UE_LOG(LogFableForge, Warning, TEXT("TARGET_QA pause rejected")); return; }
	bTargetPreviousCameraMoveable = GetWorld()->bIsCameraMoveableWhenPaused;
	GetWorld()->bIsCameraMoveableWhenPaused = true;
	bTargetingSkill = true;
	bTimeStopped = true;
	SetWheelInputCapture(true);
	if (TimeWheelWidget) TimeWheelWidget->BeginTargeting(PendingSkillId, PendingTargetLocation);
	UpdatePrecisionTarget(0.f);
	UE_LOG(LogFableForge, Display, TEXT("TARGET_QA entered paused=%d energy=%.2f"), GetWorld()->IsPaused(), CosmicEnergy);
}

void AFableForgePlayerController::UpdatePrecisionTarget(float RealDeltaSeconds)
{
	int32 Width, Height; GetViewportSize(Width, Height);
	if (Width <= 0 || Height <= 0) return;
	const FVector2D Input = RightStickValue.SizeSquared() > .06f ? RightStickValue : FVector2D::ZeroVector;
	TargetCursorPixels += Input * RealDeltaSeconds * FMath::Min(Width, Height) * .8f;
	TargetCursorPixels.X = FMath::Clamp(TargetCursorPixels.X, 12.f, Width - 12.f);
	TargetCursorPixels.Y = FMath::Clamp(TargetCursorPixels.Y, 12.f, Height - 12.f);
	FVector Origin, Direction;
	FHitResult Hit;
	FCollisionQueryParams Params(SCENE_QUERY_STAT(FablePrecisionTarget), true, GetPawn());
	const bool bHit = DeprojectScreenPositionToWorld(TargetCursorPixels.X, TargetCursorPixels.Y, Origin, Direction)
		&& GetWorld()->LineTraceSingleByChannel(Hit, Origin, Origin + Direction * 20000.f, ECC_Visibility, Params);
	PendingTargetActor = bHit ? Hit.GetActor() : nullptr;
	if (bHit) PendingTargetLocation = Hit.ImpactPoint;
	bTargetValid = bHit && GetPawn() && FVector::Dist(GetPawn()->GetActorLocation(), PendingTargetLocation) <= TargetRange;
	if (bTargetRequiresGround && bHit && Hit.ImpactNormal.Z < .5f) bTargetValid = false;
	if (bTargetValid && PendingSkillId == TEXT("time_step"))
	{
		FVector Destination;
		bTargetValid = FFableSpellRuntime::ResolveSafeTimeStepDestination(GetWorld(), GetPawn(), PendingTargetLocation, Destination);
	}
	UPrimitiveComponent* NewHighlight = bTargetValid ? Hit.GetComponent() : nullptr;
	if (NewHighlight && NewHighlight->Bounds.BoxExtent.GetMax() > 300.f) NewHighlight = nullptr;
	if (NewHighlight != TargetHighlightComponent.Get())
	{
		if (TargetHighlightComponent.IsValid()) TargetHighlightComponent->SetRenderCustomDepth(bTargetPreviousCustomDepth);
		TargetHighlightComponent = NewHighlight;
		if (NewHighlight) { bTargetPreviousCustomDepth = NewHighlight->bRenderCustomDepth; NewHighlight->SetRenderCustomDepth(true); }
	}
	if (TimeWheelWidget) TimeWheelWidget->SetTargetPreview(TargetCursorPixels, PendingTargetLocation, bHit ? Hit.ImpactNormal : FVector::UpVector, TargetRadius, bTargetValid, bHit);
}

void AFableForgePlayerController::EndPrecisionTarget()
{
	if (TargetHighlightComponent.IsValid()) TargetHighlightComponent->SetRenderCustomDepth(bTargetPreviousCustomDepth);
	TargetHighlightComponent.Reset();
	if (bTargetOwnsPause)
	{
		GetWorld()->bIsCameraMoveableWhenPaused = bTargetPreviousCameraMoveable;
		SetPause(false);
	}
	bTargetOwnsPause = false;
	bTargetingSkill = false;
	bTimeStopped = false;
	if (TimeWheelWidget) TimeWheelWidget->EndTargeting();
	LastCosmicWallTimeSeconds = FPlatformTime::Seconds();
}

void AFableForgePlayerController::ConfirmTargetedSkill()
{
	if (!bTargetingSkill) return;
	ConsumeJumpPress();
	UpdatePrecisionTarget(0.f);
	if (!bTargetValid) { UE_LOG(LogFableForge, Display, TEXT("TARGET_QA rejected no reachable surface")); return; }
	EndPrecisionTarget();
	bool bCast = true;
	if (bPendingWeaponAttack) PerformWeaponAttack(bPendingOffHand);
	else bCast = FFableSpellRuntime::ExecuteSkill(GetWorld(), GetPawn(), PendingSkillId, PendingTargetLocation, PendingTargetActor.Get());
	if (bCast && PendingSkillManaCost > 0.0f) { SpendMana(PendingSkillManaCost); PendingSkillManaCost = 0.0f; }
	if (PendingSkillId == TEXT("heal_wave") && PartyHudWidget) PartyHudWidget->RefreshFromSaveData();
	bPendingWeaponAttack = false;
	UE_LOG(LogFableForge, Display, TEXT("TARGET_QA confirmed location=%s"), *PendingTargetLocation.ToString());
	PendingSkillId.Reset();
	bTimeStopped = false;
	if (bCosmicWheelOpen)
	{
		bCosmicInputCancelled = bTimeButtonDown;
		CloseCosmicWheel(false);
	}
	else
	{
		if (TimeWheelWidget) TimeWheelWidget->Close();
		SetWheelInputCapture(false);
	}
	SetWheelSlowTime(false);
}

void AFableForgePlayerController::CancelTargetedSkill()
{
	if (MainMenuWidget && MainMenuWidget->IsControllerMenuActive()) { MainMenuWidget->HandleControllerCancel(); return; }
	if (ChestWidget && ChestWidget->IsChestOpen()) { CloseChest(); return; }
	if (bCosmicWheelOpen)
	{
		bCosmicInputCancelled = true;
		EndPrecisionTarget();
		bPendingWeaponAttack = false;
		PendingSkillId.Reset();
		if (TimeWheelWidget) TimeWheelWidget->EndTargeting();
		CloseCosmicWheel(false);
		return;
	}
	if (WheelAssignmentWidget != nullptr && WheelAssignmentWidget->IsOpen())
	{
		WheelAssignmentWidget->Cancel();
		SetInputMode(FInputModeGameAndUI());
		bShowMouseCursor = true;
		return;
	}
	if (IsJournalOpen() && !IsControllerUiInputHandledByFocusedWidget())
	{
		CharacterMenuWidget->HandleControllerCancel();
		return;
	}
	EndPrecisionTarget();
	bPendingWeaponAttack = false;
	PendingSkillId.Reset();
	if (TimeWheelWidget) { TimeWheelWidget->EndTargeting(); TimeWheelWidget->Close(); }
	SetWheelInputCapture(false);
	SetWheelSlowTime(false);
}

void AFableForgePlayerController::HandleControllerActivate()
{
	if (MainMenuWidget && MainMenuWidget->IsControllerMenuActive()) { MainMenuWidget->ActivateControllerSelection(); return; }
	if (IsGameInteractionBlocked()) ConsumeJumpPress();
	if (bTargetingSkill) { ConfirmTargetedSkill(); return; }
	if (ChestWidget && ChestWidget->IsChestOpen()) { if (!ChestWidget->HasAnyUserFocus()) ChestWidget->ActivateControllerSelection(); return; }
	if (bCosmicWheelOpen && bTimeButtonDown) { ActivateCosmicWheelSelection(); return; }
	if (IsWheelAssignmentOpen() || !IsJournalOpen() || IsControllerUiInputHandledByFocusedWidget()) return;
	CharacterMenuWidget->ActivateControllerSelection();
}

void AFableForgePlayerController::ConsumeJumpPress()
{
	bJumpPressConsumed = true;
	JumpConsumedFrame = GFrameCounter;
	if (ACharacter* Character = Cast<ACharacter>(GetPawn())) Character->StopJumping();
}

void AFableForgePlayerController::HandleControllerActivateReleased()
{
	bJumpPressConsumed = false;
	// JumpConsumedFrame deliberately survives release: a very short tap may
	// deliver press, release and Enhanced Started within the same engine frame.
}

bool AFableForgePlayerController::TryStartGameplayJump()
{
	if (IsGameInteractionBlocked())
	{
		ConsumeJumpPress();
		return false;
	}
	return !bJumpPressConsumed && JumpConsumedFrame != GFrameCounter;
}

void AFableForgePlayerController::ToggleFirstPersonView()
{
	if ((ChestWidget != nullptr && ChestWidget->IsChestOpen()) || IsJournalOpen() || IsWheelAssignmentOpen()) return;
	if (AFableForgeCharacter* Character = Cast<AFableForgeCharacter>(GetPawn())) Character->ToggleFirstPersonView();
}

void AFableForgePlayerController::OpenWheelAssignment()

{
	OpenWheelAssignmentForPayload(FString());
}

void AFableForgePlayerController::OpenSkillsForQa()
{
	EnsureUiWidgets();
	if (CharacterMenuWidget != nullptr)
	{
		CharacterMenuWidget->OpenSkillsForQa();
	}
}

void AFableForgePlayerController::OpenWheelAssignmentForPayload(const FString& PreferredPayload)
{
	if (bTargetingSkill || (TimeWheelWidget && TimeWheelWidget->IsOpen())) return;
	EnsureUiWidgets();
	if (WheelAssignmentWidget == nullptr) return;
	FFableCharacterProfile Profile;
	UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	if (SaveSubsystem == nullptr || !SaveSubsystem->TryGetActiveCharacterProfile(Profile)) return;
	TArray<FString> Payloads;
	TArray<FString> Labels;
	UDataTable* SkillTable = LoadObject<UDataTable>(nullptr, TEXT("/Game/Data/DT_Skills.DT_Skills"));
	TArray<FFableSkillDefinitionTableRow*> SkillRows;
	if (SkillTable) SkillTable->GetAllRows(TEXT("Wheel assignment"), SkillRows);
	for (const FString& SkillId : Profile.LearnedSkills)
	{
		// Basic Attack is the weapon attack baseline, not an assignable wheel skill.
		// Keep the gameplay gesture and trigger-owned weapon attack paths unchanged.
		if (!FableSkillCatalog::IsAssignableSkillId(SkillId)) continue;
		Payloads.Add(TEXT("skill:") + SkillId);
		const FFableSkillDefinitionTableRow* Skill = nullptr;
		for (const auto* Row : SkillRows) if (Row && Row->SkillId == SkillId) { Skill = Row; break; }
		FFableSkillDefinitionTableRow FallbackSkill;
		if (Skill == nullptr && FableSkillCatalog::TryGetStarterSkillDefinition(SkillId, FallbackSkill)) Skill = &FallbackSkill;
		Labels.Add(Skill && !Skill->DisplayName.IsEmpty() ? Skill->DisplayName : SkillId);
	}
	UDataTable* ItemTable = LoadObject<UDataTable>(nullptr, TEXT("/Game/Data/DT_Items.DT_Items"));
	TArray<FFableItemDefinitionTableRow*> ItemRows;
	if (ItemTable) ItemTable->GetAllRows(TEXT("WheelConsumables"), ItemRows);
	for (const FString& ItemId : Profile.InventorySlots)
	{
		const FString Payload = TEXT("item:") + ItemId;
		if (ItemId.IsEmpty() || Payloads.Contains(Payload)) continue;
		FString Label = ItemId.Replace(TEXT("_"), TEXT(" "));
		bool bWordStart = true;
		for (TCHAR& Ch : Label) { if (bWordStart) Ch = FChar::ToUpper(Ch); bWordStart = FChar::IsWhitespace(Ch); }
		for (const auto* Row : ItemRows) if (Row && Row->ItemId == ItemId && !Row->DisplayName.IsEmpty()) { Label = Row->DisplayName; break; }
		Payloads.Add(Payload); Labels.Add(Label);
	}
	// Use the gameplay wheel at its normal viewport size, above the journal.
	// Do not replace the book pages with a separate list editor.
	WheelAssignmentWidget->SetEmbedded(false);
	if (!WheelAssignmentWidget->IsInViewport()) WheelAssignmentWidget->AddToViewport(70);
	WheelAssignmentWidget->Open(QuickWheelPages, Payloads, Labels);
	bWheelAssignmentEmbedded = false;
	if (!PreferredPayload.IsEmpty())
	{
		WheelAssignmentWidget->SetSelectedAvailablePayload(PreferredPayload);
	}
	FInputModeUIOnly InputMode;
	InputMode.SetWidgetToFocus(WheelAssignmentWidget->TakeWidget());
	SetInputMode(InputMode);
	bShowMouseCursor = true;
	SetWheelInputCapture(true);
}

void AFableForgePlayerController::OpenQuickWheelForQa()
{
	HandleQuickWheelPressed();
}

void AFableForgePlayerController::HandleWheelAssignmentChanged(const TArray<FFableQuickWheelPageData>& Pages)
{
	QuickWheelPages = Pages;
	QuickWheelPage = QuickWheelPages.Num() > 0 ? FMath::Clamp(QuickWheelPage, 0, QuickWheelPages.Num() - 1) : 0;
	if (UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr)
		SaveSubsystem->SetActiveQuickWheelPages(QuickWheelPages);
	if (!bCosmicWheelOpen && TimeWheelWidget != nullptr && TimeWheelWidget->IsOpen())
	{
		TimeWheelWidget->Open(QuickWheelPages);
		if (QuickWheelPages.Num() > 0) TimeWheelWidget->SetPage(QuickWheelPage);
	}
}

bool AFableForgePlayerController::RefreshQuickWheelPagesFromSave()
{
	UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	if (SaveSubsystem == nullptr) return false;

	TArray<FFableQuickWheelPageData> SavedPages;
	if (!SaveSubsystem->TryGetActiveQuickWheelPages(SavedPages)) return false;
	QuickWheelPages = MoveTemp(SavedPages);
	QuickWheelPage = QuickWheelPages.Num() > 0
		? ((QuickWheelPage % QuickWheelPages.Num()) + QuickWheelPages.Num()) % QuickWheelPages.Num()
		: 0;
	UE_LOG(LogFableForge, Verbose, TEXT("Quick wheel pages refreshed from save: pages=%d page=%d"), QuickWheelPages.Num(), QuickWheelPage);
	return true;
}

void AFableForgePlayerController::HandleWheelAssignmentClosed()
{
	if (bWheelAssignmentEmbedded)
	{
		if (CharacterMenuWidget != nullptr)
		{
			CharacterMenuWidget->HideEmbeddedQuickWheel();
		}
		WheelAssignmentWidget->SetEmbedded(false);
		WheelAssignmentWidget->AddToViewport(70);
		WheelAssignmentWidget->SetVisibility(ESlateVisibility::Collapsed);
		bWheelAssignmentEmbedded = false;
	}
	SetWheelInputCapture(false);
	FInputModeGameAndUI InputMode;
	ResetIgnoreMoveInput();
	ResetIgnoreLookInput();
	if (IsJournalOpen())
	{
		InputMode.SetWidgetToFocus(CharacterMenuWidget->TakeWidget());
		SetIgnoreMoveInput(true);
		SetIgnoreLookInput(true);
	}
	SetInputMode(InputMode);
	MainMenuWidget->FocusControllerSelection();
	bShowMouseCursor = true;
}

void AFableForgePlayerController::RunControllerInputSmokeTest()
{
	EnsureUiWidgets();
	if (UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr)
	{
		FFableCharacterProfile Profile;
		if (!SaveSubsystem->TryGetActiveCharacterProfile(Profile))
		{
			const FGuid QaCharacterId = SaveSubsystem->CreateCharacter(TEXT("Input QA"), TEXT("human"), EFableGender::Male);
			SaveSubsystem->SaveCharacterToSlot(QaCharacterId, 0, GetWorld() ? GetWorld()->GetMapName() : TEXT("QA"));
			SaveSubsystem->LoadCharacterFromSlot(QaCharacterId, 0);
		}
		SaveSubsystem->TryGetActiveQuickWheelPages(QuickWheelPages);
	}
	UE_LOG(LogFableForge, Display, TEXT("INPUT_QA begin pawn=%s pages=%d"), *GetNameSafe(GetPawn()), QuickWheelPages.Num());

	HandleQuickWheelPressed();
	UE_LOG(LogFableForge, Display, TEXT("INPUT_QA quick_wheel open=%d capture=%d"),
		TimeWheelWidget != nullptr && TimeWheelWidget->IsOpen(), bWheelInputCaptured);
	HandleRightStickX(0.7f);
	HandleRightStickY(-0.7f);
	if (TimeWheelWidget != nullptr)
	{
		UE_LOG(LogFableForge, Display, TEXT("INPUT_QA quick_wheel selected_slot=%d selected=%s"), TimeWheelWidget->GetSelectedSlot(), *TimeWheelWidget->GetSelectedPayload());
	}
	HandleQuickWheelNext();
	HandleQuickWheelPrevious();
	HandleQuickWheelReleased();
	UE_LOG(LogFableForge, Display, TEXT("INPUT_QA quick_wheel released open=%d capture=%d"),
		TimeWheelWidget != nullptr && TimeWheelWidget->IsOpen(), bWheelInputCaptured);

	HandleTimePressed();
	UE_LOG(LogFableForge, Display, TEXT("INPUT_QA time_slow open=%d slow=%d capture=%d"),
		TimeWheelWidget != nullptr && TimeWheelWidget->IsOpen(), bTimeHeld, bWheelInputCaptured);
	HandleRightTrigger(1.0f);
	HandleRightTrigger(0.0f);
	UE_LOG(LogFableForge, Display, TEXT("INPUT_QA time_stop stopped=%d"), bTimeStopped);
	const bool bTargetAccepted = RequestSkillPayload(TEXT("skill:heal_wave"));
	UE_LOG(LogFableForge, Display, TEXT("INPUT_QA targeted_skill accepted=%d targeting=%d"), bTargetAccepted, bTargetingSkill);
	HandleRightTrigger(1.0f);
	HandleRightTrigger(0.0f);
	UE_LOG(LogFableForge, Display, TEXT("INPUT_QA targeted_skill confirmed targeting=%d"), bTargetingSkill);
	HandleTimeReleased();
	HandleTimePressed();
	HandleTimeReleased();

	OpenWheelAssignment();
	UE_LOG(LogFableForge, Display, TEXT("INPUT_QA assignment capture=%d"), bWheelInputCaptured);
	if (WheelAssignmentWidget != nullptr && WheelAssignmentWidget->IsOpen())
	{
		WheelAssignmentWidget->MoveSelection(1);
		WheelAssignmentWidget->ConfirmAssignment();
		const FString Assigned = QuickWheelPages.IsValidIndex(0) && QuickWheelPages[0].Slots.IsValidIndex(1)
			? QuickWheelPages[0].Slots[1].EntryId : FString();
		UE_LOG(LogFableForge, Display, TEXT("INPUT_QA assignment assigned=%s"), *Assigned);
	}
	CancelTargetedSkill();
	UE_LOG(LogFableForge, Display, TEXT("INPUT_QA assignment_cancel capture=%d"), bWheelInputCaptured);

	HandleRightTrigger(1.0f);
	HandleRightTrigger(0.0f);
	HandleLeftTrigger(1.0f);
	HandleLeftTrigger(0.0f);
	HandleDPadRight();
	GestureTravel = 0.5f;
	GestureTurn = 0.0f;
	HandleElementReleased();
	HandleDPadRight();
	GestureTravel = 0.5f;
	GestureTurn = 5.0f;
	HandleElementReleased();
	const bool bItemAccepted = RequestSkillPayload(TEXT("item:health_potion"));
	UE_LOG(LogFableForge, Display, TEXT("INPUT_QA consumable_request accepted=%d"), bItemAccepted);

	const bool bSkillAccepted = RequestSkillPayload(TEXT("skill:heal_wave"));
	UE_LOG(LogFableForge, Display, TEXT("INPUT_QA skill_request accepted=%d"), bSkillAccepted);
	UE_LOG(LogFableForge, Display, TEXT("INPUT_QA complete"));
}

void AFableForgePlayerController::SetWheelInputCapture(bool bCapture)
{
	if (bWheelInputCaptured == bCapture)
	{
		return;
	}
	bWheelInputCaptured = bCapture;
	// Only the right stick belongs to gameplay wheels. Movement capture for
	// journal/assignment/precision targeting is handled by those modes separately.
	if (!IsJournalOpen() && !IsWheelAssignmentOpen())
	{
		// A closed journal can retain Slate navigation focus. Gameplay wheels
		// need D-pad events in the controller, not swallowed by invisible UI.
		if (bCapture) SetInputMode(FInputModeGameOnly());
		else SetInputMode(FInputModeGameAndUI());
		UWidgetBlueprintLibrary::SetFocusToGameViewport();
		bShowMouseCursor = !bCapture;
	}
	// Keep look input flowing while the wheel is open so the Enhanced Input right
	// stick action can be routed to the wheel instead of being discarded.
	SetIgnoreLookInput(false);
	if (bCapture) StopMovement();
}

void AFableForgePlayerController::RouteRightStickToWheel(const FVector2D& Value)
{
	RightStickValue = Value;
	if (TimeWheelWidget != nullptr && TimeWheelWidget->IsOpen() && !bTargetingSkill && Value.SizeSquared() > 0.08f)
	{
		TimeWheelWidget->SetSelectionFromStick(Value);
	}
}

bool AFableForgePlayerController::BuildCosmicWheelPages()
{
	CosmicWheelPages.Reset();
	CosmicWheelPage = 0;

	UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	if (SaveSubsystem == nullptr)
	{
		return false;
	}

	FFableCharacterProfile Profile;
	if (!SaveSubsystem->TryGetActiveCharacterProfile(Profile))
	{
		return false;
	}

	UDataTable* SkillTable = LoadObject<UDataTable>(nullptr, TEXT("/Game/Data/DT_Skills.DT_Skills"));
	TArray<FFableSkillDefinitionTableRow*> SkillRows;
	if (SkillTable != nullptr)
	{
		SkillTable->GetAllRows(TEXT("FableForgePlayerController::BuildCosmicWheelPages"), SkillRows);
	}

	TArray<FFableActionSlotData> CosmicSlots;
	TSet<FString> AddedSkillIds;
	for (const FString& SkillId : Profile.LearnedSkills)
	{
		if (SkillId.IsEmpty() || !FableSkillCatalog::IsAssignableSkillId(SkillId) || AddedSkillIds.Contains(SkillId))
		{
			continue;
		}

		const FFableSkillDefinitionTableRow* Skill = nullptr;
		for (const FFableSkillDefinitionTableRow* Row : SkillRows)
		{
			if (Row != nullptr && Row->SkillId.Equals(SkillId, ESearchCase::IgnoreCase))
			{
				Skill = Row;
				break;
			}
		}
		FFableSkillDefinitionTableRow FallbackSkill;
		if (Skill == nullptr && FableSkillCatalog::TryGetStarterSkillDefinition(SkillId, FallbackSkill))
		{
			Skill = &FallbackSkill;
		}
		bool bIsCosmicSkill = Skill != nullptr && Skill->Category == EFableSkillCategory::TimeManipulation;
		for (const FFableStarterSkillDefinition& Starter : FableSkillCatalog::GetStarterSkills())
		{
			if (SkillId.Equals(Starter.SkillId, ESearchCase::IgnoreCase)
				&& Starter.School == EFableSkillCategory::TimeManipulation)
			{
				bIsCosmicSkill = true;
				break;
			}
		}
		if (Skill == nullptr || !bIsCosmicSkill)
		{
			continue;
		}

		FFableActionSlotData Slot;
		Slot.EntryId = TEXT("skill:") + SkillId;
		Slot.EntryLabel = Skill->DisplayName.IsEmpty() ? SkillId : Skill->DisplayName;
		CosmicSlots.Add(MoveTemp(Slot));
		AddedSkillIds.Add(SkillId);
	}

	for (int32 SlotStart = 0; SlotStart < CosmicSlots.Num(); SlotStart += 8)
	{
		FFableQuickWheelPageData& Page = CosmicWheelPages.AddDefaulted_GetRef();
		Page.PageName = CosmicWheelPages.Num() == 1
			? TEXT("Cosmic")
			: FString::Printf(TEXT("Cosmic %d"), CosmicWheelPages.Num());
		Page.Slots.Append(CosmicSlots.GetData() + SlotStart, FMath::Min(8, CosmicSlots.Num() - SlotStart));
	}

	UE_LOG(LogFableForge, Display, TEXT("COSMIC wheel pages built pages=%d skills=%d"), CosmicWheelPages.Num(), CosmicSlots.Num());
	return CosmicWheelPages.Num() > 0;
}

void AFableForgePlayerController::OpenCosmicWheel()
{
	if (TimeWheelWidget == nullptr)
	{
		EnsureUiWidgets();
	}
	if (bCosmicWheelOpen || TimeWheelWidget == nullptr)
	{
		return;
	}
	if (!BuildCosmicWheelPages())
	{
		UE_LOG(LogFableForge, Display, TEXT("COSMIC wheel hold rejected: no learned TimeManipulation skills"));
		return;
	}

	bCosmicWheelOpen = true;
	bCosmicSelectionActivated = false;
	bQuickWheelHeld = false;
	TimeWheelWidget->SetCosmicWheel(true);
	TimeWheelWidget->Open(CosmicWheelPages);
	TimeWheelWidget->SetPage(CosmicWheelPage);
	SetWheelInputCapture(true);
	SetWheelSlowTime(true);
	UE_LOG(LogFableForge, Display, TEXT("COSMIC wheel opened"));
}

void AFableForgePlayerController::ActivateCosmicWheelSelection()
{
	if (!bCosmicWheelOpen || TimeWheelWidget == nullptr)
	{
		return;
	}
	const FString Payload = TimeWheelWidget->GetSelectedPayload();
	if (!Payload.IsEmpty())
	{
		bCosmicSelectionActivated = true;
		EquipCosmicPower(Payload);
	}
}

void AFableForgePlayerController::CloseCosmicWheel(bool bActivateSelected)
{
	if (!bCosmicWheelOpen)
	{
		return;
	}
	if (bActivateSelected && TimeWheelWidget)
		TimeWheelWidget->SetSelectionFromStick(FVector2D(GetInputAnalogKeyState(EKeys::Gamepad_RightX), GetInputAnalogKeyState(EKeys::Gamepad_RightY)));
	const FString Payload = bActivateSelected && TimeWheelWidget ? TimeWheelWidget->GetSelectedPayload() : FString();
	if (bTargetingSkill)
	{
		// Keep the targeting overlay and Cosmic time state alive until the
		// target is confirmed or explicitly cancelled.
		SetWheelInputCapture(true);
		return;
	}
	bCosmicWheelOpen = false;
	bCosmicSelectionActivated = false;
	if (TimeWheelWidget != nullptr)
	{
		TimeWheelWidget->SetCosmicWheel(false);
		TimeWheelWidget->SetElement(ActiveElement);
		TimeWheelWidget->Close();
	}
	SetWheelInputCapture(false);
	if (!Payload.IsEmpty())
	{
		const bool bAccepted = EquipCosmicPower(Payload);
		UE_LOG(LogFableForge, Display, TEXT("COSMIC_RELEASE payload=%s accepted=%d"), *Payload, bAccepted);
	}
	if (!bTargetingSkill) SetWheelSlowTime(false);
	UE_LOG(LogFableForge, Display, TEXT("COSMIC wheel closed; regular pages preserved pages=%d"), QuickWheelPages.Num());
}

bool AFableForgePlayerController::EquipCosmicPower(const FString& Payload)
{
	if (!Payload.StartsWith(TEXT("skill:"))) return false;
	UFableSaveSubsystem* Save = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	if (!Save) return false;
	const bool bChangedPower = Save->GetActiveCosmicSkillId() != Payload.RightChop(6);
	if (!Save->SetActiveCosmicSkillId(Payload.RightChop(6))) return false;
	// Switching the L3 loadout ends the previously toggled power. Wheel slow
	// time remains owned separately until the selector closes.
	if (bChangedPower) bTimeHeld = false;
	ApplyCosmicTimeState();
	UE_LOG(LogFableForge, Display, TEXT("COSMIC_EQUIPPED L3=%s"), *Payload);
	return true;
}

void AFableForgePlayerController::UpdateCosmicEnergy(double WallNowSeconds)
{
	if (LastCosmicWallTimeSeconds <= 0.0)
	{
		LastCosmicWallTimeSeconds = WallNowSeconds;
		return;
	}

	const double WallDeltaSeconds = FMath::Max(0.0, WallNowSeconds - LastCosmicWallTimeSeconds);
	LastCosmicWallTimeSeconds = WallNowSeconds;
	if (bTargetingSkill || bTimeStopped) return;
	if (IsSlowTimeActive())
	{
		CosmicEnergy = FMath::Max(0.0f, CosmicEnergy - CosmicDrainPerSecond * static_cast<float>(WallDeltaSeconds));
		if (CosmicEnergy <= KINDA_SMALL_NUMBER)
		{
			CosmicEnergy = 0.0f;
			UE_LOG(LogFableForge, Display, TEXT("COSMIC depleted; restoring normal time and cancelling active targeting/wheel"));
			DeactivateCosmicTime();
		}
	}
	else
	{
		CosmicEnergy = FMath::Min(MaxCosmicEnergy, CosmicEnergy + CosmicRecoveryPerSecond * static_cast<float>(WallDeltaSeconds));
	}
}

void AFableForgePlayerController::DeactivateCosmicTime()
{
	EndPrecisionTarget();
	bPendingWeaponAttack = false;
	PendingSkillId.Reset();
	CloseCosmicWheel(false);
	bTimeHeld = false;
	bWheelSlowTime = false;
	bTimeStopped = false;
	bTimeButtonDown = false;
	bCosmicInputCancelled = false;
	bCosmicSelectionActivated = false;
	bQuickWheelHeld = false;
	bTargetingSkill = false;
	PendingSkillId.Reset();
	if (GetWorld() != nullptr && GetWorld()->GetWorldSettings() != nullptr)
	{
		GetWorld()->GetWorldSettings()->SetTimeDilation(1.0f);
	}
	if (TimeWheelWidget != nullptr)
	{
		TimeWheelWidget->SetTimeState(false, false);
		TimeWheelWidget->EndTargeting();
		TimeWheelWidget->Close();
	}
	SetWheelInputCapture(false);
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
	if (GetWorld() && GetWorld()->GetGameViewport())
	{
		GetWorld()->GetGameViewport()->bDisableWorldRendering = false;
	}

	ResetIgnoreLookInput();
	ResetIgnoreMoveInput();
	ApplyActiveCharacterMesh();
	if (AFableForgeGameMode* GameMode = GetWorld() ? GetWorld()->GetAuthGameMode<AFableForgeGameMode>() : nullptr)
	{
		GameMode->EnsureTrainingEnemy(GetPawn());
	}

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
	if (UFableSaveSubsystem* ActiveSaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr)
	{
		ActiveSaveSubsystem->TryGetActiveQuickWheelPages(QuickWheelPages);
	}
	if (CharacterMenuWidget != nullptr)
	{
		CharacterMenuWidget->Close();
	}
	CloseChest();

	FInputModeGameAndUI InputMode;
	InputMode.SetHideCursorDuringCapture(false);
	InputMode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
	SetInputMode(InputMode);
	bShowMouseCursor = true;
	bEnableClickEvents = true;
	bEnableMouseOverEvents = true;
}

void AFableForgePlayerController::ShowMainMenu()
{
	DeactivateCosmicTime();
	StopMovement();
	ClearPendingInteraction();
	ResetIgnoreLookInput();
	ResetIgnoreMoveInput();
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
	if (GetWorld() && GetWorld()->GetGameViewport())
	{
		// The storybook is the front end. The village is revealed only after a character is loaded.
		GetWorld()->GetGameViewport()->bDisableWorldRendering = true;
	}

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
	InputMode.SetWidgetToFocus(MainMenuWidget->TakeWidget());
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
	if (ChestWidget != nullptr && ChestWidget->IsChestOpen())
	{
		return;
	}
	if (MainMenuWidget != nullptr && MainMenuWidget->IsInViewport())
	{
		return;
	}
	CloseChest();
	EnsureUiWidgets();
	if (CharacterMenuWidget != nullptr)
	{
		CharacterMenuWidget->Toggle();

		if (CharacterMenuWidget->IsOpen())
		{
			// Journal navigation owns every controller face/shoulder/trigger path;
			// clear any held gameplay gesture so opening it cannot leave a wheel,
			// time stop, targeting state, or element gesture active underneath.
			bRightTriggerLatched = false;
			bLeftTriggerLatched = false;
			bElementHeld = false;
			bQuickWheelHeld = false;
			bTimeHeld = false;
			bWheelSlowTime = false;
			bTimeButtonDown = false;
			bCosmicInputCancelled = false;
			EndPrecisionTarget();
			bPendingWeaponAttack = false;
			CloseCosmicWheel(false);
			bTimeStopped = false;
			bTargetingSkill = false;
			PendingSkillId.Reset();
			if (GetWorld()) GetWorld()->GetWorldSettings()->SetTimeDilation(1.0f);
			if (TimeWheelWidget != nullptr)
			{
				TimeWheelWidget->SetTimeState(false, false);
				TimeWheelWidget->EndTargeting();
				TimeWheelWidget->Close();
			}
			SetWheelInputCapture(false);
			StopMovement();
			ClearPendingInteraction();
			FInputModeGameAndUI InputMode;
			InputMode.SetHideCursorDuringCapture(false);
			InputMode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
			InputMode.SetWidgetToFocus(CharacterMenuWidget->TakeWidget());
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
			// A collapsed journal can retain Slate navigation focus and swallow
			// the first D-pad press. Return ownership explicitly on every close.
			UWidgetBlueprintLibrary::SetFocusToGameViewport();
			// A trigger held for tab navigation must return to neutral before it
			// can become a gameplay attack after the journal closes.
			bRightTriggerLatched = IsInputKeyDown(EKeys::Gamepad_RightTrigger) || GetInputAnalogKeyState(EKeys::Gamepad_RightTriggerAxis) > .2f;
			bLeftTriggerLatched = IsInputKeyDown(EKeys::Gamepad_LeftTrigger) || GetInputAnalogKeyState(EKeys::Gamepad_LeftTriggerAxis) > .2f;
		}
	}
}

void AFableForgePlayerController::CloseActivePanel()
{
	if (PartyHudWidget != nullptr && PartyHudWidget->IsModalOpen())
	{
		PartyHudWidget->CloseModal();
	}
	else if (CharacterMenuWidget != nullptr && CharacterMenuWidget->IsOpen())
	{
		ToggleCharacterMenu();
	}
	else if (ChestWidget != nullptr && ChestWidget->IsChestOpen())
	{
		CloseChest();
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

	ResetGameplayInputForChest();
	ChestWidget->OpenForChest(Chest, this);

	FInputModeGameAndUI InputMode;
	InputMode.SetHideCursorDuringCapture(false);
	InputMode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
	InputMode.SetWidgetToFocus(ChestWidget->TakeWidget());
	SetInputMode(InputMode);
	SetIgnoreMoveInput(true);
	SetIgnoreLookInput(true);
	ChestWidget->FocusControllerSelection();
	bShowMouseCursor = true;
	bEnableClickEvents = true;
	bEnableMouseOverEvents = true;
}

void AFableForgePlayerController::CloseChest()
{
	ResetGameplayInputForChest();
	if (ChestWidget != nullptr)
	{
		ChestWidget->CloseChest();
	}

	FInputModeGameAndUI InputMode;
	InputMode.SetHideCursorDuringCapture(false);
	InputMode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
	SetInputMode(InputMode);
	ResetIgnoreMoveInput();
	ResetIgnoreLookInput();
	UWidgetBlueprintLibrary::SetFocusToGameViewport();
	bShowMouseCursor = true;
	bEnableClickEvents = true;
	bEnableMouseOverEvents = true;
}

void AFableForgePlayerController::ResetGameplayInputForChest()
{
	EndPrecisionTarget();
	bPendingWeaponAttack = false;
	CloseCosmicWheel(false);
	bQuickWheelHeld = false;
	bTimeHeld = false;
	bWheelSlowTime = false;
	bTimeButtonDown = false;
	bCosmicSelectionActivated = false;
	bCosmicInputCancelled = false;
	bTimeStopped = false;
	bElementHeld = false;
	bTargetingSkill = false;
	bRightTriggerLatched = IsInputKeyDown(EKeys::Gamepad_RightTrigger) || GetInputAnalogKeyState(EKeys::Gamepad_RightTriggerAxis) > .2f;
	bLeftTriggerLatched = IsInputKeyDown(EKeys::Gamepad_LeftTrigger) || GetInputAnalogKeyState(EKeys::Gamepad_LeftTriggerAxis) > .2f;
	PendingSkillId.Reset();
	PendingTargetActor.Reset();
	RightStickValue = FVector2D::ZeroVector;
	GestureTravel = 0.0f;
	GestureTurn = 0.0f;

	if (GetWorld() != nullptr && GetWorld()->GetWorldSettings() != nullptr)
	{
		GetWorld()->GetWorldSettings()->SetTimeDilation(1.0f);
	}
	if (TimeWheelWidget != nullptr)
	{
		TimeWheelWidget->SetTimeState(false, false);
		TimeWheelWidget->EndTargeting();
		TimeWheelWidget->Close();
	}
	SetWheelInputCapture(false);
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
	if (MeshComponent->GetSkeletalMeshAsset() != CharacterMesh)
	{
		MeshComponent->SetSkeletalMesh(CharacterMesh);
		if (ExistingAnimClass != nullptr)
		{
			MeshComponent->SetAnimInstanceClass(ExistingAnimClass);
		}
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

	if (TimeWheelWidget == nullptr)
	{
		TimeWheelWidget = CreateWidget<UFableTimeWheelWidget>(this, UFableTimeWheelWidget::StaticClass());
		if (TimeWheelWidget != nullptr)
		{
			TimeWheelWidget->AddToViewport(60);
			TimeWheelWidget->SetVisibility(ESlateVisibility::Collapsed);
		}
	}

	if (WheelAssignmentWidget == nullptr)
	{
		WheelAssignmentWidget = CreateWidget<UFableWheelAssignmentWidget>(this, UFableWheelAssignmentWidget::StaticClass());
		if (WheelAssignmentWidget != nullptr)
		{
			WheelAssignmentWidget->AddToViewport(70);
			WheelAssignmentWidget->SetVisibility(ESlateVisibility::Collapsed);
			WheelAssignmentWidget->OnPagesChanged.AddDynamic(this, &AFableForgePlayerController::HandleWheelAssignmentChanged);
			WheelAssignmentWidget->OnClosed.AddDynamic(this, &AFableForgePlayerController::HandleWheelAssignmentClosed);
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
	// Modal screens must win before the global action-bar click fallback.
	if (IsGameInteractionBlocked())
	{
		return;
	}
	UE_LOG(LogFableForge, Log, TEXT("Interact click start partyHud=%s visible=%d"),
		*GetNameSafe(PartyHudWidget),
		(PartyHudWidget != nullptr && PartyHudWidget->IsVisible()) ? 1 : 0);

	if (PartyHudWidget != nullptr)
	{
		float MouseX = 0.0f;
		float MouseY = 0.0f;
		if (GetMousePosition(MouseX, MouseY))
		{
			const FVector2D MouseScreenPosition(MouseX, MouseY);
			const bool bActionBarHandled = PartyHudWidget->TryUseActionAtScreenPosition(MouseScreenPosition);
			UE_LOG(LogFableForge, Log, TEXT("Interact click precheck actionBarHandled=%d mouse=(%.1f, %.1f)"),
				bActionBarHandled ? 1 : 0, MouseX, MouseY);
			if (bActionBarHandled)
			{
				return;
			}
		}
		else
		{
			UE_LOG(LogFableForge, Verbose, TEXT("Interact click precheck: GetMousePosition failed"));
		}
	}
	else
	{
		UE_LOG(LogFableForge, Warning, TEXT("Interact click precheck skipped: PartyHudWidget is null"));
	}

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

	BeginInteractionFromHit(HitResult);
}

bool AFableForgePlayerController::TraceFocusedInteractable(FHitResult& OutHit) const
{
	int32 Width = 0, Height = 0;
	GetViewportSize(Width, Height);
	FVector Origin, Direction;
	if (!GetWorld() || Width <= 0 || Height <= 0 || !DeprojectScreenPositionToWorld(Width * .5f, Height * .5f, Origin, Direction)) return false;
	FCollisionQueryParams Params(SCENE_QUERY_STAT(JournalFocus), false, GetPawn());
	// Stop at the first blocking surface: a door behind a wall is not focusable.
	if (!GetWorld()->LineTraceSingleByChannel(OutHit, Origin, Origin + Direction * (MaxInteractableSelectionDistance + 1000.f), ECC_Visibility, Params)) return false;
	return IsActorInteractable(OutHit.GetActor()) && IsActorWithinSelectionDistance(OutHit.GetActor());
}

void AFableForgePlayerController::HandleFocusedInteract()
{
	if (ChestWidget != nullptr && ChestWidget->IsChestOpen()) { if (!ChestWidget->HasAnyUserFocus()) ChestWidget->TakeAllItems(); return; }
	if (IsGameInteractionBlocked()) return;
	FHitResult Hit;
	if (TraceFocusedInteractable(Hit)) BeginInteractionFromHit(Hit);
}

void AFableForgePlayerController::BeginInteractionFromHit(const FHitResult& HitResult)
{
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
		if (PartyHudWidget) PartyHudWidget->SetInteractionFocus(false, false);
		ClearHoveredInteractable();
		return;
	}

	FHitResult HitResult;
	AActor* NewHoveredActor = nullptr;
	const bool bFocused = TraceFocusedInteractable(HitResult);
	if (PartyHudWidget) PartyHudWidget->SetInteractionFocus(true, bFocused);
	if (bFocused || GetHitResultUnderCursor(ECC_Visibility, false, HitResult))
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
		UE_LOG(LogFableForge, VeryVerbose, TEXT("Interact pending: %s out of range (distance %.1f > required %.1f)"),
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
	if (IsWheelAssignmentOpen() || (TimeWheelWidget && TimeWheelWidget->IsOpen()) || bTargetingSkill) return true;
	if (PartyHudWidget != nullptr && PartyHudWidget->IsModalOpen())
	{
		return true;
	}
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

bool AFableForgePlayerController::IsJournalOpen() const
{
	return CharacterMenuWidget != nullptr
		&& CharacterMenuWidget->IsInViewport()
		&& CharacterMenuWidget->IsOpen();
}

bool AFableForgePlayerController::IsControllerUiInputHandledByFocusedWidget() const
{
	if (IsWheelAssignmentOpen())
	{
		return WheelAssignmentWidget->HasAnyUserFocus();
	}
	return IsJournalOpen() && CharacterMenuWidget->HasAnyUserFocus();
}

bool AFableForgePlayerController::IsWheelAssignmentOpen() const
{
	return WheelAssignmentWidget != nullptr
		&& WheelAssignmentWidget->IsInViewport()
		&& WheelAssignmentWidget->IsOpen();
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
