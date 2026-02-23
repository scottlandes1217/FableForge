#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "FableChestWidget.generated.h"

class AFFChestInteractable;
class AFableForgePlayerController;
class UTextBlock;
class UVerticalBox;

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

	UFUNCTION()
	void HandleTakeAction(FName ActionId);

	UFUNCTION()
	void HandleTakeAllAction(FName ActionId);

	UFUNCTION()
	void HandleCloseAction(FName ActionId);

private:
	UPROPERTY(Transient)
	TObjectPtr<UVerticalBox> RootContent;

	UPROPERTY(Transient)
	TObjectPtr<UVerticalBox> ItemListBox;

	UPROPERTY(Transient)
	TObjectPtr<UTextBlock> HeaderText;

	UPROPERTY(Transient)
	TObjectPtr<AFFChestInteractable> ActiveChest;

	UPROPERTY(Transient)
	TObjectPtr<AFableForgePlayerController> CachedController;
};
