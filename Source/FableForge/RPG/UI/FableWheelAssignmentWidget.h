#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "RPG/Data/FableForgeRPGTypes.h"
#include "FableWheelAssignmentWidget.generated.h"

class UButton;
class UCanvasPanel;
class UTextBlock;
class UVerticalBox;
class UFableTimeWheelWidget;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FFableWheelPagesChangedSignature, const TArray<FFableQuickWheelPageData>&, Pages);
DECLARE_DYNAMIC_MULTICAST_DELEGATE(FFableWheelAssignmentClosedSignature);

/** Full-screen, controller-friendly editor for assigning entries to one quick-wheel page. */
UCLASS()
class UFableWheelAssignmentWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	virtual TSharedRef<SWidget> RebuildWidget() override;
	virtual void NativeConstruct() override;
	virtual FReply NativeOnPreviewKeyDown(const FGeometry& InGeometry, const FKeyEvent& InKeyEvent) override;
	virtual FReply NativeOnKeyDown(const FGeometry& InGeometry, const FKeyEvent& InKeyEvent) override;
	virtual FReply NativeOnMouseMove(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent) override;
	virtual FReply NativeOnMouseButtonDown(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent) override;
	virtual FReply NativeOnAnalogValueChanged(const FGeometry& InGeometry, const FAnalogInputEvent& InAnalogInputEvent) override;

	void Open(const TArray<FFableQuickWheelPageData>& InPages, const TArray<FString>& InAvailablePayloads, const TArray<FString>& InLabels);
	void SetSelectedAvailablePayload(const FString& Payload);
	void SetEmbedded(bool bInEmbedded) { bEmbedded = bInEmbedded; }
	void Close();
	bool IsOpen() const { return bOpen; }
	const TArray<FFableQuickWheelPageData>& GetPages() const { return Pages; }
	void MoveSelection(int32 Delta);
	void ConfirmAssignment();
	void Cancel();

	UPROPERTY(BlueprintAssignable, Category = "Quick Wheel")
	FFableWheelPagesChangedSignature OnPagesChanged;

	UPROPERTY(BlueprintAssignable, Category = "Quick Wheel")
	FFableWheelAssignmentClosedSignature OnClosed;

private:
	void RebuildContent();
	void ChangePage(int32 Delta);
	void SyncWheelSelection();
	int32 FindSocketAtPointer(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent) const;

	UPROPERTY(Transient)
	TObjectPtr<UCanvasPanel> RootCanvas;

	UPROPERTY(Transient)
	TObjectPtr<UFableTimeWheelWidget> TimeWheelWidget;

	UPROPERTY(Transient)
	TObjectPtr<UTextBlock> SelectedPayloadText;

	UPROPERTY(Transient)
	TObjectPtr<UTextBlock> PageText;

	TArray<FFableQuickWheelPageData> Pages;
	TArray<FString> AvailablePayloads;
	TArray<FString> AvailableLabels;
	int32 PageIndex = 0;
	int32 SelectedSlot = 0;
	int32 SelectedAvailable = 0;
	bool bOpen = false;
	bool bEmbedded = false;
	bool bAvailablePayloadLocked = false;
	FVector2D RightStickValue = FVector2D::ZeroVector;
};
