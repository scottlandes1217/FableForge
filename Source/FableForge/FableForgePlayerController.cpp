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
#include "RPG/Gameplay/FableSpellRuntime.h"
#include "Variant_Combat/Interfaces/CombatDamageable.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Animation/AnimSequence.h"
#include "Animation/AnimSequenceBase.h"
#include "TimerManager.h"
#include "DrawDebugHelpers.h"
#include "Engine/DataTable.h"
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
		InputComponent->BindKey(EKeys::Gamepad_FaceButton_Right, IE_Pressed, this, &AFableForgePlayerController::CancelTargetedSkill);
		InputComponent->BindKey(EKeys::Gamepad_FaceButton_Bottom, IE_Pressed, this, &AFableForgePlayerController::HandleControllerActivate);
		InputComponent->BindKey(EKeys::Gamepad_Special_Right, IE_Pressed, this, &AFableForgePlayerController::ToggleCharacterMenu);
		InputComponent->BindAxis(TEXT("FF_RightStickX"), this, &AFableForgePlayerController::HandleRightStickX);
		InputComponent->BindAxis(TEXT("FF_RightStickY"), this, &AFableForgePlayerController::HandleRightStickY);
		InputComponent->BindAxis(TEXT("FF_RightTrigger"), this, &AFableForgePlayerController::HandleRightTrigger);
		InputComponent->BindAxis(TEXT("FF_LeftTrigger"), this, &AFableForgePlayerController::HandleLeftTrigger);
	}
}

