#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "Input/Events.h"
#include "FableChestWidget.generated.h"

class AFFChestInteractable;
class AFableForgePlayerController;
class UCanvasPanel;
class UCanvasPanelSlot;
class UBorder;
class UFableActionButton;
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
	virtual FReply NativeOnPreviewKeyDown(const FGeometry& Geometry, const FKeyEvent& Event) override;
	virtual FReply NativeOnAnalogValueChanged(const FGeometry& Geometry, const FAnalogInputEvent& Event) override;

	void OpenForChest(AFFChestInteractable* InChest, AFableForgePlayerController* InOwningController);
	void CloseChest();
	bool IsChestOpen() const;
	/** Executes Take All for the active chest. The owning controller can call this
	 * when its focused-widget routing does not deliver the Triangle input here. */
	void TakeAllItems();
	void MoveControllerSelection(int32 Direction);
	void ActivateControllerSelection();
	void FocusControllerSelection();

private:
	void RebuildContent();
	void RefreshItemRows();
	void EnsureItemDefinitionsLoaded();
	FString GetDisplayNameForItem(const FString& ItemId) const;
	UTexture2D* GetIconForItem(const FString& ItemId);
	void ResetControllerSelection();
	void RefreshControllerSelectionVisual();

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
	TObjectPtr<AFFChestInteractable> ActiveChest;

	UPROPERTY(Transient)
	TObjectPtr<AFableForgePlayerController> CachedController;

	UPROPERTY(Transient)
	TMap<FString, FFableChestUiItemDefinition> ItemDefinitions;

	UPROPERTY(Transient)
	TMap<FString, TObjectPtr<UTexture2D>> IconTextureCache;

	UPROPERTY(Transient)
	TArray<TObjectPtr<UFableActionButton>> ControllerItemButtons;

	UPROPERTY(Transient)
	TArray<TObjectPtr<UBorder>> ControllerItemSelectionIndicators;

	int32 ControllerSelectionIndex = 0;

	bool bItemDefinitionsLoaded = false;
};
