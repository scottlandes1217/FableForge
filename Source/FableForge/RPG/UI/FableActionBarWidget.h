#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "RPG/Data/FableForgeRPGTypes.h"
#include "FableActionBarWidget.generated.h"

class UCanvasPanelSlot;
class UFableInventorySlotWidget;
class UUniformGridPanel;
class UVerticalBox;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FFableActionBarMovedSignature, FGuid, BarId, FVector2D, NewScreenPosition);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FFableActionBarExpandToggledSignature, FGuid, BarId);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_FiveParams(FFableActionBarSlotDropSignature, FGuid, BarId, int32, ToSlotIndex, FName, FromSlotId, const FString&, PayloadId, const FString&, PayloadLabel);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FFableActionBarRemoveRequestedSignature, FGuid, BarId);

UCLASS()
class UFableActionBarWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	virtual TSharedRef<SWidget> RebuildWidget() override;
	virtual void NativeConstruct() override;
	virtual void NativeTick(const FGeometry& MyGeometry, float InDeltaTime) override;

	void InitializeBar(const FFableActionBarData& InBarData, const TArray<FFableActionSlotData>& InVisibleSlots, bool bInCanExpand, bool bInShowExpanded);
	FGuid GetBarId() const;

	UPROPERTY(BlueprintAssignable, Category = "ActionBar")
	FFableActionBarMovedSignature OnBarMoved;

	UPROPERTY(BlueprintAssignable, Category = "ActionBar")
	FFableActionBarExpandToggledSignature OnExpandToggled;

	UPROPERTY(BlueprintAssignable, Category = "ActionBar")
	FFableActionBarSlotDropSignature OnActionSlotDropped;

	UPROPERTY(BlueprintAssignable, Category = "ActionBar")
	FFableActionBarRemoveRequestedSignature OnRemoveRequested;

private:
	UFUNCTION()
	void HandleMovePressed();

	UFUNCTION()
	void HandleMoveReleased();

	UFUNCTION()
	void HandleExpandClicked(FName ActionId);

	UFUNCTION()
	void HandleRemoveClicked(FName ActionId);

	UFUNCTION()
	void HandleSlotDrop(FName FromSlotId, FName ToSlotId, const FString& PayloadId, const FString& PayloadLabel);

private:
	FFableActionBarData BarData;
	TArray<FFableActionSlotData> VisibleSlots;
	bool bCanExpand = false;
	bool bShowExpanded = false;
	bool bDragging = false;
	FVector2D DragOffset = FVector2D::ZeroVector;

	TMap<FName, int32> SlotAddressMap;
};
