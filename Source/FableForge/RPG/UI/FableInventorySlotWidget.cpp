#include "RPG/UI/FableInventorySlotWidget.h"

#include "Blueprint/DragDropOperation.h"
#include "Blueprint/WidgetBlueprintLibrary.h"
#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/BorderSlot.h"
#include "Components/Image.h"
#include "Components/Overlay.h"
#include "Components/OverlaySlot.h"
#include "Components/ScaleBox.h"
#include "Components/ScaleBoxSlot.h"
#include "Components/TextBlock.h"
#include "FableForgePlayerController.h"
#include "FableForge.h"
#include "InputCoreTypes.h"
#include "RPG/UI/FableInventoryDragDropOperation.h"
#include "RPG/UI/FablePartyHudWidget.h"
#include "Styling/SlateBrush.h"
#include "Brushes/SlateRoundedBoxBrush.h"
#include "Engine/Texture2D.h"
#include "RPG/UI/FableItemIconLibrary.h"
#include "Rendering/DrawElements.h"

namespace
{
	const FLinearColor UiSlotOutline(0.27f, 0.24f, 0.17f, 0.95f);
	const FLinearColor UiSlotOutlineEquipment(0.67f, 0.49f, 0.23f, 0.98f);
	const FLinearColor UiSlotBackground(0.66f, 0.54f, 0.36f, 1.0f);
	const FLinearColor UiSlotBackgroundEquipment(0.61f, 0.48f, 0.30f, 1.0f);
	const FLinearColor UiInventoryTransparent(0.0f, 0.0f, 0.0f, 0.0f);
	const FLinearColor UiSlotText(0.92f, 0.86f, 0.73f, 1.0f);
	const FLinearColor UiSlotTextMuted(0.12f, 0.065f, 0.028f, 1.0f);
	const FLinearColor UiCooldownOverlay(0.0f, 0.0f, 0.0f, 0.62f);

	FLinearColor SlotOutlineColor(const bool bEquipmentSlot, const bool bActionSlot)
	{
		// Inventory cells deliberately keep a transparent interior, but retain a
		// clear square frame so the hit target is visible against the parchment.
		return bEquipmentSlot ? UiSlotOutlineEquipment : (bActionSlot ? UiInventoryTransparent : UiSlotOutline);
	}

	FSlateBrush SlotOutlineBrush(const bool bEquipmentSlot, const bool bActionSlot, const FLinearColor& OutlineColor)
	{
		return FSlateRoundedBoxBrush(
			UiInventoryTransparent,
			0.0f,
			OutlineColor,
			bActionSlot ? 0.0f : 1.5f);
	}

	FString FormatCooldownText(const float Seconds)
	{
		const float Clamped = FMath::Max(0.0f, Seconds);
		if (Clamped >= 10.0f)
		{
			return FString::Printf(TEXT("%.0f"), FMath::CeilToFloat(Clamped));
		}

		return FString::Printf(TEXT("%.1f"), FMath::CeilToFloat(Clamped * 10.0f) / 10.0f);
	}
}

