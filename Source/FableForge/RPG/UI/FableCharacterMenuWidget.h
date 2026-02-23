#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "FableCharacterMenuWidget.generated.h"

class UVerticalBox;
class UFableInventorySlotWidget;

struct FFableUiItemDefinition
{
	FString Id;
	FString Name;
	FName Category;
	bool bStackable = false;
	bool bEquipable = false;
	int32 EquipmentSlot = INDEX_NONE;
	FString IconToken;
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
	void SaveInventoryToSaveSubsystem() const;
	void LoadItemDefinitionsFromUnityJson();
	void RefreshInventorySlotWidgets();
	bool ResolveSlotAddress(FName SlotId, bool& bOutEquipmentSlot, int32& OutSlotIndex) const;
	bool IsItemAllowedInEquipmentSlot(const FString& ItemId, int32 EquipmentSlotIndex) const;
	FString GetItemLabelForSlot(const FString& ItemId, bool bEquipmentSlot) const;
	FName ResolveItemCategory(const FString& ItemId) const;
	void BuildSkillsTab();

	UFUNCTION()
	void HandleInventorySlotDropped(FName FromSlotId, FName ToSlotId, const FString& PayloadId, const FString& PayloadLabel);

	UFUNCTION()
	void HandleActionClicked(FName ActionId);

private:
	FName ActiveTab = TEXT("inventory");
	FName ActiveInventoryCategory = TEXT("cat_weapons");
	bool bInventoryLoaded = false;
	bool bItemDefinitionsLoaded = false;
	TArray<FString> InventorySlots;
	TArray<FString> EquippedSlots;
	TMap<FName, TObjectPtr<UFableInventorySlotWidget>> SlotWidgets;
	TMap<FString, FFableUiItemDefinition> ItemDefinitions;

	UPROPERTY(Transient)
	TObjectPtr<UVerticalBox> ContentRoot;
};
