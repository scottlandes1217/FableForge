#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "RPG/Data/FableForgeRPGTypes.h"
#include "FableTimeWheelWidget.generated.h"

class UCanvasPanel;
class UBorder;
class UTextBlock;

UCLASS()
class UFableTimeWheelWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	virtual TSharedRef<SWidget> RebuildWidget() override;
	virtual void NativeConstruct() override;

	void Open(const TArray<FFableQuickWheelPageData>& InPages);
	void Close();
	void SetPage(int32 InPageIndex);
	void SetElement(FName InElement);
	void SetGesture(FString InGesture);
	void SetTimeState(bool bInSlow, bool bInStopped);
	void BeginTargeting(const FString& SkillLabel, const FVector& InLocation);
	void SetTargetLocation(const FVector& InLocation);
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
	void AddLabel(const FString& Text, const FVector2D& Position, const FVector2D& Size, const FLinearColor& Color, int32 FontSize = 18, bool bBold = true);
	void AddWheelTile(const FString& Label, const FVector2D& Position, bool bSelected);

	UPROPERTY(Transient) TObjectPtr<UCanvasPanel> RootCanvas;
	UPROPERTY(Transient) TObjectPtr<UTextBlock> HeaderText;
	UPROPERTY(Transient) TObjectPtr<UTextBlock> FooterText;
	TArray<FFableQuickWheelPageData> Pages;
	int32 PageIndex = 0;
	int32 SelectedSlot = 0;
	FName Element = TEXT("None");
	FString Gesture = TEXT("Ready");
	bool bOpen = false;
	bool bSlow = false;
	bool bStopped = false;
	bool bTargeting = false;
	FString TargetSkill;
	FVector TargetLocation = FVector::ZeroVector;
	FVector2D RightStickDirection = FVector2D(0.0f, -1.0f);
};
