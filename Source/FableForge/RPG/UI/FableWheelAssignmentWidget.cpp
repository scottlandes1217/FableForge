#include "RPG/UI/FableWheelAssignmentWidget.h"

#include "Blueprint/WidgetTree.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/TextBlock.h"
#include "InputCoreTypes.h"
#include "Input/Reply.h"
#include "RPG/UI/FableBookStyle.h"
#include "RPG/UI/FableTimeWheelWidget.h"

namespace
{
	const FLinearColor LabelColor(0.92f, 0.86f, 0.73f, 1.0f);
	const FLinearColor MutedLabelColor(0.72f, 0.63f, 0.48f, 1.0f);
}

TSharedRef<SWidget> UFableWheelAssignmentWidget::RebuildWidget()
{
	if (WidgetTree != nullptr)
	{
		RootCanvas = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("WheelAssignmentRoot"));
		WidgetTree->RootWidget = RootCanvas;
	}
	SetIsFocusable(true);
	return Super::RebuildWidget();
}

void UFableWheelAssignmentWidget::NativeConstruct()
{
	Super::NativeConstruct();
	SetVisibility(ESlateVisibility::Collapsed);
	SetIsFocusable(true);
}

void UFableWheelAssignmentWidget::Open(const TArray<FFableQuickWheelPageData>& InPages,
	const TArray<FString>& InAvailablePayloads, const TArray<FString>& InLabels)
{
	Pages = InPages;
	AvailablePayloads = InAvailablePayloads;
	AvailableLabels = InLabels;
	for (FFableQuickWheelPageData& Page : Pages)
	{
		Page.Slots.SetNum(8);
	}
	PageIndex = 0;
	SelectedSlot = 0;
	SelectedAvailable = 0;
	bAvailablePayloadLocked = false;
	RightStickValue = FVector2D::ZeroVector;
	bOpen = true;
	SetVisibility(ESlateVisibility::Visible);
	RebuildContent();
	SetKeyboardFocus();
}

void UFableWheelAssignmentWidget::Close()
{
	bOpen = false;
	if (TimeWheelWidget != nullptr)
	{
		TimeWheelWidget->Close();
	}
	SetVisibility(ESlateVisibility::Collapsed);
}

void UFableWheelAssignmentWidget::SetSelectedAvailablePayload(const FString& Payload)
{
	const int32 PreferredIndex = AvailablePayloads.IndexOfByKey(Payload);
	if (PreferredIndex == INDEX_NONE)
	{
		return;
	}
	SelectedAvailable = PreferredIndex;
	bAvailablePayloadLocked = true;
	RebuildContent();
}

void UFableWheelAssignmentWidget::MoveSelection(int32 Delta)
{
	if (!bOpen)
	{
		return;
	}
	SelectedSlot = (SelectedSlot + Delta) % 8;
	if (SelectedSlot < 0)
	{
		SelectedSlot += 8;
	}
	if (TimeWheelWidget != nullptr)
	{
		TimeWheelWidget->SetSelectedSlot(SelectedSlot);
	}
	SyncWheelSelection();
}

void UFableWheelAssignmentWidget::ConfirmAssignment()
{
	if (!bOpen || !Pages.IsValidIndex(PageIndex) || !AvailablePayloads.IsValidIndex(SelectedAvailable))
	{
		return;
	}

	Pages[PageIndex].Slots.SetNum(8);
	FFableActionSlotData& Slot = Pages[PageIndex].Slots[SelectedSlot];
	Slot.EntryId = AvailablePayloads[SelectedAvailable];
	Slot.EntryLabel = AvailableLabels.IsValidIndex(SelectedAvailable) ? AvailableLabels[SelectedAvailable] : Slot.EntryId;
	OnPagesChanged.Broadcast(Pages);
	Close();
	OnClosed.Broadcast();
}

void UFableWheelAssignmentWidget::Cancel()
{
	if (!bOpen)
	{
		return;
	}
	Close();
	OnClosed.Broadcast();
}

