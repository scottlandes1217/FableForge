#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "RPG/Data/FableForgeRPGTypes.h"
#include "FableTimeWheelWidget.generated.h"

class UCanvasPanel;
class UBorder;
class UImage;
class UTextBlock;

UCLASS()
class UFableTimeWheelWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	virtual TSharedRef<SWidget> RebuildWidget() override;
	virtual void NativeConstruct() override;
	virtual void NativeTick(const FGeometry& MyGeometry, float InDeltaTime) override;
	virtual int32 NativePaint(const FPaintArgs& Args, const FGeometry& AllottedGeometry, const FSlateRect& MyCullingRect, FSlateWindowElementList& OutDrawElements, int32 LayerId, const FWidgetStyle& InWidgetStyle, bool bParentEnabled) const override;

	void Open(const TArray<FFableQuickWheelPageData>& InPages);
	void Close();
	void SetPage(int32 InPageIndex);
	void SetElement(FName InElement);
	void SetCosmicWheel(bool bInCosmic);
	void SetGesture(FString InGesture);
	void SetTimeState(bool bInSlow, bool bInStopped);
	void BeginTargeting(const FString& SkillLabel, const FVector& InLocation);
	void SetTargetLocation(const FVector& InLocation);
	void SetTargetPreview(FVector2D CursorPixels, FVector Location, FVector Normal, float Radius, bool bValid, bool bHit);
	void EndTargeting();
	bool IsTargeting() const { return bTargeting; }
	void SetSelectionFromStick(const FVector2D& Stick);
	void SetSelectedSlot(int32 InSlot);
	static FVector2D GetSocketPosition(int32 InSlot);
	FString GetSelectedPayload() const;
	int32 GetSelectedSlot() const { return SelectedSlot; }
	bool IsOpen() const { return bOpen; }

private:
	void RebuildWheel();
	void UpdateWheelInventoryQuantities();
	void UpdateWheelSelectionVisuals();
	void AddLabel(const FString& Text, const FVector2D& Position, const FVector2D& Size, const FLinearColor& Color, int32 FontSize = 18, bool bBold = true);
	void AddWheelTile(const FString& Label, const FVector2D& Position, bool bSelected);

	UPROPERTY(Transient) TObjectPtr<UCanvasPanel> RootCanvas;
	UPROPERTY(Transient) TObjectPtr<UTextBlock> HeaderText;
	UPROPERTY(Transient) TObjectPtr<UTextBlock> FooterText;
	UPROPERTY(Transient) TObjectPtr<UTextBlock> SelectedEntryNameText;
	UPROPERTY(Transient) TObjectPtr<UCanvasPanel> NeedleLayer;
	UPROPERTY(Transient) TArray<TObjectPtr<UBorder>> WheelTiles;
	UPROPERTY(Transient) TArray<TObjectPtr<UBorder>> TargetCursorLines;
	UPROPERTY(Transient) TArray<TObjectPtr<UImage>> WheelTileIcons;
	UPROPERTY(Transient) TArray<TObjectPtr<UBorder>> WheelTileQuantityBadges;
	UPROPERTY(Transient) TArray<TObjectPtr<UTextBlock>> WheelTileQuantityLabels;
	TArray<FFableQuickWheelPageData> Pages;
	int32 PageIndex = 0;
	int32 SelectedSlot = INDEX_NONE;
	FName Element = TEXT("None");
	FString Gesture = TEXT("Ready");
	bool bOpen = false;
	bool bCosmicWheel = false;
	bool bSlow = false;
	bool bStopped = false;
	bool bTargeting = false;
	FString TargetSkill;
	FVector TargetLocation = FVector::ZeroVector;
	FVector2D TargetCursorPixels = FVector2D::ZeroVector;
	FVector TargetNormal = FVector::UpVector;
	float TargetRadius = 60.f;
	bool bTargetValid = false;
	bool bTargetHit = false;
	float InventoryRefreshAccumulator = 0.0f;
	FVector2D RightStickDirection = FVector2D(0.0f, -1.0f);
};
