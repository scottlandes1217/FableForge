// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "FableForgePlayerController.generated.h"

class UFableCharacterMenuWidget;
class UFableChestWidget;
class UFableMainMenuWidget;
class UFablePartyHudWidget;
class UInputMappingContext;
class UUserWidget;
class AFFChestInteractable;

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

	UFUNCTION(BlueprintCallable, Category = "UI")
	void ToggleCharacterMenu();

	UFUNCTION(BlueprintCallable, Category = "UI")
	void OpenChest(AFFChestInteractable* Chest);

	UFUNCTION(BlueprintCallable, Category = "UI")
	void CloseChest();

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

private:
	void ApplyActiveCharacterMesh();
	void EnsureUiWidgets();
	void RefreshHudData();
	void HandlePrimaryInteractClick();
	void UpdateHoveredInteractable();
	bool IsActorInteractable(const AActor* Actor) const;
	bool IsActorWithinSelectionDistance(const AActor* Actor) const;
	bool TryInteractWithActor(AActor* Actor);
	bool IsGameInteractionBlocked() const;
	void ClearHoveredInteractable();
	void ClearPendingInteraction();

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
};