FReply UFableWheelAssignmentWidget::NativeOnPreviewKeyDown(const FGeometry& InGeometry, const FKeyEvent& InKeyEvent)
{
	if (!bOpen)
	{
		return Super::NativeOnPreviewKeyDown(InGeometry, InKeyEvent);
	}

	const FKey Key = InKeyEvent.GetKey();
	if (Key == EKeys::Left || Key == EKeys::Gamepad_DPad_Left)
	{
		MoveSelection(-1);
		return FReply::Handled();
	}
	if (Key == EKeys::Right || Key == EKeys::Gamepad_DPad_Right)
	{
		MoveSelection(1);
		return FReply::Handled();
	}
	if (Key == EKeys::Up || Key == EKeys::Gamepad_DPad_Up)
	{
		MoveSelection(-1);
		return FReply::Handled();
	}
	if (Key == EKeys::Down || Key == EKeys::Gamepad_DPad_Down)
	{
		MoveSelection(1);
		return FReply::Handled();
	}
	if (Key == EKeys::Gamepad_LeftShoulder || Key == EKeys::Gamepad_LeftTrigger || Key == EKeys::PageUp)
	{
		if (!InKeyEvent.IsRepeat()) ChangePage(-1);
		return FReply::Handled();
	}
	if (Key == EKeys::Gamepad_RightShoulder || Key == EKeys::Gamepad_RightTrigger || Key == EKeys::PageDown)
	{
		if (!InKeyEvent.IsRepeat()) ChangePage(1);
		return FReply::Handled();
	}
	if (Key == EKeys::Enter || Key == EKeys::Gamepad_FaceButton_Bottom)
	{
		if (!InKeyEvent.IsRepeat()) ConfirmAssignment();
		return FReply::Handled();
	}
	if (Key == EKeys::Escape || Key == EKeys::Gamepad_FaceButton_Right)
	{
		if (!InKeyEvent.IsRepeat()) Cancel();
		return FReply::Handled();
	}

	return Super::NativeOnPreviewKeyDown(InGeometry, InKeyEvent);
}

FReply UFableWheelAssignmentWidget::NativeOnKeyDown(const FGeometry& InGeometry, const FKeyEvent& InKeyEvent)
{
	return Super::NativeOnKeyDown(InGeometry, InKeyEvent);
}

FReply UFableWheelAssignmentWidget::NativeOnAnalogValueChanged(const FGeometry& InGeometry,
	const FAnalogInputEvent& InAnalogInputEvent)
{
	if (!bOpen || TimeWheelWidget == nullptr)
	{
		return Super::NativeOnAnalogValueChanged(InGeometry, InAnalogInputEvent);
	}

	const FKey Key = InAnalogInputEvent.GetKey();
	if (Key == EKeys::Gamepad_RightX)
	{
		RightStickValue.X = InAnalogInputEvent.GetAnalogValue();
	}
	else if (Key == EKeys::Gamepad_RightY)
	{
		RightStickValue.Y = -InAnalogInputEvent.GetAnalogValue();
	}
	else
	{
		return Super::NativeOnAnalogValueChanged(InGeometry, InAnalogInputEvent);
	}

	TimeWheelWidget->SetSelectionFromStick(RightStickValue);
	SyncWheelSelection();
	return FReply::Handled();
}

FReply UFableWheelAssignmentWidget::NativeOnMouseMove(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent)
{
	if (!bOpen || TimeWheelWidget == nullptr)
	{
		return Super::NativeOnMouseMove(InGeometry, InMouseEvent);
	}

	const FGeometry& WheelGeometry = TimeWheelWidget->GetCachedGeometry();
	const FVector2D LocalPosition = WheelGeometry.AbsoluteToLocal(InMouseEvent.GetScreenSpacePosition());
	const FVector2D Center = WheelGeometry.GetLocalSize() * 0.5f;
	const FVector2D Delta(LocalPosition.X - Center.X, LocalPosition.Y - Center.Y);
	if (Delta.SizeSquared() > FMath::Square(20.0f))
	{
		TimeWheelWidget->SetSelectionFromStick(Delta.GetSafeNormal());
		SyncWheelSelection();
	}
	return FReply::Handled();
}

FReply UFableWheelAssignmentWidget::NativeOnMouseButtonDown(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent)
{
	if (!bOpen || InMouseEvent.GetEffectingButton() != EKeys::LeftMouseButton)
	{
		return Super::NativeOnMouseButtonDown(InGeometry, InMouseEvent);
	}
	const int32 ClickedSocket = FindSocketAtPointer(InGeometry, InMouseEvent);
	if (ClickedSocket != INDEX_NONE)
	{
		SelectedSlot = ClickedSocket;
		if (TimeWheelWidget != nullptr)
		{
			TimeWheelWidget->SetSelectedSlot(SelectedSlot);
		}
		ConfirmAssignment();
		return FReply::Handled();
	}
	return FReply::Handled();
}

