#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "FableInventorySlotWidget.generated.h"

class UBorder;
class UImage;
class UObject;
class UOverlay;
class UTextBlock;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_FourParams(FFableInventorySlotDropSignature, FName, FromSlotId, FName, ToSlotId, const FString&, PayloadId, const FString&, PayloadLabel);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FFableInventorySlotHoverSignature, FName, SlotId, const FString&, PayloadId);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FFableInventorySlotClickSignature, FName, SlotId, const FString&, PayloadId);

UCLASS()
class UFableInventorySlotWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	virtual TSharedRef<SWidget> RebuildWidget() override;
	virtual FReply NativeOnMouseButtonDown(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent) override;
	virtual FReply NativeOnMouseButtonUp(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent) override;
	virtual void NativeOnMouseEnter(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent) override;
	virtual void NativeOnDragEnter(const FGeometry& InGeometry, const FDragDropEvent& InDragDropEvent, UDragDropOperation* InOperation) override;
	virtual bool NativeOnDragOver(const FGeometry& InGeometry, const FDragDropEvent& InDragDropEvent, UDragDropOperation* InOperation) override;
	virtual void NativeOnDragDetected(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent, UDragDropOperation*& OutOperation) override;
	virtual void NativeOnDragCancelled(const FDragDropEvent& InDragDropEvent, UDragDropOperation* InOperation) override;
	virtual bool NativeOnDrop(const FGeometry& InGeometry, const FDragDropEvent& InDragDropEvent, UDragDropOperation* InOperation) override;

	void InitializeSlot(FName InSlotId, const FString& InDisplayName, bool bInEquipmentSlot);
	void SetItemLabel(const FString& InItemLabel);
	void SetItemData(const FString& InPayloadId, const FString& InItemLabel, UObject* InIconResource = nullptr);
	FName GetSlotId() const;

	UPROPERTY(BlueprintAssignable, Category = "Inventory")
	FFableInventorySlotDropSignature OnItemDrop;

	UPROPERTY(BlueprintAssignable, Category = "Inventory")
	FFableInventorySlotHoverSignature OnSlotHovered;

	UPROPERTY(BlueprintAssignable, Category = "Inventory")
	FFableInventorySlotClickSignature OnSlotClicked;

private:
	void RefreshVisual();

private:
	UPROPERTY(Transient)
	TObjectPtr<UBorder> RootBorder;

	UPROPERTY(Transient)
	TObjectPtr<UBorder> InnerBorder;

	UPROPERTY(Transient)
	TObjectPtr<UOverlay> ContentOverlay;

	UPROPERTY(Transient)
	TObjectPtr<UImage> IconImage;

	UPROPERTY(Transient)
	TObjectPtr<UTextBlock> LabelText;

	UPROPERTY(Transient)
	TObjectPtr<UObject> ItemIconResource;

	FName SlotId;
	FString EmptyDisplayName;
	FString ItemLabel;
	FString ItemPayloadId;
	bool bEquipmentSlot = false;
	bool bDragDetectedThisPress = false;
	bool bTemporarilyDragHidden = false;
};
