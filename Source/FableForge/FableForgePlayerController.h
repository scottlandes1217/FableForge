// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "RPG/Data/FableForgeRPGTypes.h"
#include "FableForgePlayerController.generated.h"

class UFableCharacterMenuWidget;
class UFableChestWidget;
class UFableMainMenuWidget;
class UFablePartyHudWidget;
class UFableTimeWheelWidget;
class UFableWheelAssignmentWidget;
class UInputMappingContext;
class UUserWidget;
class AFFChestInteractable;
class UPrimitiveComponent;

/**
 *  Player controller that now owns menu + HUD flow for the RPG prototype.
 */
UCLASS()
class AFableForgePlayerController : public APlayerController
{
	GENERATED_BODY()

public:
	void EnterGameFromCharacterSlot(const FGuid& CharacterId, int32 SlotIndex, bool bCreateNewSave);
	void ShowMainMenu();
	void NotifyManualMoveInput();
	void ToggleFirstPersonView();
	void OpenWheelAssignment();
	void OpenWheelAssignmentForPayload(const FString& PreferredPayload);
	void OpenSkillsForQa();
	void OpenQuickWheelForQa();
	bool IsWheelInputCaptured() const { return bWheelInputCaptured || bElementHeld || bTargetingSkill; }
	// Gameplay wheels own aiming, not locomotion. Assignment and precision
	// targeting still capture movement; journal/chest also use ignore-move input.
	bool IsCharacterMovementCaptured() const
	{
		return bTargetingSkill || IsWheelAssignmentOpen()
			|| (bElementHeld && !bQuickWheelHeld && !bCosmicWheelOpen);
	}
	bool IsTargetingForQa() const { return bTargetingSkill; }
	FVector2D GetTargetCursorForQa() const { return TargetCursorPixels; }
	void RouteRightStickToWheel(const FVector2D& Value);
	void RunControllerInputSmokeTest();
	bool RequestSkillPayload(const FString& PayloadId);
	bool ConsumeInventoryItem(int32 InventorySlot);
	UFUNCTION(BlueprintPure, Category = "Cosmic")
	float GetCosmicEnergy() const { return CosmicEnergy; }
	UFUNCTION(BlueprintPure, Category = "Cosmic")
	float GetMaxCosmicEnergy() const { return MaxCosmicEnergy; }
	void ConfirmTargetedSkill();
	void CancelTargetedSkill();
	bool TryStartGameplayJump();

	UFUNCTION(BlueprintCallable, Category = "UI")
	void ToggleCharacterMenu();

	UFUNCTION(BlueprintCallable, Category = "UI")
	void OpenChest(AFFChestInteractable* Chest);

	UFUNCTION(BlueprintCallable, Category = "UI")
	void CloseChest();

	UFUNCTION(BlueprintPure, Category = "UI")
	UFablePartyHudWidget* GetPartyHudWidget() const { return PartyHudWidget; }

protected:
	/** Input Mapping Contexts */
	UPROPERTY(EditAnywhere, Category = "Input|Input Mappings")
	TArray<UInputMappingContext*> DefaultMappingContexts;

	/** Input Mapping Contexts */
	UPROPERTY(EditAnywhere, Category = "Input|Input Mappings")
	TArray<UInputMappingContext*> MobileExcludedMappingContexts;

	/** Mobile controls widget to spawn */
	UPROPERTY(EditAnywhere, Category = "Input|Touch Controls")
	TSubclassOf<UUserWidget> MobileControlsWidgetClass;

	/** Pointer to the mobile controls widget */
	UPROPERTY()
	TObjectPtr<UUserWidget> MobileControlsWidget;

	/** If true, the player will use UMG touch controls even if not playing on mobile platforms */
	UPROPERTY(EditAnywhere, Config, Category = "Input|Touch Controls")
	bool bForceTouchControls = false;

	/** If true, begin play will open the main menu UI instead of entering direct gameplay input mode */
	UPROPERTY(EditAnywhere, Config, Category = "UI")
	bool bShowMainMenuOnBeginPlay = false;