TSharedRef<SWidget> UFableInventorySlotWidget::RebuildWidget()
{
	if (WidgetTree == nullptr)
	{
		return Super::RebuildWidget();
	}
	const bool bActionSlot = SlotId.ToString().StartsWith(TEXT("action_"));

	RootBorder = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("SlotBorder"));
	RootBorder->SetPadding(FMargin(1.5f));
	RootBorder->SetBrush(SlotOutlineBrush(bEquipmentSlot, bActionSlot, SlotOutlineColor(bEquipmentSlot, bActionSlot)));

	InnerBorder = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("SlotInner"));
	InnerBorder->SetPadding(FMargin(bEquipmentSlot ? 6.0f : 3.0f));
	InnerBorder->SetBrushColor(bActionSlot ? FLinearColor(0.028f, 0.020f, 0.013f, 1.f)
			: (bEquipmentSlot ? UiInventoryTransparent : UiSlotBackground));
	if (!bEquipmentSlot && !bActionSlot)
	{
		InnerBorder->SetBrushColor(UiInventoryTransparent);
	}
	RootBorder->SetContent(InnerBorder);

	ContentOverlay = WidgetTree->ConstructWidget<UOverlay>(UOverlay::StaticClass(), TEXT("SlotOverlay"));
	InnerBorder->SetContent(ContentOverlay);

	IconScaleBox = WidgetTree->ConstructWidget<UScaleBox>(UScaleBox::StaticClass(), TEXT("SlotIconScaleBox"));
	IconScaleBox->SetStretch(EStretch::ScaleToFit);
	IconImage = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass(), TEXT("SlotIcon"));
	IconScaleBox->SetContent(IconImage);
	if (UScaleBoxSlot* IconScaleSlot = Cast<UScaleBoxSlot>(IconImage->Slot))
	{
		IconScaleSlot->SetHorizontalAlignment(HAlign_Center);
		IconScaleSlot->SetVerticalAlignment(VAlign_Center);
	}
	if (UOverlaySlot* IconSlot = ContentOverlay->AddChildToOverlay(IconScaleBox))
	{
		IconSlot->SetHorizontalAlignment(HAlign_Fill);
		IconSlot->SetVerticalAlignment(VAlign_Fill);
		IconSlot->SetPadding(FMargin(2.0f));
	}

	LabelText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("SlotText"));
	LabelText->SetAutoWrapText(true);
	LabelText->SetJustification(ETextJustify::Center);
	if (UOverlaySlot* LabelSlot = ContentOverlay->AddChildToOverlay(LabelText))
	{
		LabelSlot->SetHorizontalAlignment(HAlign_Center);
		LabelSlot->SetVerticalAlignment(VAlign_Center);
		LabelSlot->SetPadding(FMargin(2.0f));
	}

	CooldownOverlay = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("CooldownOverlay"));
	CooldownOverlay->SetBrushColor(UiCooldownOverlay);
	if (UOverlaySlot* CooldownOverlaySlot = ContentOverlay->AddChildToOverlay(CooldownOverlay))
	{
		CooldownOverlaySlot->SetHorizontalAlignment(HAlign_Fill);
		CooldownOverlaySlot->SetVerticalAlignment(VAlign_Fill);
	}

	CooldownText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("CooldownText"));
	CooldownText->SetColorAndOpacity(FSlateColor(UiSlotText));
	CooldownText->SetJustification(ETextJustify::Center);
	if (UOverlaySlot* CooldownTextSlot = ContentOverlay->AddChildToOverlay(CooldownText))
	{
		CooldownTextSlot->SetHorizontalAlignment(HAlign_Center);
		CooldownTextSlot->SetVerticalAlignment(VAlign_Center);
		CooldownTextSlot->SetPadding(FMargin(2.0f));
	}

	bCooldownVisualInitialized = false;
	WidgetTree->RootWidget = RootBorder;
	RefreshVisual();
	return Super::RebuildWidget();
}

void UFableInventorySlotWidget::NativeConstruct()
{
	Super::NativeConstruct();
}

int32 UFableInventorySlotWidget::NativePaint(const FPaintArgs& Args, const FGeometry& AllottedGeometry,
	const FSlateRect& MyCullingRect, FSlateWindowElementList& OutDrawElements, int32 LayerId,
	const FWidgetStyle& InWidgetStyle, bool bParentEnabled) const
{
	const int32 RetLayerId = Super::NativePaint(Args, AllottedGeometry, MyCullingRect, OutDrawElements,
		LayerId, InWidgetStyle, bParentEnabled);
	if (!bJournalGridCell || JournalGridColumnCount <= 0 || JournalGridRowCount <= 0)
	{
		return RetLayerId;
	}

	const FVector2D LocalSize = AllottedGeometry.GetLocalSize();
	const float HalfPixel = 0.5f;
	const int32 GridLayer = RetLayerId + 1;

	auto DrawLine = [&](const FVector2D& Start, const FVector2D& End, const FLinearColor& Color, float Thickness)
	{
		TArray<FVector2D> Points;
		Points.Reserve(2);
		Points.Add(Start);
		Points.Add(End);
		FSlateDrawElement::MakeLines(OutDrawElements, GridLayer, AllottedGeometry.ToPaintGeometry(), Points,
			ESlateDrawEffect::None, Color, true, Thickness);
	};

	const FLinearColor GridColor = bEquipmentSlot ? UiSlotOutlineEquipment : UiSlotOutline;
	// Every cell owns only its left/top edges. The final column/row add the
	// outer right/bottom edges, so shared boundaries are painted once.
	DrawLine(FVector2D(HalfPixel, 0.0f), FVector2D(HalfPixel, LocalSize.Y), GridColor, 1.0f);
	DrawLine(FVector2D(0.0f, HalfPixel), FVector2D(LocalSize.X, HalfPixel), GridColor, 1.0f);
	if (JournalGridColumn == JournalGridColumnCount - 1)
	{
		DrawLine(FVector2D(LocalSize.X - HalfPixel, 0.0f), FVector2D(LocalSize.X - HalfPixel, LocalSize.Y), GridColor, 1.0f);
	}
	if (JournalGridRow == JournalGridRowCount - 1)
	{
		DrawLine(FVector2D(0.0f, LocalSize.Y - HalfPixel), FVector2D(LocalSize.X, LocalSize.Y - HalfPixel), GridColor, 1.0f);
	}

	if (bControllerSelected || bControllerPicked)
	{
		const FLinearColor SelectionColor = bControllerPicked
			? FLinearColor(0.25f, 0.48f, 0.55f, 1.0f)
			: FLinearColor(0.48f, 0.19f, 0.035f, 1.0f);
		DrawLine(FVector2D(1.5f, 1.5f), FVector2D(LocalSize.X - 1.5f, 1.5f), SelectionColor, 3.0f);
		DrawLine(FVector2D(1.5f, LocalSize.Y - 1.5f), FVector2D(LocalSize.X - 1.5f, LocalSize.Y - 1.5f), SelectionColor, 3.0f);
		DrawLine(FVector2D(1.5f, 1.5f), FVector2D(1.5f, LocalSize.Y - 1.5f), SelectionColor, 3.0f);
		DrawLine(FVector2D(LocalSize.X - 1.5f, 1.5f), FVector2D(LocalSize.X - 1.5f, LocalSize.Y - 1.5f), SelectionColor, 3.0f);
	}

	return GridLayer;
}

