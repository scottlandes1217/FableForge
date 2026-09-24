#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "RPG/Data/FableSkillSystemTableRows.h"
#include "RPG/Data/FableForgeRPGTypes.h"
#include "FableCharacterMenuWidget.generated.h"

class UVerticalBox;
class UFableActionButton;
class UFableInventorySlotWidget;
class UTexture2D;
class UBorder;
class USizeBox;
class UTextBlock;
class UFableWheelAssignmentWidget;

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
	virtual FReply NativeOnPreviewKeyDown(const FGeometry& Geometry, const FKeyEvent& Event) override;
	void CycleMainTab(int32 Direction);
	void CycleCategoryTab(int32 Direction);
	void HandleControllerCancel();
	void MoveControllerSelection(int32 X, int32 Y);
	void ActivateControllerSelection();

	void Open();
	void Close();
	void Toggle();
	void OpenSkillsForQa();
	bool IsOpen() const;
	bool ShowEmbeddedQuickWheel(UFableWheelAssignmentWidget* AssignmentWidget, const TArray<FFableQuickWheelPageData>& Pages, const TArray<FString>& Payloads, const TArray<FString>& Labels);
	void HideEmbeddedQuickWheel();

private:
	friend class FFableJournalStabilityTest;
	void Rebuild();
	void RebuildTabContent();
	void BuildInventoryTab();
	void BuildSimpleInfoTab(const FString& Header, const FString& Body);
	void LoadInventoryFromSave();
	void LoadSkillDefinitionsFromDataTable();
	void SaveInventoryToSaveSubsystem();
	void LoadItemDefinitionsFromUnityJson();
	void RefreshInventorySlotWidgets();
	void RefreshInventoryPresentation();
	void RefreshSkillsPresentation();
	void RefreshSkillDetails();
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
	void RefreshControllerSelection();

	UFUNCTION()
	void HandleInventorySlotDropped(FName FromSlotId, FName ToSlotId, const FString& PayloadId, const FString& PayloadLabel);

	UFUNCTION()
	void HandleActionClicked(FName ActionId);

	UFUNCTION()
	void HandleSkillSlotHovered(FName SlotId, const FString& PayloadId);

	UFUNCTION()
	void HandleSkillSlotClicked(FName SlotId, const FString& PayloadId);

	UFUNCTION()
	void HandleSkillSlotRightClicked(FName SlotId, const FString& PayloadId);


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
	FString ContextSkillId;
	bool bSkillContextVisible = false;
	FString InventorySaveWarning;
	FName ControllerSlotId;
	FName ControllerPickedSlot;
	bool bControllerSelectionVisible = false;
	TArray<int32> ControllerVisibleInventory;
	TArray<FName> OrderedSkillCategories;
	UPROPERTY(Transient)
	TObjectPtr<class UScrollBox> InventoryScroll;
	UPROPERTY(Transient)
	TObjectPtr<class UScrollBox> SkillsScroll;
	TMap<FName, TObjectPtr<UFableInventorySlotWidget>> SlotWidgets;
	TMap<FString, FFableUiItemDefinition> ItemDefinitions;
	TMap<FString, TObjectPtr<UTexture2D>> IconTextureCache;
	TMap<FString, FFableSkillDefinitionTableRow> SkillDefinitions;
	TMap<FName, TObjectPtr<UFableActionButton>> MainTabButtons;
	TMap<FName, FString> SkillRowActions;

	UPROPERTY(Transient)
	TMap<FName,TObjectPtr<UFableActionButton>> InventoryCategoryButtons;
	UPROPERTY(Transient)
	TMap<FName,TObjectPtr<UFableActionButton>> SkillCategoryButtons;
	UPROPERTY(Transient)
	TMap<int32,TObjectPtr<USizeBox>> InventoryCells;
	UPROPERTY(Transient)
	TMap<FString,TObjectPtr<UBorder>> SkillRows;
	TArray<FString> DisplayedSkillOrder;
	UPROPERTY(Transient)
	TObjectPtr<UTextBlock> InventoryHeading;
	UPROPERTY(Transient)
	TObjectPtr<UTextBlock> InventoryStatus;
	UPROPERTY(Transient)
	TObjectPtr<UVerticalBox> SkillDetailsContent;
	UPROPERTY(Transient)
	TMap<FString, TObjectPtr<UTexture2D>> EquipmentSlotTextures;
	UPROPERTY(Transient)
	TObjectPtr<UVerticalBox> ContentRoot;
	UPROPERTY(Transient)
	TObjectPtr<UFableWheelAssignmentWidget> EmbeddedQuickWheel;
};