	/** Gameplay initialization */
	virtual void BeginPlay() override;
	virtual void OnPossess(APawn* InPawn) override;

	/** Input mapping context setup */
	virtual void SetupInputComponent() override;
	virtual void PlayerTick(float DeltaTime) override;

	void HandleDPadUp();
	void HandleDPadDown();
	void HandleDPadLeft();
	void HandleDPadRight();
	void HandleElementReleased();
	void HandleTimePressed();
	void HandleTimeReleased();
	void ToggleSlowTime();
	bool EquipCosmicPower(const FString& Payload);
	bool IsSlowTimeActive() const { return bTimeHeld || bWheelSlowTime; }
	void SetWheelSlowTime(bool bEnabled);
	void ApplyCosmicTimeState();
	void ConsumeJumpPress();
	void HandleControllerActivateReleased();
	void HandleQuickWheelPressed();
	void HandleQuickWheelReleased();
	void HandleLeftTriggerPressed();
	void HandleLeftTriggerReleased();
	void HandleQuickWheelNext();
	void HandleQuickWheelPrevious();
	void HandleRightTriggerPressed();
	void HandleRightTriggerReleased();
	void HandleRightStickX(float Value);
	void HandleRightStickY(float Value);
	void HandleRightTrigger(float Value);
	void HandleLeftTrigger(float Value);
	UFUNCTION()
	void HandleWheelAssignmentChanged(const TArray<FFableQuickWheelPageData>& Pages);
	UFUNCTION()
	void HandleWheelAssignmentClosed();
	bool RefreshQuickWheelPagesFromSave();
	void SetWheelInputCapture(bool bCapture);
	void UpdateCosmicEnergy(double WallNowSeconds);
	void DeactivateCosmicTime();
	bool BuildCosmicWheelPages();
	void OpenCosmicWheel();
	void CloseCosmicWheel(bool bActivateSelected);
	void ActivateCosmicWheelSelection();
	void BeginPrecisionTarget(float Range, float Radius);
	void UpdatePrecisionTarget(float RealDeltaSeconds);
	void EndPrecisionTarget();
	void UpdateElementGesture(float RealDeltaSeconds);
	void BeginElementGesture(FName Element);
	void PerformWeaponAttack(bool bOffHand);
	FVector ResolveAimPoint(FHitResult* OutHit = nullptr) const;

private:
	void ApplyActiveCharacterMesh();
	void EnsureUiWidgets();
	void RefreshHudData();
	void HandlePrimaryInteractClick();
	void HandleFocusedInteract();
	bool TraceFocusedInteractable(FHitResult& OutHit) const;
	void BeginInteractionFromHit(const FHitResult& HitResult);
	void CloseActivePanel();
	void UpdateHoveredInteractable();
	bool IsActorInteractable(const AActor* Actor) const;
	bool IsActorWithinSelectionDistance(const AActor* Actor) const;
	bool TryInteractWithActor(AActor* Actor);
	bool IsGameInteractionBlocked() const;
	void ClearHoveredInteractable();
	void ClearPendingInteraction();
	void ResetGameplayInputForChest();
	bool IsJournalOpen() const;
	bool IsControllerUiInputHandledByFocusedWidget() const;
	bool IsWheelAssignmentOpen() const;
	void HandleControllerActivate();

	/** Returns true if the player should use UMG touch controls */
	bool ShouldUseTouchControls() const;

private:
	UPROPERTY(Transient)
	TObjectPtr<UFableMainMenuWidget> MainMenuWidget;

	UPROPERTY(Transient)
	TObjectPtr<UFablePartyHudWidget> PartyHudWidget;

	UPROPERTY(Transient)
	TObjectPtr<UFableCharacterMenuWidget> CharacterMenuWidget;

	UPROPERTY(EditAnywhere, Category = "Interaction", meta = (ClampMin = "25.0", UIMin = "25.0", Units = "cm"))
	float InteractionDistancePadding = 35.0f;

	// Hard cap for hover/click selection so distant objects cannot be selected from across the map.
	UPROPERTY(EditAnywhere, Category = "Interaction", meta = (ClampMin = "100.0", UIMin = "100.0", Units = "cm"))
	float MaxInteractableSelectionDistance = 1500.0f;