void UFableInventorySlotWidget::SetJournalGridCell(int32 InColumn, int32 InRow, int32 InColumnCount, int32 InRowCount)
{
	bJournalGridCell = InColumnCount > 0 && InRowCount > 0
		&& InColumn >= 0 && InColumn < InColumnCount
		&& InRow >= 0 && InRow < InRowCount;
	JournalGridColumn = InColumn;
	JournalGridRow = InRow;
	JournalGridColumnCount = InColumnCount;
	JournalGridRowCount = InRowCount;
	RefreshVisual();
}

void UFableInventorySlotWidget::NativeTick(const FGeometry& MyGeometry, float InDeltaTime)
{
	Super::NativeTick(MyGeometry, InDeltaTime);
	(void)MyGeometry;

	if (UseFeedbackTimeRemaining > 0.0f)
	{
		UseFeedbackTimeRemaining = FMath::Max(0.0f, UseFeedbackTimeRemaining - InDeltaTime);
		const float Alpha = 1.0f - (UseFeedbackTimeRemaining / 0.16f);
		const float Pulse = FMath::Sin(Alpha * PI);
		SetRenderScale(FVector2D(1.0f + (Pulse * 0.08f)));
		if (RootBorder != nullptr)
		{
			const bool bActionSlot = SlotId.ToString().StartsWith(TEXT("action_"));
			const FLinearColor BaseColor = SlotOutlineColor(bEquipmentSlot, bActionSlot);
			RootBorder->SetBrush(SlotOutlineBrush(bEquipmentSlot, bActionSlot,
				FMath::Lerp(BaseColor, FLinearColor(0.95f, 0.9f, 0.45f, 1.0f), Pulse)));
		}
	}
}

