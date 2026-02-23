#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "RPG/Data/FableForgeRPGTypes.h"
#include "FablePartyHudWidget.generated.h"

class UBorder;
class UCanvasPanel;
class UProgressBar;
class UTextBlock;
class UVerticalBox;
class UFableActionBarWidget;
class UFableCharacterMenuWidget;

UCLASS()
class UFablePartyHudWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	virtual TSharedRef<SWidget> RebuildWidget() override;
	virtual void NativeConstruct() override;

	void RefreshFromSaveData();
	void SetCharacterMenuWidget(UFableCharacterMenuWidget* InCharacterMenuWidget);

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
	void HandleActionBarRemoveRequested(FGuid BarId);

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

	TArray<FFableActionBarData> ActionBars;
	TMap<FString, FString> ItemTypeLookup;
};