void AFableForgePlayerController::PlayerTick(float DeltaTime)
{
	Super::PlayerTick(DeltaTime);
	if (IsJournalOpen() || IsWheelAssignmentOpen())
	{
		UpdateHoveredInteractable();
		return;
	}
	if (bTimeHeld)
	{
		TimeHeldSeconds += DeltaTime;
		if (!bQuickWheelHeld && TimeHeldSeconds >= TimeHoldThreshold && TimeWheelWidget != nullptr && !TimeWheelWidget->IsOpen())
		{
			TimeWheelWidget->Open(QuickWheelPages);
			TimeWheelWidget->SetElement(ActiveElement);
			SetWheelInputCapture(true);
		}
	}

	if (TimeWheelWidget != nullptr && TimeWheelWidget->IsOpen() && !bTargetingSkill && RightStickValue.SizeSquared() > 0.08f)
	{
		TimeWheelWidget->SetSelectionFromStick(RightStickValue);
	}

	if (bElementHeld && RightStickValue.SizeSquared() > 0.08f)
	{
		const float Now = GetWorld() ? GetWorld()->GetTimeSeconds() : 0.0f;
		if (Now - LastGestureSampleTime >= GestureSampleInterval)
		{
			const float Angle = FMath::Atan2(RightStickValue.Y, RightStickValue.X);
			if (GestureTravel > 0.0f) GestureTurn += FMath::FindDeltaAngleRadians(LastGestureAngle, Angle);
			LastGestureAngle = Angle;
			LastGestureSampleTime = Now;
			GestureTravel += RightStickValue.Size() * GestureSampleInterval;
		}
	}
	if (bTargetingSkill && RightStickValue.SizeSquared() > 0.04f)
	{
		const FVector Forward = FRotationMatrix(GetControlRotation()).GetUnitAxis(EAxis::X);
		const FVector Right = FRotationMatrix(GetControlRotation()).GetUnitAxis(EAxis::Y);
		PendingTargetLocation += (Forward * RightStickValue.Y + Right * RightStickValue.X) * DeltaTime * 350.0f;
		if (TimeWheelWidget) TimeWheelWidget->SetTargetLocation(PendingTargetLocation);
	}

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
	if (IsJournalOpen())
	{
		if (!IsControllerUiInputHandledByFocusedWidget()) CharacterMenuWidget->MoveControllerSelection(0, -1);
		return;
	}
	ActiveElement = TEXT("Air"); bElementHeld = true; GestureTravel = 0.0f; GestureTurn = 0.0f; if (TimeWheelWidget) TimeWheelWidget->SetElement(ActiveElement);
}
void AFableForgePlayerController::HandleDPadDown()
{
	if (IsWheelAssignmentOpen()) return;
	if (IsJournalOpen())
	{
		if (!IsControllerUiInputHandledByFocusedWidget()) CharacterMenuWidget->MoveControllerSelection(0, 1);
		return;
	}
	ActiveElement = TEXT("Earth"); bElementHeld = true; GestureTravel = 0.0f; GestureTurn = 0.0f; if (TimeWheelWidget) TimeWheelWidget->SetElement(ActiveElement);
}
void AFableForgePlayerController::HandleDPadLeft()
{
	if (IsWheelAssignmentOpen()) return;
	if (IsJournalOpen())
	{
		if (!IsControllerUiInputHandledByFocusedWidget()) CharacterMenuWidget->MoveControllerSelection(-1, 0);
		return;
	}
	ActiveElement = TEXT("Water"); bElementHeld = true; GestureTravel = 0.0f; GestureTurn = 0.0f; if (TimeWheelWidget) TimeWheelWidget->SetElement(ActiveElement);
}
void AFableForgePlayerController::HandleDPadRight()
{
	if (IsWheelAssignmentOpen()) return;
	if (IsJournalOpen())
	{
		if (!IsControllerUiInputHandledByFocusedWidget()) CharacterMenuWidget->MoveControllerSelection(1, 0);
		return;
	}
	ActiveElement = TEXT("Fire"); bElementHeld = true; GestureTravel = 0.0f; GestureTurn = 0.0f; if (TimeWheelWidget) TimeWheelWidget->SetElement(ActiveElement);
}
void AFableForgePlayerController::HandleElementReleased()
{
	if (IsJournalOpen() || IsWheelAssignmentOpen())
	{
		bElementHeld = false;
		return;
	}
	if (bElementHeld && GestureTravel > 0.35f)
	{
		const bool bCircle = FMath::Abs(GestureTurn) > 4.2f;
		FString Spell;
		if (ActiveElement == TEXT("Fire")) Spell = bCircle ? TEXT("fire_tornado") : TEXT("fireball");
		else if (ActiveElement == TEXT("Water")) Spell = TEXT("heal_wave");
		else if (ActiveElement == TEXT("Air")) Spell = TEXT("gust");
		else if (ActiveElement == TEXT("Earth")) Spell = TEXT("basic_attack");
		UE_LOG(LogFableForge, Log, TEXT("Element gesture resolved element=%s gesture=%s spell=%s"), *ActiveElement.ToString(), bCircle ? TEXT("circle") : TEXT("burst"), *Spell);
		if (!Spell.IsEmpty() && PartyHudWidget != nullptr) PartyHudWidget->TryUseQuickWheelPayload(TEXT("skill:") + Spell);
	}
	bElementHeld = false;
}

void AFableForgePlayerController::HandleTimePressed()
{
	if (IsJournalOpen())
	{
		if (!IsWheelAssignmentOpen() && !IsControllerUiInputHandledByFocusedWidget()) CharacterMenuWidget->CycleCategoryTab(-1);
		return;
	}
	if (IsJournalOpen() || IsWheelAssignmentOpen()) return;
	bTimeHeld = true; TimeHeldSeconds = 0.0f; bTimeStopped = false;
	if (GetWorld()) GetWorld()->GetWorldSettings()->SetTimeDilation(SlowTimeDilation);
	if (TimeWheelWidget) TimeWheelWidget->SetTimeState(true, false);
}

void AFableForgePlayerController::HandleTimeReleased()
{
	if (IsJournalOpen() || IsWheelAssignmentOpen()) return;
	bTimeHeld = false; bTimeStopped = false;
	if (GetWorld()) GetWorld()->GetWorldSettings()->SetTimeDilation(1.0f);
	if (TimeWheelWidget) TimeWheelWidget->SetTimeState(false, false);
	if (TimeWheelWidget != nullptr && !bQuickWheelHeld)
	{
		TimeWheelWidget->Close();
		SetWheelInputCapture(false);
	}
}