FReply UFableInventorySlotWidget::NativeOnMouseButtonDown(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent)
{
	// Always recover a source slot before starting a new drag. This also repairs
	// stale state left by a rejected equipment target in older Slate paths.
	ResetDragVisual();
	bDragDetectedThisPress = false;
	bActionClickTriggeredThisPress = false;
	(void)InGeometry;

	UE_LOG(LogFableForge, Log, TEXT("Slot mouse down slot=%s payload=%s label=%s button=%s visible=%d"),
		*SlotId.ToString(),
		*ItemPayloadId,
		*ItemLabel,
		*InMouseEvent.GetEffectingButton().ToString(),
		static_cast<int32>(GetVisibility()));

	if (!ItemLabel.IsEmpty())
	{
		if (SlotId.ToString().StartsWith(TEXT("action_")))
		{
			bool bCtrlDown = InMouseEvent.IsControlDown();
			if (!bCtrlDown)
			{
				if (APlayerController* OwningPC = GetOwningPlayer())
				{
					bCtrlDown = OwningPC->IsInputKeyDown(EKeys::LeftControl) || OwningPC->IsInputKeyDown(EKeys::RightControl);
				}
			}

			if (!bCtrlDown)
			{
				if (InMouseEvent.GetEffectingButton() == EKeys::LeftMouseButton)
				{
					UE_LOG(LogFableForge, Log, TEXT("Action slot left mouse down slot=%s payload=%s ctrl=%d cooldown=%.2f"),
						*SlotId.ToString(), *ItemPayloadId, bCtrlDown ? 1 : 0, CooldownRemainingSeconds);
					if (CooldownRemainingSeconds > 0.0f)
					{
						UE_LOG(LogFableForge, Log, TEXT("Action slot click blocked by cooldown slot=%s remaining=%.2f"),
							*SlotId.ToString(), CooldownRemainingSeconds);
						return FReply::Handled();
					}

					bActionClickTriggeredThisPress = true;
					UE_LOG(LogFableForge, Log, TEXT("Action slot click firing on mouse down slot=%s payload=%s"),
						*SlotId.ToString(), *ItemPayloadId);
					PlayUseFeedback();
					OnSlotClicked.Broadcast(SlotId, ItemPayloadId);
					return FReply::Handled();
				}
				return Super::NativeOnMouseButtonDown(InGeometry, InMouseEvent);
			}
		}
		return UWidgetBlueprintLibrary::DetectDragIfPressed(InMouseEvent, this, EKeys::LeftMouseButton).NativeReply;
	}

	return Super::NativeOnMouseButtonDown(InGeometry, InMouseEvent);
}

FReply UFableInventorySlotWidget::NativeOnMouseButtonUp(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent)
{
	UE_LOG(LogFableForge, Log, TEXT("Slot mouse up slot=%s payload=%s button=%s dragDetected=%d clickOnDown=%d"),
		*SlotId.ToString(),
		*ItemPayloadId,
		*InMouseEvent.GetEffectingButton().ToString(),
		bDragDetectedThisPress ? 1 : 0,
		bActionClickTriggeredThisPress ? 1 : 0);

	if (bTemporarilyDragHidden)
	{
		SetRenderOpacity(1.0f);
		bTemporarilyDragHidden = false;
	}

	if (InMouseEvent.GetEffectingButton() == EKeys::LeftMouseButton && !ItemPayloadId.IsEmpty())
	{
		if (bActionClickTriggeredThisPress)
		{
			UE_LOG(LogFableForge, Log, TEXT("Slot mouse up consumed (action click already fired on down) slot=%s"), *SlotId.ToString());
			bActionClickTriggeredThisPress = false;
			bDragDetectedThisPress = false;
			return FReply::Handled();
		}

		bool bCtrlDown = InMouseEvent.IsControlDown();
		if (!bCtrlDown)
		{
			if (APlayerController* OwningPC = GetOwningPlayer())
			{
				bCtrlDown = OwningPC->IsInputKeyDown(EKeys::LeftControl) || OwningPC->IsInputKeyDown(EKeys::RightControl);
			}
		}

		if (CooldownRemainingSeconds > 0.0f && SlotId.ToString().StartsWith(TEXT("action_")) && !bCtrlDown)
		{
			UE_LOG(LogFableForge, Log, TEXT("Action slot mouse up blocked by cooldown slot=%s remaining=%.2f"),
				*SlotId.ToString(), CooldownRemainingSeconds);
			bDragDetectedThisPress = false;
			return FReply::Handled();
		}

		const bool bShouldTreatAsClick = !bDragDetectedThisPress;
		const bool bWasDragRelease = bDragDetectedThisPress;
		bDragDetectedThisPress = false;

		if (bWasDragRelease)
		{
			if (AFableForgePlayerController* ForgePC = Cast<AFableForgePlayerController>(GetOwningPlayer()))
			{
				if (UFablePartyHudWidget* PartyHud = ForgePC->GetPartyHudWidget())
				{
					const bool bAssigned = PartyHud->TryAssignActionAtScreenPosition(
						InMouseEvent.GetScreenSpacePosition(),
						SlotId,
						ItemPayloadId,
						ItemLabel);
					if (bAssigned)
					{
						return FReply::Handled();
					}
					if (SlotId.ToString().StartsWith(TEXT("action_")))
					{
						if (PartyHud->ClearActionAtSlotId(SlotId))
						{
							return FReply::Handled();
						}
					}
				}
			}
		}

		if (bShouldTreatAsClick)
		{
			UE_LOG(LogFableForge, Log, TEXT("Slot click firing on mouse up slot=%s payload=%s"), *SlotId.ToString(), *ItemPayloadId);
			OnSlotClicked.Broadcast(SlotId, ItemPayloadId);
			return FReply::Handled();
		}
	}

	if (InMouseEvent.GetEffectingButton() == EKeys::RightMouseButton && !ItemPayloadId.IsEmpty())
	{
		OnSlotRightClicked.Broadcast(SlotId, ItemPayloadId);
		return FReply::Handled();
	}

	return Super::NativeOnMouseButtonUp(InGeometry, InMouseEvent);
}

