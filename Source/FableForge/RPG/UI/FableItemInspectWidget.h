#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "FableItemInspectWidget.generated.h"

class UButton;
class UCanvasPanel;
class UImage;
class UScrollBox;
class UTexture2D;

DECLARE_DYNAMIC_MULTICAST_DELEGATE(FFableItemInspectClosedSignature);

/** Controller-friendly, centered item details modal for the inventory. */
UCLASS()
class UFableItemInspectWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	virtual TSharedRef<SWidget> RebuildWidget() override;
	virtual void NativeConstruct() override;
	virtual FReply NativeOnPreviewKeyDown(const FGeometry& InGeometry, const FKeyEvent& InKeyEvent) override;
	virtual FReply NativeOnAnalogValueChanged(const FGeometry& InGeometry, const FAnalogInputEvent& InAnalogInputEvent) override;
	virtual void NativeTick(const FGeometry& InGeometry, float InDeltaTime) override;

	void Open(const FString& InTitle, const TArray<TPair<FString, FString>>& InDetails, UTexture2D* InIcon);
	void Close();
	bool IsOpen() const { return bOpen; }

	UPROPERTY(BlueprintAssignable, Category = "Item Inspection")
	FFableItemInspectClosedSignature OnClosed;

private:
	void RebuildContent();
	void ScrollBy(float Amount);

	UFUNCTION()
	void HandleCloseClicked();

	UPROPERTY(Transient)
	TObjectPtr<UCanvasPanel> RootCanvas;

	UPROPERTY(Transient)
	TObjectPtr<UScrollBox> DetailsScroll;

	UPROPERTY(Transient)
	TObjectPtr<UButton> CloseButton;

	UPROPERTY(Transient)
	TObjectPtr<UImage> IconImage;

	FString Title;
	TArray<TPair<FString, FString>> Details;

	UPROPERTY(Transient)
	TObjectPtr<UTexture2D> Icon;

	bool bOpen = false;
	float RightStickY = 0.f;
	float AnalogScrollCooldown = 0.f;
};
