#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "RPG/Data/FableForgeRPGTypes.h"
#include "RPG/Data/FableSkillSystemTableRows.h"
#include "FablePartyHudWidget.generated.h"

class UBorder;
class UCanvasPanel;
class UImage;
class UProgressBar;
class UTextBlock;
class UTextureRenderTarget2D;
class UVerticalBox;
class UFableActionBarWidget;
class UFableCharacterMenuWidget;
class ASceneCapture2D;

UCLASS()
class UFablePartyHudWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	virtual TSharedRef<SWidget> RebuildWidget() override;
	virtual void NativeConstruct() override;
	virtual void NativeDestruct() override;
	virtual void NativeTick(const FGeometry& MyGeometry, float InDeltaTime) override;

	void RefreshFromSaveData();
	void SetCharacterMenuWidget(UFableCharacterMenuWidget* InCharacterMenuWidget);
	bool TryAssignActionAtScreenPosition(const FVector2D& ScreenPosition, FName FromSlotId, const FString& PayloadId, const FString& PayloadLabel);
	bool TryUseActionAtScreenPosition(const FVector2D& ScreenPosition);
	bool ClearActionAtSlotId(FName SlotId);

private:
	enum class EModalState : uint8
	{
		None,
		SettingsRoot,
		SaveSlots,
		LoadCharacters,
		LoadSlots,
		ConfirmDeleteActionBar
	};

	void Rebuild();
	void RebuildPartyMembers(const FFableCharacterProfile& ActiveProfile);
	void RebuildActionBars();
	void RebuildModal();
	void AddModalButton(UVerticalBox* Parent, const FString& Label, FName Action, bool bEnabled = true);
	FString BuildSlotLabel(const FFableSaveSlotMeta& SlotMeta) const;
	bool IsValidActionPayload(const FString& PayloadId) const;
	bool ResolveActionSlotAddress(FName SlotId, FGuid& OutBarId, int32& OutSlotIndex) const;
	FString BuildActionToken(const FString& PayloadId) const;
	void SaveActionBars();
	void AddAdditionalActionBar(EFableActionBarOrientation Orientation);
	void LoadSkillDefinitionsFromDataTable();
	const FFableSkillDefinitionTableRow* FindSkillDefinition(const FString& SkillId) const;
	void UpdateActionBarCooldownVisuals();
	UFableActionBarWidget* FindActionBarWidgetById(const FGuid& BarId) const;

	FName MakeActionName(const FString& Prefix);
	FName RegisterCharacterAction(const FGuid& CharacterId);
	FName RegisterSlotAction(int32 SlotIndex);

	UFUNCTION()
	void HandleActionClicked(FName ActionId);

	UFUNCTION()
	void HandleActionBarMoved(FGuid BarId, FVector2D NewScreenPosition);

	UFUNCTION()
	void HandleActionBarExpandToggled(FGuid BarId);

	UFUNCTION()
	void HandleActionBarSlotDrop(FGuid BarId, int32 ToSlotIndex, FName FromSlotId, const FString& PayloadId, const FString& PayloadLabel);

	UFUNCTION()
	void HandleActionBarSlotClicked(FGuid BarId, int32 SlotIndex, const FString& PayloadId);

	UFUNCTION()
	void HandleActionBarRemoveRequested(FGuid BarId);

	void EnsurePlayerPortraitCapture();
	void UpdatePlayerPortraitCapture();

private:
	EModalState ModalState = EModalState::None;
	FGuid PendingLoadCharacterId;
	int32 ActionCounter = 0;

	TMap<FName, FGuid> CharacterActionMap;
	TMap<FName, int32> SlotActionMap;
	FGuid PendingDeleteActionBarId;

	UPROPERTY(Transient)
	TObjectPtr<UTextBlock> PlayerNameText;

	UPROPERTY(Transient)
	TObjectPtr<UImage> PlayerPortraitImage;

	UPROPERTY(Transient)
	TObjectPtr<UTextBlock> PlayerPortraitFallbackText;

	UPROPERTY(Transient)
	TObjectPtr<UVerticalBox> PartyMembersBox;

	UPROPERTY(Transient)
	TObjectPtr<UCanvasPanel> ActionBarsCanvas;

	UPROPERTY(Transient)
	TObjectPtr<UProgressBar> PlayerHealthBar;

	UPROPERTY(Transient)
	TObjectPtr<UProgressBar> PlayerManaBar;

	UPROPERTY(Transient)
	TObjectPtr<UProgressBar> PlayerExperienceBar;

	UPROPERTY(Transient)
	TObjectPtr<UBorder> ModalBackdrop;

	UPROPERTY(Transient)
	TObjectPtr<UBorder> ModalPanel;

	UPROPERTY(Transient)
	TObjectPtr<UFableCharacterMenuWidget> CharacterMenuWidget;

	UPROPERTY(Transient)
	TObjectPtr<UTextureRenderTarget2D> PlayerPortraitRenderTarget;

	UPROPERTY(Transient)
	TObjectPtr<ASceneCapture2D> PlayerPortraitCaptureActor;

	TArray<FFableActionBarData> ActionBars;
	TMap<FString, FString> ItemTypeLookup;
	TMap<FString, FFableSkillDefinitionTableRow> SkillDefinitions;
	TMap<FString, float> ActionCooldownsByPayload;
	bool bSkillDefinitionsLoaded = false;
};