void AFableForgePlayerController::HandleQuickWheelPressed()
{
	if (IsJournalOpen())
	{
		if (!IsWheelAssignmentOpen() && !IsControllerUiInputHandledByFocusedWidget()) CharacterMenuWidget->CycleCategoryTab(1);
		return;
	}
	if (IsJournalOpen() || IsWheelAssignmentOpen()) return;
	bQuickWheelHeld = true;
	if (TimeWheelWidget != nullptr)
	{
		TimeWheelWidget->Open(QuickWheelPages);
		TimeWheelWidget->SetElement(ActiveElement);
		SetWheelInputCapture(true);
	}
}

void AFableForgePlayerController::HandleLeftTriggerPressed()
{
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
	if (IsJournalOpen() || IsWheelAssignmentOpen())
	{
		bLeftTriggerLatched = false;
		return;
	}
	HandleLeftTrigger(0.0f);
}

void AFableForgePlayerController::HandleQuickWheelReleased()
{
	if (IsJournalOpen() || IsWheelAssignmentOpen()) return;
	bQuickWheelHeld = false;
	if (TimeWheelWidget != nullptr && TimeWheelWidget->IsOpen())
	{
		const FString Payload = TimeWheelWidget->GetSelectedPayload();
		if (!Payload.IsEmpty() && PartyHudWidget != nullptr) PartyHudWidget->TryUseQuickWheelPayload(Payload);
		if (!bTimeHeld)
		{
			TimeWheelWidget->Close();
			SetWheelInputCapture(false);
		}
	}
}

