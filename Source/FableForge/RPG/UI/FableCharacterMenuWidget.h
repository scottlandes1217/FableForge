#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "RPG/Data/FableSkillSystemTableRows.h"
#include "FableCharacterMenuWidget.generated.h"

class UVerticalBox;
class UFableActionButton;
class UFableInventorySlotWidget;
class UTexture2D;

struct FFableUiItemDefinition
{
	FString Id;
	FString Name;
	FName Category;
	bool bStackable = false;
	bool bEquipable = false;
	int32 EquipmentSlot = INDEX_NONE;
	FString IconToken;
	FString IconAssetPath;
	FString ModelPath;
	FString ModelPathMale;
	FString ModelPathFemale;
};

UCLASS()
class UFableCharacterMenuWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	virtual TSharedRef<SWidget> RebuildWidget() override;
	virtual void NativeConstruct() override;

	void Open();
	void Close();
	void Toggle();
	bool IsOpen() const;

private:
	void Rebuild();
	void RebuildTabContent();
	void BuildInventoryTab();
	void BuildSimpleInfoTab(const FString& Header, const FString& Body);
	void LoadInventoryFromSave();
	void LoadSkillDefinitionsFromDataTable();
	void SaveInventoryToSaveSubsystem() const;
	void LoadItemDefinitionsFromUnityJson();
	void RefreshInventorySlotWidgets();
	bool ResolveSlotAddress(FName SlotId, bool& bOutEquipmentSlot, int32& OutSlotIndex) const;
	bool IsItemAllowedInEquipmentSlot(const FString& ItemId, int32 EquipmentSlotIndex) const;
	FString GetItemLabelForSlot(const FString& ItemId, bool bEquipmentSlot) const;
	UTexture2D* GetItemIconForSlot(const FString& ItemId);
	FName ResolveItemCategory(const FString& ItemId) const;
	void BuildSkillsTab();
	const FFableSkillDefinitionTableRow* FindSkillDefinition(const FString& SkillId) const;
	void RefreshMainTabButtonStyles();
	void QueueTabContentRebuild();
	void PerformQueuedTabContentRebuild();

	UFUNCTION()
	void HandleInventorySlotDropped(FName FromSlotId, FName ToSlotId, const FString& PayloadId, const FString& PayloadLabel);

	UFUNCTION()
	void HandleActionClicked(FName ActionId);

	UFUNCTION()
	void HandleSkillSlotHovered(FName SlotId, const FString& PayloadId);

	UFUNCTION()
	void HandleSkillSlotClicked(FName SlotId, const FString& PayloadId);

private:
	FName ActiveTab = TEXT("inventory");
	FName ActiveInventoryCategory = TEXT("cat_all");
	FName ActiveSkillCategory = TEXT("skillcat_all");
	bool bInventoryLoaded = false;
	bool bItemDefinitionsLoaded = false;
	bool bSkillDefinitionsLoaded = false;
	bool bTabContentRebuildQueued = false;
	TArray<FString> InventorySlots;
	TArray<FString> EquippedSlots;
	FString ActiveSkillDetailsId;
	TMap<FName, TObjectPtr<UFableInventorySlotWidget>> SlotWidgets;
	TMap<FString, FFableUiItemDefinition> ItemDefinitions;
	TMap<FString, TObjectPtr<UTexture2D>> IconTextureCache;
	TMap<FString, FFableSkillDefinitionTableRow> SkillDefinitions;
	TMap<FName, TObjectPtr<UFableActionButton>> MainTabButtons;
	TMap<FName, FString> SkillRowActions;

	UPROPERTY(Transient)
	TObjectPtr<UVerticalBox> ContentRoot;
};