void UFableInventorySlotWidget::NativeOnMouseEnter(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent)
{
	Super::NativeOnMouseEnter(InGeometry, InMouseEvent);
	(void)InGeometry;
	(void)InMouseEvent;

	if (!ItemPayloadId.IsEmpty())
	{
		OnSlotHovered.Broadcast(SlotId, ItemPayloadId);
	}
}

void UFableInventorySlotWidget::NativeOnDragEnter(const FGeometry& InGeometry, const FDragDropEvent& InDragDropEvent, UDragDropOperation* InOperation)
{
	Super::NativeOnDragEnter(InGeometry, InDragDropEvent, InOperation);
	(void)InGeometry;
	(void)InDragDropEvent;

	const UFableInventoryDragDropOperation* DragOperation = Cast<UFableInventoryDragDropOperation>(InOperation);
	if (DragOperation != nullptr)
	{
		if (DragOperation->SourceSlotId == SlotId)
		{
			return;
		}
		UE_LOG(LogFableForge, Log, TEXT("Drag enter target=%s from=%s payload=%s"), *SlotId.ToString(), *DragOperation->SourceSlotId.ToString(), *DragOperation->PayloadId);
	}
}

bool UFableInventorySlotWidget::NativeOnDragOver(const FGeometry& InGeometry, const FDragDropEvent& InDragDropEvent, UDragDropOperation* InOperation)
{
	(void)InGeometry;
	(void)InDragDropEvent;

	const UFableInventoryDragDropOperation* DragOperation = Cast<UFableInventoryDragDropOperation>(InOperation);
	if (DragOperation == nullptr || DragOperation->SourceSlotId == NAME_None || DragOperation->SourceSlotId == SlotId)
	{
		return Super::NativeOnDragOver(InGeometry, InDragDropEvent, InOperation);
	}

	UE_LOG(LogFableForge, Verbose, TEXT("Drag over target=%s from=%s payload=%s"), *SlotId.ToString(), *DragOperation->SourceSlotId.ToString(), *DragOperation->PayloadId);
	return true;
}

void UFableInventorySlotWidget::NativeOnDragDetected(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent, UDragDropOperation*& OutOperation)
{
	Super::NativeOnDragDetected(InGeometry, InMouseEvent, OutOperation);
	bDragDetectedThisPress = true;

	if (ItemLabel.IsEmpty())
	{
		UE_LOG(LogFableForge, Verbose, TEXT("Slot drag ignored (empty item) slot=%s payload=%s"), *SlotId.ToString(), *ItemPayloadId);
		return;
	}

	UFableInventoryDragDropOperation* DragOperation = NewObject<UFableInventoryDragDropOperation>(this);
	if (DragOperation == nullptr)
	{
		UE_LOG(LogFableForge, Warning, TEXT("Failed to create drag operation for slot=%s payload=%s"), *SlotId.ToString(), *ItemPayloadId);
		return;
	}

	if (ItemIconResource != nullptr)
	{
		UImage* DragIcon = NewObject<UImage>(DragOperation);
		FSlateBrush Brush;
		Brush.SetResourceObject(ItemIconResource);
		Brush.ImageSize = FVector2D(56.0f, 56.0f);
		DragIcon->SetBrush(Brush);
		DragIcon->SetVisibility(ESlateVisibility::HitTestInvisible);
		DragOperation->DefaultDragVisual = DragIcon;
	}
	UTextBlock* DragText = ItemIconResource == nullptr ? NewObject<UTextBlock>(DragOperation) : nullptr;
	if (DragText != nullptr)
	{
		DragText->SetText(FText::FromString(ItemLabel));
		DragText->SetColorAndOpacity(FSlateColor(UiSlotText));
		DragText->SetVisibility(ESlateVisibility::HitTestInvisible);
		FSlateFontInfo FontInfo = DragText->GetFont();
		FontInfo.Size = ItemLabel.Len() <= 3 ? 22 : 16;
		DragText->SetFont(FontInfo);
		DragOperation->DefaultDragVisual = DragText;
	}

	DragOperation->SourceSlotId = SlotId;
	DragOperation->PayloadId = ItemPayloadId;
	DragOperation->PayloadLabel = ItemLabel;
	DragOperation->Pivot = EDragPivot::CenterCenter;
	OutOperation = DragOperation;
	// Keep the source hit-testable while dragging. Some rejected equipment drops
	// do not send a cancellation event, which used to leave the source stuck.
	SetRenderOpacity(0.35f);
	bTemporarilyDragHidden = true;
	UE_LOG(LogFableForge, Log, TEXT("Drag started slot=%s payload=%s label=%s"), *SlotId.ToString(), *ItemPayloadId, *ItemLabel);
}

