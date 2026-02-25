#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "FableChestWidget.generated.h"

class AFFChestInteractable;
class AFableForgePlayerController;
class UCanvasPanel;
class UCanvasPanelSlot;
class UImage;
class UTextBlock;
class UTexture2D;
class UVerticalBox;
class UWrapBox;

USTRUCT()
struct FFableChestUiItemDefinition
{
	GENERATED_BODY()

	UPROPERTY()
	FString DisplayName;

	UPROPERTY()
	FString IconAssetPath;
};

UCLASS()
class UFableChestWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	virtual TSharedRef<SWidget> RebuildWidget() override;

	void OpenForChest(AFFChestInteractable* InChest, AFableForgePlayerController* InOwningController);
	void CloseChest();
	bool IsChestOpen() const;

private:
	void RebuildContent();
	void RefreshItemRows();
	void EnsureItemDefinitionsLoaded();
	FString GetDisplayNameForItem(const FString& ItemId) const;
	UTexture2D* GetIconForItem(const FString& ItemId);

	UFUNCTION()
	void HandleTakeAction(FName ActionId);

	UFUNCTION()
	void HandleTakeAllAction(FName ActionId);

	UFUNCTION()
	void HandleCloseAction(FName ActionId);

private:
	UPROPERTY(Transient)
	TObjectPtr<UCanvasPanel> RootCanvas;

	UPROPERTY(Transient)
	TObjectPtr<UCanvasPanelSlot> PanelCanvasSlot;

	UPROPERTY(Transient)
	TObjectPtr<UVerticalBox> RootContent;

	UPROPERTY(Transient)
	TObjectPtr<UWrapBox> ItemGrid;

	UPROPERTY(Transient)
	TObjectPtr<UTextBlock> HeaderText;

	UPROPERTY(Transient)
	TObjectPtr<AFFChestInteractable> ActiveChest;

	UPROPERTY(Transient)
	TObjectPtr<AFableForgePlayerController> CachedController;

	UPROPERTY(Transient)
	TMap<FString, FFableChestUiItemDefinition> ItemDefinitions;

	UPROPERTY(Transient)
	TMap<FString, TObjectPtr<UTexture2D>> IconTextureCache;

	bool bItemDefinitionsLoaded = false;
};