void UFableWheelAssignmentWidget::RebuildContent()
{
	if (RootCanvas == nullptr || WidgetTree == nullptr)
	{
		return;
	}

	RootCanvas->ClearChildren();
	TimeWheelWidget = WidgetTree->ConstructWidget<UFableTimeWheelWidget>(UFableTimeWheelWidget::StaticClass(), TEXT("AssignmentTimeWheel"));
	if (UCanvasPanelSlot* WheelSlot = RootCanvas->AddChildToCanvas(TimeWheelWidget))
	{
		WheelSlot->SetAnchors(FAnchors(0.0f, 0.0f, 1.0f, 1.0f));
		WheelSlot->SetOffsets(FMargin(0.0f));
	}
	TimeWheelWidget->TakeWidget();
	TimeWheelWidget->Open(Pages);
	TimeWheelWidget->SetVisibility(ESlateVisibility::HitTestInvisible);
	TimeWheelWidget->SetPage(PageIndex);
	TimeWheelWidget->SetSelectedSlot(SelectedSlot);

	SelectedPayloadText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("SelectedPayload"));
	SelectedPayloadText->SetText(FText::FromString(AvailableLabels.IsValidIndex(SelectedAvailable) ? AvailableLabels[SelectedAvailable] : TEXT("Select a wheel socket")));
	SelectedPayloadText->SetColorAndOpacity(LabelColor);
	SelectedPayloadText->SetJustification(ETextJustify::Center);
	SelectedPayloadText->SetFont(FableBookStyle::Font(18, true));
	if (UCanvasPanelSlot* LabelSlot = RootCanvas->AddChildToCanvas(SelectedPayloadText))
	{
		LabelSlot->SetAnchors(FAnchors(0.5f, 0.5f));
		LabelSlot->SetAlignment(FVector2D(0.5f, 0.5f));
		LabelSlot->SetPosition(FVector2D(0.0f, -330.0f));
		LabelSlot->SetSize(FVector2D(720.0f, 34.0f));
	}

	PageText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("AssignmentPage"));
	PageText->SetText(FText::FromString(FString::Printf(TEXT("Page %d / %d"), Pages.Num() == 0 ? 0 : PageIndex + 1, Pages.Num())));
	PageText->SetColorAndOpacity(MutedLabelColor);
	PageText->SetJustification(ETextJustify::Center);
	PageText->SetFont(FableBookStyle::Font(14, false));
	if (UCanvasPanelSlot* PageSlot = RootCanvas->AddChildToCanvas(PageText))
	{
		PageSlot->SetAnchors(FAnchors(0.5f, 0.5f));
		PageSlot->SetAlignment(FVector2D(0.5f, 0.5f));
		PageSlot->SetPosition(FVector2D(0.0f, 330.0f));
		PageSlot->SetSize(FVector2D(500.0f, 30.0f));
	}
}

void UFableWheelAssignmentWidget::SyncWheelSelection()
{
	if (TimeWheelWidget == nullptr)
	{
		return;
	}
	SelectedSlot = TimeWheelWidget->GetSelectedSlot();
	if (SelectedPayloadText != nullptr)
	{
		SelectedPayloadText->SetText(FText::FromString(AvailableLabels.IsValidIndex(SelectedAvailable) ? AvailableLabels[SelectedAvailable] : TEXT("Select a wheel socket")));
	}
}

int32 UFableWheelAssignmentWidget::FindSocketAtPointer(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent) const
{
	if (TimeWheelWidget == nullptr)
	{
		return INDEX_NONE;
	}
	const FGeometry& WheelGeometry = TimeWheelWidget->GetCachedGeometry();
	const FVector2D LocalPosition = WheelGeometry.AbsoluteToLocal(InMouseEvent.GetScreenSpacePosition());
	const FVector2D Center = WheelGeometry.GetLocalSize() * 0.5f;
	for (int32 SocketIndex = 0; SocketIndex < 8; ++SocketIndex)
	{
		if (FVector2D::Distance(LocalPosition, Center + UFableTimeWheelWidget::GetSocketPosition(SocketIndex)) <= 55.0f)
		{
			return SocketIndex;
		}
	}
	return INDEX_NONE;
}

void UFableWheelAssignmentWidget::ChangePage(int32 Delta)
{
	if (Pages.Num() == 0)
	{
		return;
	}
	PageIndex = (PageIndex + Delta) % Pages.Num();
	if (PageIndex < 0)
	{
		PageIndex += Pages.Num();
	}
	SelectedSlot = 0;
	RebuildContent();
}