void UFableInventorySlotWidget::NativeOnDragCancelled(const FDragDropEvent& InDragDropEvent, UDragDropOperation* InOperation)
{
	Super::NativeOnDragCancelled(InDragDropEvent, InOperation);

	if (const UFableInventoryDragDropOperation* DragOperation = Cast<UFableInventoryDragDropOperation>(InOperation))
	{
		if (AFableForgePlayerController* ForgePC = Cast<AFableForgePlayerController>(GetOwningPlayer()))
		{
			if (UFablePartyHudWidget* PartyHud = ForgePC->GetPartyHudWidget())
			{
				const bool bAssigned = PartyHud->TryAssignActionAtScreenPosition(
					InDragDropEvent.GetScreenSpacePosition(),
					DragOperation->SourceSlotId,
					DragOperation->PayloadId,
					DragOperation->PayloadLabel);
				UE_LOG(LogFableForge, Log, TEXT("Skill drag cancel fallback assigned=%d slot=%s payload=%s"),
					bAssigned ? 1 : 0,
					*DragOperation->SourceSlotId.ToString(),
					*DragOperation->PayloadId);
				if (!bAssigned && DragOperation->SourceSlotId.ToString().StartsWith(TEXT("action_")))
				{
					const bool bCleared = PartyHud->ClearActionAtSlotId(DragOperation->SourceSlotId);
					UE_LOG(LogFableForge, Log, TEXT("Action drag cancel clear assigned=%d slot=%s payload=%s"),
						bCleared ? 1 : 0,
						*DragOperation->SourceSlotId.ToString(),
						*DragOperation->PayloadId);
				}
			}
		}
	}

	if (bTemporarilyDragHidden)
	{
		SetRenderOpacity(1.0f);
		bTemporarilyDragHidden = false;
	}
}

bool UFableInventorySlotWidget::NativeOnDrop(const FGeometry& InGeometry, const FDragDropEvent& InDragDropEvent, UDragDropOperation* InOperation)
{
	if (bTemporarilyDragHidden)
	{
		SetRenderOpacity(1.0f);
		bTemporarilyDragHidden = false;
	}

	const UFableInventoryDragDropOperation* DragOperation = Cast<UFableInventoryDragDropOperation>(InOperation);
	if (DragOperation == nullptr || DragOperation->SourceSlotId == NAME_None || DragOperation->SourceSlotId == SlotId)
	{
		UE_LOG(LogFableForge, Verbose, TEXT("Slot drop rejected target=%s validOp=%d source=%s"),
			*SlotId.ToString(),
			DragOperation != nullptr ? 1 : 0,
			DragOperation != nullptr ? *DragOperation->SourceSlotId.ToString() : TEXT("None"));
		return Super::NativeOnDrop(InGeometry, InDragDropEvent, InOperation);
	}

	UE_LOG(LogFableForge, Log, TEXT("Slot drop received target=%s from=%s payload=%s label=%s"),
		*SlotId.ToString(),
		*DragOperation->SourceSlotId.ToString(),
		*DragOperation->PayloadId,
		*DragOperation->PayloadLabel);
	// A successful drop does not always dispatch NativeOnDragCancelled back to
	// the source widget. Restore it here so the same item can be dragged again.
	if (UFableInventorySlotWidget* SourceWidget = Cast<UFableInventorySlotWidget>(DragOperation->GetOuter()))
	{
		SourceWidget->SetRenderOpacity(1.0f);
		SourceWidget->bTemporarilyDragHidden = false;
	}
	OnItemDrop.Broadcast(DragOperation->SourceSlotId, SlotId, DragOperation->PayloadId, DragOperation->PayloadLabel);
	return true;
}

