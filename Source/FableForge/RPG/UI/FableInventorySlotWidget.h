#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "FableInventorySlotWidget.generated.h"

class UBorder;
class UTextBlock;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_FourParams(FFableInventorySlotDropSignature, FName, FromSlotId, FName, ToSlotId, const FString&, PayloadId, const FString&, PayloadLabel);

UCLASS()
class UFableInventorySlotWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	virtual TSharedRef<SWidget> RebuildWidget() override;
	virtual FReply NativeOnMouseButtonDown(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent) override;
	virtual void NativeOnDragDetected(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent, UDragDropOperation*& OutOperation) override;
	virtual bool NativeOnDrop(const FGeometry& InGeometry, const FDragDropEvent& InDragDropEvent, UDragDropOperation* InOperation) override;

	void InitializeSlot(FName InSlotId, const FString& InDisplayName, bool bInEquipmentSlot);
	void SetItemLabel(const FString& InItemLabel);
	void SetItemData(const FString& InPayloadId, const FString& InItemLabel);
	FName GetSlotId() const;

	UPROPERTY(BlueprintAssignable, Category = "Inventory")
	FFableInventorySlotDropSignature OnItemDrop;

private:
	void RefreshVisual();

private:
	UPROPERTY(Transient)
	TObjectPtr<UBorder> RootBorder;

	UPROPERTY(Transient)
	TObjectPtr<UBorder> InnerBorder;

	UPROPERTY(Transient)
	TObjectPtr<UTextBlock> LabelText;

	FName SlotId;
	FString EmptyDisplayName;
	FString ItemLabel;
	FString ItemPayloadId;
	bool bEquipmentSlot = false;
};
