#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "RPG/Data/FableForgeRPGTypes.h"
#include "FableMainMenuWidget.generated.h"

class UEditableTextBox;
class USkeletalMeshComponent;
class UPointLightComponent;
class UVerticalBox;
class UViewport;
class UFableActionButton;

UCLASS()
class UFableMainMenuWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	UFableMainMenuWidget(const FObjectInitializer& ObjectInitializer);

	virtual TSharedRef<SWidget> RebuildWidget() override;
	virtual void NativeConstruct() override;
	virtual void NativeDestruct() override;

	void OpenMainMenu();

private:
	enum class EMainMenuState : uint8
	{
		Main,
		CharacterSelect,
		SlotSelect,
		RaceSelect,
		Customization
	};

	void Rebuild();
	void BuildMainState();
	void BuildCharacterSelectState();
	void BuildSlotSelectState();
	void BuildRaceSelectState();
	void BuildCustomizationState();

	void CreateHeader(UVerticalBox* Parent, const FString& Text, int32 FontSize = 34) const;
	void CreateSubheader(UVerticalBox* Parent, const FString& Text) const;
	void AddSpacer(UVerticalBox* Parent, float Height) const;

	UFableActionButton* CreateActionButton(UVerticalBox* Parent, const FString& Label, FName ActionId, bool bEnabled = true, float Height = 46.0f);

	FName RegisterCharacterAction(const FGuid& CharacterId);
	FName RegisterRaceAction(const FString& RaceId);
	FName RegisterSlotAction(int32 SlotIndex);
	FName MakeActionName(const FString& Prefix);

	void ApplyCharacterCreation();
	void UpdatePreviewMesh();
	bool EnsurePreviewActor();
	void ApplyRotationDelta(float DeltaYaw);
	void BeginRotateHold(float DeltaYaw);
	void EndRotateHold();

	UFUNCTION()
	void HandleRotateLeftPressed();

	UFUNCTION()
	void HandleRotateRightPressed();

	UFUNCTION()
	void HandleRotateReleased();

	UFUNCTION()
	void TickRotateHold();

	FString BuildSlotLabel(const FFableSaveSlotMeta& SlotMeta) const;

	UFUNCTION()
	void HandleActionClicked(FName ActionId);

private:
	EMainMenuState CurrentState = EMainMenuState::Main;
	bool bIsSlotLoadMode = true;

	FGuid PendingCharacterId;
	FString PendingRaceId = TEXT("human");
	EFableGender PendingGender = EFableGender::Male;

	int32 ActionCounter = 0;
	TMap<FName, FGuid> CharacterActionMap;
	TMap<FName, FString> RaceActionMap;
	TMap<FName, int32> SlotActionMap;

	UPROPERTY(Transient)
	TObjectPtr<UEditableTextBox> CharacterNameTextBox;

	UPROPERTY(Transient)
	TObjectPtr<UViewport> PreviewViewport;

	UPROPERTY(Transient)
	TObjectPtr<AActor> PreviewActor;

	UPROPERTY(Transient)
	TObjectPtr<USkeletalMeshComponent> PreviewMeshComponent;

	UPROPERTY(Transient)
	TObjectPtr<UPointLightComponent> PreviewKeyLightComponent;

	float PreviewYawDegrees = -90.0f;
	float PreviewHoldDeltaYaw = 0.0f;
	FTimerHandle PreviewRotateTimerHandle;
};