	UPROPERTY(EditAnywhere, Category = "Interaction")
	TSubclassOf<UFableChestWidget> ChestWidgetClass;

	UPROPERTY(Transient)
	TObjectPtr<UFableChestWidget> ChestWidget;

	UPROPERTY(Transient)
	TObjectPtr<AActor> HoveredInteractableActor;

	UPROPERTY(Transient)
	TObjectPtr<AActor> PendingInteractionActor;

	UPROPERTY(Transient)
	FVector PendingInteractionApproachLocation = FVector::ZeroVector;

	UPROPERTY(Transient)
	bool bHasPendingInteractionApproachLocation = false;

	UPROPERTY(EditAnywhere, Category = "Gameplay|Time")
	float SlowTimeDilation = 0.12f;
	UPROPERTY(EditAnywhere, Category = "Gameplay|Time")
	float GestureSampleInterval = 0.04f;
	UPROPERTY(EditAnywhere, Category = "Gameplay|Cosmic")
	float MaxCosmicEnergy = 100.0f;
	UPROPERTY(EditAnywhere, Category = "Gameplay|Cosmic")
	float CosmicDrainPerSecond = 10.0f;
	UPROPERTY(EditAnywhere, Category = "Gameplay|Cosmic")
	float CosmicRecoveryPerSecond = 5.0f;

	UPROPERTY(Transient)
	TObjectPtr<UFableTimeWheelWidget> TimeWheelWidget;
	UPROPERTY(Transient)
	TObjectPtr<UFableWheelAssignmentWidget> WheelAssignmentWidget;
	TArray<FFableQuickWheelPageData> QuickWheelPages;
	TArray<FFableQuickWheelPageData> CosmicWheelPages;
	int32 CosmicWheelPage = 0;
	float CosmicEnergy = 100.0f;
	double LastCosmicWallTimeSeconds = 0.0;
	FVector2D RightStickValue = FVector2D::ZeroVector;
	FVector2D GestureStart = FVector2D::ZeroVector;
	float GestureTravel = 0.0f;
	float GestureTurn = 0.0f;
	float LastGestureAngle = 0.0f;
	bool bGestureHasStroke = false;
	bool bGestureNeedsNeutral = false;
	// Slow time is toggled by L3, independently of the physical L1 wheel button.
	bool bTimeHeld = false;
	// Temporary wheel slow time survives release into precision targeting, but
	// never changes the player's independent L3 toggle.
	bool bWheelSlowTime = false;
	bool bJumpPressConsumed = false;
	uint64 JumpConsumedFrame = MAX_uint64;
	bool bTimeButtonDown = false;
	bool bCosmicInputCancelled = false;
	bool bCosmicWheelOpen = false;
	bool bCosmicSelectionActivated = false;
	bool bTimeStopped = false;
	bool bQuickWheelHeld = false;
	bool bElementHeld = false;
	FName ActiveElement = TEXT("None");
	int32 QuickWheelPage = 0;
	float LastGestureSampleTime = -100.0f;
	bool bTargetingSkill = false;
	bool bTargetOwnsPause = false;
	bool bTargetPreviousCameraMoveable = false;
	bool bTargetValid = false;
	bool bPendingWeaponAttack = false;
	bool bPendingOffHand = false;
	bool bTargetRequiresGround = false;
	FVector2D TargetCursorPixels = FVector2D::ZeroVector;
	float TargetRange = 1200.f;
	float TargetRadius = 60.f;
	TWeakObjectPtr<UPrimitiveComponent> TargetHighlightComponent;
	bool bTargetPreviousCustomDepth = false;
	FString PendingSkillId;
	FVector PendingTargetLocation = FVector::ZeroVector;
	TWeakObjectPtr<AActor> PendingTargetActor;
	bool bRightTriggerLatched = false;
	bool bLeftTriggerLatched = false;
	bool bWheelInputCaptured = false;
	bool bWheelAssignmentEmbedded = false;
};