void UFableInventorySlotWidget::InitializeSlot(FName InSlotId, const FString& InDisplayName, bool bInEquipmentSlot)
{
	SlotId = InSlotId;
	EmptyDisplayName = InDisplayName;
	bEquipmentSlot = bInEquipmentSlot;
	bJournalGridCell = false;
	JournalGridColumn = 0;
	JournalGridRow = 0;
	JournalGridColumnCount = 0;
	JournalGridRowCount = 0;
	RefreshVisual();
}

void UFableInventorySlotWidget::SetItemLabel(const FString& InItemLabel)
{
	ItemPayloadId = InItemLabel;
	ItemLabel = InItemLabel;
	ItemIconResource = FableItemIcons::Get(InItemLabel);
	SetToolTipText(FText::FromString(InItemLabel.IsEmpty() && bEquipmentSlot ? EmptyDisplayName : InItemLabel));
	RefreshVisual();
}

void UFableInventorySlotWidget::SetItemData(const FString& InPayloadId, const FString& InItemLabel, UObject* InIconResource)
{
	ItemPayloadId = InPayloadId;
	ItemLabel = InItemLabel;
	ItemIconResource = InIconResource != nullptr ? InIconResource : FableItemIcons::Get(InPayloadId);
	SetToolTipText(FText::FromString(InItemLabel.IsEmpty() && bEquipmentSlot ? EmptyDisplayName : InItemLabel));
	RefreshVisual();
}

void UFableInventorySlotWidget::SetCooldownRemaining(float InRemainingSeconds)
{
	CooldownRemainingSeconds = FMath::Max(0.0f, InRemainingSeconds);
	// Only mutate the timer layer when its displayed tenth changes. Rebuilding the
	// icon brush, font and label every frame invalidates every action-bar cell.
	RefreshCooldownVisual();
}

void UFableInventorySlotWidget::PlayUseFeedback()
{
	UseFeedbackTimeRemaining = 0.16f;
	UE_LOG(LogFableForge, Log, TEXT("Slot use feedback slot=%s payload=%s"), *SlotId.ToString(), *ItemPayloadId);
	SetRenderScale(FVector2D(1.08f, 1.08f));
	if (RootBorder != nullptr)
	{
		RootBorder->SetBrushColor(FLinearColor(0.95f, 0.9f, 0.45f, 1.0f));
	}
}

void UFableInventorySlotWidget::ResetDragVisual()
{
	SetRenderOpacity(1.0f);
	bTemporarilyDragHidden = false;
}

FName UFableInventorySlotWidget::GetSlotId() const
{
	return SlotId;
}

void UFableInventorySlotWidget::SetEmptyEquipmentBrush(const FSlateBrush& InBrush)
{
	EmptyEquipmentBrush = InBrush;
	RefreshVisual();
}

void UFableInventorySlotWidget::SetControllerSelection(bool bSelected, bool bPicked)
{
	if (bControllerSelected == bSelected && bControllerPicked == bPicked) return;
	bControllerSelected = bSelected;
	bControllerPicked = bPicked;
	RefreshVisual();
}