void AFableForgePlayerController::HandleQuickWheelNext() { if (!IsJournalOpen() && !IsWheelAssignmentOpen() && TimeWheelWidget && TimeWheelWidget->IsOpen()) TimeWheelWidget->SetPage(++QuickWheelPage); }
void AFableForgePlayerController::HandleQuickWheelPrevious() { if (!IsJournalOpen() && !IsWheelAssignmentOpen() && TimeWheelWidget && TimeWheelWidget->IsOpen()) TimeWheelWidget->SetPage(--QuickWheelPage); }
void AFableForgePlayerController::HandleRightTriggerPressed()
{
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
	if (TimeWheelWidget != nullptr && TimeWheelWidget->IsOpen())
	{
		HandleQuickWheelNext();
		return;
	}
	HandleRightTrigger(1.0f);
}
void AFableForgePlayerController::HandleRightTriggerReleased() { if (!IsJournalOpen() && !IsWheelAssignmentOpen()) HandleRightTrigger(0.0f); else bRightTriggerLatched = false; }
void AFableForgePlayerController::HandleRightStickX(float Value) { RightStickValue.X = Value; if (!IsJournalOpen() && !IsWheelAssignmentOpen()) RouteRightStickToWheel(RightStickValue); }
void AFableForgePlayerController::HandleRightStickY(float Value) { RightStickValue.Y = Value; if (!IsJournalOpen() && !IsWheelAssignmentOpen()) RouteRightStickToWheel(RightStickValue); }
void AFableForgePlayerController::HandleRightTrigger(float Value)
{
	if (IsWheelAssignmentOpen()) return;
	if (IsJournalOpen())
	{
		if (Value > 0.85f && !bRightTriggerLatched)
		{
			bRightTriggerLatched = true;
			CharacterMenuWidget->CycleMainTab(1);
		}
		if (Value < 0.2f) bRightTriggerLatched = false;
		return;
	}
	if (Value > 0.85f && !bRightTriggerLatched)
	{
		bRightTriggerLatched = true;
		if (bTargetingSkill) ConfirmTargetedSkill();
		else if (bTimeHeld && !bTimeStopped)
		{
			bTimeStopped = true;
			if (GetWorld()) GetWorld()->GetWorldSettings()->SetTimeDilation(0.0f);
			if (TimeWheelWidget) TimeWheelWidget->SetTimeState(true, true);
		}
		else if (!bTimeHeld && !(TimeWheelWidget && TimeWheelWidget->IsOpen())) PerformWeaponAttack(false);
	}
	if (Value < 0.2f) bRightTriggerLatched = false;
}
void AFableForgePlayerController::HandleLeftTrigger(float Value)
{
	if (IsWheelAssignmentOpen()) return;
	if (IsJournalOpen())
	{
		if (Value > 0.85f && !bLeftTriggerLatched)
		{
			bLeftTriggerLatched = true;
			CharacterMenuWidget->CycleMainTab(-1);
		}
		if (Value < 0.2f) bLeftTriggerLatched = false;
		return;
	}
	if (Value > 0.85f && !bLeftTriggerLatched)
	{
		bLeftTriggerLatched = true;
		if (bTargetingSkill) ConfirmTargetedSkill();
		else if (!bTimeHeld && !(TimeWheelWidget && TimeWheelWidget->IsOpen())) PerformWeaponAttack(true);
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
	APawn* Pawn = GetPawn();
	if (Pawn == nullptr || GetWorld() == nullptr) return;
	UE_LOG(LogFableForge, Display, TEXT("INPUT_QA weapon_attack hand=%s"), bOffHand ? TEXT("off") : TEXT("main"));
	FHitResult AimHit;
	const FVector AimPoint = ResolveAimPoint(&AimHit);
	const FVector Start = Pawn->GetActorLocation() + FVector(0, 0, 70);
	const FVector Direction = (AimPoint - Start).GetSafeNormal();
	const FVector End = Start + Direction * 180.0f;
	FCollisionShape Shape = FCollisionShape::MakeSphere(65.0f);
	FCollisionQueryParams Params(SCENE_QUERY_STAT(FableWeaponAttack), false, Pawn);
	TArray<FHitResult> Hits;
	if (GetWorld()->SweepMultiByObjectType(Hits, Start, End, FQuat::Identity, FCollisionObjectQueryParams(ECC_Pawn | ECC_WorldDynamic), Shape, Params))
	{
		for (const FHitResult& Hit : Hits)
			if (ICombatDamageable* Damageable = Cast<ICombatDamageable>(Hit.GetActor()))
				Damageable->ApplyDamage(bOffHand ? 16.0f : 22.0f, Pawn, Hit.ImpactPoint, Direction * (bOffHand ? 120.0f : 180.0f) + FVector(0, 0, 80));
	}
	if (ACharacter* Character = Cast<ACharacter>(Pawn))
		if (USkeletalMeshComponent* Mesh = Character->GetMesh())
			if (UAnimationAsset* Attack = LoadObject<UAnimationAsset>(nullptr, TEXT("/Game/Characters/PlayableCharacter/Anims/Unarmed/Attack/MM_Attack_01.MM_Attack_01")))
			{
				Mesh->PlayAnimation(Attack, false);
				const float RestoreDelay = FMath::Max(0.2f, Cast<UAnimSequenceBase>(Attack) ? Cast<UAnimSequenceBase>(Attack)->GetPlayLength() : 0.7f);
				TWeakObjectPtr<USkeletalMeshComponent> WeakMesh(Mesh);
				FTimerHandle RestoreAnimationTimer;
				GetWorld()->GetTimerManager().SetTimer(RestoreAnimationTimer, FTimerDelegate::CreateLambda([WeakMesh]()
				{
					if (USkeletalMeshComponent* RestoredMesh = WeakMesh.Get())
					{
						RestoredMesh->SetAnimationMode(EAnimationMode::AnimationBlueprint);
						RestoredMesh->InitAnim(true);
					}
				}), RestoreDelay, false);
			}
	DrawDebugLine(GetWorld(), Start, End, bOffHand ? FColor::Blue : FColor::White, false, 0.35f, 0, 4.0f);
}

bool AFableForgePlayerController::RequestSkillPayload(const FString& PayloadId)
{
	if (PayloadId.StartsWith(TEXT("item:")))
	{
		UE_LOG(LogFableForge, Log, TEXT("Quick wheel consumable requested: %s"), *PayloadId);
		return true;
	}
	if (!PayloadId.StartsWith(TEXT("skill:"))) return false;
	PendingSkillId = PayloadId;
	PendingSkillId.RemoveFromStart(TEXT("skill:"));
	FString SkillPath = TEXT("/Game/Data/DT_Skills.DT_Skills");
	UDataTable* Table = LoadObject<UDataTable>(nullptr, *SkillPath);
	const FFableSkillDefinitionTableRow* Skill = nullptr;
	if (Table)
	{
		TArray<FFableSkillDefinitionTableRow*> Rows;
		Table->GetAllRows(TEXT("FableForgePlayerController::RequestSkillPayload"), Rows);
		for (const FFableSkillDefinitionTableRow* Row : Rows) if (Row && Row->SkillId == PendingSkillId) { Skill = Row; break; }
	}
	if (!Skill) return false;
	FHitResult Hit;
	PendingTargetLocation = ResolveAimPoint(&Hit);
	PendingTargetActor = Hit.GetActor();
	if (bTimeHeld && Skill->TargetingMode != EFableSkillTargetingMode::Self && Skill->TargetingMode != EFableSkillTargetingMode::Weapon && Skill->TargetingMode != EFableSkillTargetingMode::Equipment)
	{
		bTargetingSkill = true;
		if (TimeWheelWidget) TimeWheelWidget->BeginTargeting(Skill->DisplayName, PendingTargetLocation);
		return true;
	}
	if (ACharacter* Character = Cast<ACharacter>(GetPawn()))
		if (USkeletalMeshComponent* Mesh = Character->GetMesh())
			if (UAnimationAsset* Animation = Skill->CharacterAnimationAsset.LoadSynchronous()) Mesh->PlayAnimation(Animation, false);
	return FFableSpellRuntime::ExecuteSkill(GetWorld(), GetPawn(), PendingSkillId, Skill->TargetingMode == EFableSkillTargetingMode::Self ? GetPawn()->GetActorLocation() : PendingTargetLocation, PendingTargetActor.Get());
}

void AFableForgePlayerController::ConfirmTargetedSkill()
{
	if (!bTargetingSkill) return;
	bTargetingSkill = false;
	if (TimeWheelWidget) TimeWheelWidget->EndTargeting();
	FFableSpellRuntime::ExecuteSkill(GetWorld(), GetPawn(), PendingSkillId, PendingTargetLocation, PendingTargetActor.Get());
	PendingSkillId.Reset();
}

void AFableForgePlayerController::CancelTargetedSkill()
{
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
	bTargetingSkill = false;
	PendingSkillId.Reset();
	if (TimeWheelWidget) TimeWheelWidget->EndTargeting();
}

void AFableForgePlayerController::HandleControllerActivate()
{
	if (IsWheelAssignmentOpen() || !IsJournalOpen() || IsControllerUiInputHandledByFocusedWidget()) return;
	CharacterMenuWidget->ActivateControllerSelection();
}

void AFableForgePlayerController::ToggleFirstPersonView()
{
	if (IsJournalOpen() || IsWheelAssignmentOpen()) return;
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
		Payloads.Add(TEXT("skill:") + SkillId);
		const FFableSkillDefinitionTableRow* Skill = nullptr;
		for (const auto* Row : SkillRows) if (Row && Row->SkillId == SkillId) { Skill = Row; break; }
		Labels.Add(Skill && !Skill->DisplayName.IsEmpty() ? Skill->DisplayName : SkillId);
	}
	for (const FString& ItemId : Profile.InventorySlots)
	{
		if (!ItemId.IsEmpty()) { Payloads.Add(TEXT("item:") + ItemId); Labels.Add(ItemId); }
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
	if (UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr)
		SaveSubsystem->SetActiveQuickWheelPages(QuickWheelPages);
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
	TimeHeldSeconds = TimeHoldThreshold;
	PlayerTick(0.0f);
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
	bWheelInputCaptured = bCapture;
	SetIgnoreMoveInput(bCapture);
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
	if (UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr)
	{
		SaveSubsystem->TryGetActiveQuickWheelPages(QuickWheelPages);
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