void UFableInventorySlotWidget::RefreshVisual()
{
	if (RootBorder != nullptr)
	{
		const bool bActionSlot = SlotId.ToString().StartsWith(TEXT("action_"));
		if (bJournalGridCell)
		{
			RootBorder->SetBrush(FSlateRoundedBoxBrush(UiInventoryTransparent, 0.0f, UiInventoryTransparent, 0.0f));
		}
		else
		{
			RootBorder->SetBrush(SlotOutlineBrush(bEquipmentSlot, bActionSlot, SlotOutlineColor(bEquipmentSlot, bActionSlot)));
			if (bControllerSelected || bControllerPicked)
			{
				RootBorder->SetBrush(FSlateRoundedBoxBrush(FLinearColor(0.65f, 0.40f, 0.12f, 0.10f), 0.f,
					bControllerPicked ? FLinearColor(0.25f, 0.48f, 0.55f, 1.f) : FLinearColor(0.48f, 0.19f, 0.035f, 1.f), 3.f));
			}
		}
	}

	if (InnerBorder != nullptr)
	{
		const bool bActionSlot = SlotId.ToString().StartsWith(TEXT("action_"));
		InnerBorder->SetBrushColor(bActionSlot ? FLinearColor(0.028f, 0.020f, 0.013f, 1.f)
			: (bEquipmentSlot ? UiInventoryTransparent : UiSlotBackground));
		if (!bEquipmentSlot && !bActionSlot)
		{
			InnerBorder->SetBrushColor(UiInventoryTransparent);
		}
	}

	if (LabelText == nullptr)
	{
		return;
	}

	if (IconImage != nullptr)
	{
		if (ItemIconResource != nullptr && !ItemPayloadId.IsEmpty())
		{
			FSlateBrush IconBrush;
			IconBrush.SetResourceObject(ItemIconResource);
			if (const UTexture2D* IconTexture = Cast<UTexture2D>(ItemIconResource))
			{
				IconBrush.ImageSize = FVector2D(IconTexture->GetSizeX(), IconTexture->GetSizeY());
			}
			else
			{
				IconBrush.ImageSize = FVector2D(70.0f, 70.0f);
			}
			IconImage->SetBrush(IconBrush);
			IconImage->SetColorAndOpacity(FLinearColor::White);
			IconImage->SetVisibility(ESlateVisibility::HitTestInvisible);
		}
		else if (bEquipmentSlot && ItemPayloadId.IsEmpty() && EmptyEquipmentBrush.GetResourceObject() != nullptr)
		{
			IconImage->SetBrush(EmptyEquipmentBrush);
			IconImage->SetColorAndOpacity(FLinearColor(0.45f, 0.28f, 0.12f, 0.48f));
			IconImage->SetVisibility(ESlateVisibility::HitTestInvisible);
		}
		else
		{
			IconImage->SetBrush(FSlateBrush());
			IconImage->SetColorAndOpacity(FLinearColor::White);
			IconImage->SetVisibility(ESlateVisibility::Collapsed);
		}
	}

	if (ItemLabel.IsEmpty())
	{
		bCooldownVisualInitialized = false;
		LabelText->SetText(FText::FromString(EmptyDisplayName.Replace(TEXT(" Hand"), TEXT("\nHand"))));
		LabelText->SetColorAndOpacity(FSlateColor(UiSlotTextMuted));
		LabelText->SetVisibility(bEquipmentSlot ? ESlateVisibility::Collapsed : ESlateVisibility::HitTestInvisible);
		FSlateFontInfo FontInfo = LabelText->GetFont();
		FontInfo.Size = EmptyDisplayName.IsEmpty() ? 10 : 13;
		LabelText->SetFont(FontInfo);
		if (CooldownOverlay != nullptr)
		{
			CooldownOverlay->SetVisibility(ESlateVisibility::Collapsed);
		}
		if (CooldownText != nullptr)
		{
			CooldownText->SetVisibility(ESlateVisibility::Collapsed);
		}
		return;
	}

	LabelText->SetText(FText::FromString(ItemLabel));
	LabelText->SetColorAndOpacity(FSlateColor(UiSlotText));
	LabelText->SetVisibility(ItemIconResource != nullptr ? ESlateVisibility::Collapsed : ESlateVisibility::HitTestInvisible);
	FSlateFontInfo FontInfo = LabelText->GetFont();
	FontInfo.Size = ItemLabel.Len() <= 3 ? 30 : 15;
	LabelText->SetFont(FontInfo);

	RefreshCooldownVisual();
}

void UFableInventorySlotWidget::RefreshCooldownVisual()
{
	const FString DisplayText = !ItemLabel.IsEmpty() && CooldownRemainingSeconds > 0.0f && SlotId.ToString().StartsWith(TEXT("action_"))
		? FormatCooldownText(CooldownRemainingSeconds) : FString();
	if (DisplayText == LastCooldownDisplay && bCooldownVisualInitialized) { return; }
	LastCooldownDisplay = DisplayText;
	bCooldownVisualInitialized = true;
	const bool bShowCooldown = !DisplayText.IsEmpty();
	if (CooldownOverlay != nullptr)
	{
		CooldownOverlay->SetVisibility(bShowCooldown ? ESlateVisibility::HitTestInvisible : ESlateVisibility::Collapsed);
	}
	if (CooldownText != nullptr)
	{
		if (bShowCooldown)
		{
			CooldownText->SetText(FText::FromString(DisplayText));
			CooldownText->SetVisibility(ESlateVisibility::HitTestInvisible);
			FSlateFontInfo CooldownFont = CooldownText->GetFont();
			CooldownFont.Size = 18;
			CooldownText->SetFont(CooldownFont);
		}
		else
		{
			CooldownText->SetVisibility(ESlateVisibility::Collapsed);
		}
	}
}
