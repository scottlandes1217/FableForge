#include "RPG/UI/FableInventorySlotWidget.h"

#include "Blueprint/DragDropOperation.h"
#include "Blueprint/WidgetBlueprintLibrary.h"
#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/BorderSlot.h"
#include "Components/Image.h"
#include "Components/Overlay.h"
#include "Components/OverlaySlot.h"
#include "Components/TextBlock.h"
#include "FableForgePlayerController.h"
#include "FableForge.h"
#include "InputCoreTypes.h"
#include "RPG/UI/FableInventoryDragDropOperation.h"
#include "RPG/UI/FablePartyHudWidget.h"
#include "Styling/SlateBrush.h"

namespace
{
	const FLinearColor UiSlotOutline(0.42f, 0.42f, 0.42f, 0.95f);
	const FLinearColor UiSlotOutlineEquipment(0.62f, 0.53f, 0.30f, 0.98f);
	const FLinearColor UiSlotBackground(0.015f, 0.015f, 0.015f, 0.98f);
	const FLinearColor UiSlotBackgroundEquipment(0.022f, 0.022f, 0.022f, 1.0f);
	const FLinearColor UiSlotText(0.95f, 0.95f, 0.95f, 1.0f);
	const FLinearColor UiSlotTextMuted(0.46f, 0.46f, 0.46f, 1.0f);
}

TSharedRef<SWidget> UFableInventorySlotWidget::RebuildWidget()
{
	if (WidgetTree == nullptr)
	{
		return Super::RebuildWidget();
	}

	RootBorder = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("SlotBorder"));
	RootBorder->SetPadding(FMargin(1.5f));
	RootBorder->SetBrushColor(bEquipmentSlot ? UiSlotOutlineEquipment : UiSlotOutline);

	InnerBorder = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("SlotInner"));
	InnerBorder->SetPadding(FMargin(3.0f));
	InnerBorder->SetBrushColor(bEquipmentSlot ? UiSlotBackgroundEquipment : UiSlotBackground);
	RootBorder->SetContent(InnerBorder);

	ContentOverlay = WidgetTree->ConstructWidget<UOverlay>(UOverlay::StaticClass(), TEXT("SlotOverlay"));
	InnerBorder->SetContent(ContentOverlay);

	IconImage = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass(), TEXT("SlotIcon"));
	if (UOverlaySlot* IconSlot = ContentOverlay->AddChildToOverlay(IconImage))
	{
		IconSlot->SetHorizontalAlignment(HAlign_Fill);
		IconSlot->SetVerticalAlignment(VAlign_Fill);
		IconSlot->SetPadding(FMargin(2.0f));
	}

	LabelText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("SlotText"));
	LabelText->SetAutoWrapText(false);
	LabelText->SetJustification(ETextJustify::Center);
	if (UOverlaySlot* LabelSlot = ContentOverlay->AddChildToOverlay(LabelText))
	{
		LabelSlot->SetHorizontalAlignment(HAlign_Center);
		LabelSlot->SetVerticalAlignment(VAlign_Center);
		LabelSlot->SetPadding(FMargin(2.0f));
	}

	WidgetTree->RootWidget = RootBorder;
	RefreshVisual();
	return Super::RebuildWidget();
}

FReply UFableInventorySlotWidget::NativeOnMouseButtonDown(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent)
{
	bDragDetectedThisPress = false;

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
				return Super::NativeOnMouseButtonDown(InGeometry, InMouseEvent);
			}
		}
		return UWidgetBlueprintLibrary::DetectDragIfPressed(InMouseEvent, this, EKeys::LeftMouseButton).NativeReply;
	}

	return Super::NativeOnMouseButtonDown(InGeometry, InMouseEvent);
}

FReply UFableInventorySlotWidget::NativeOnMouseButtonUp(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent)
{
	if (bTemporarilyDragHidden)
	{
		SetVisibility(ESlateVisibility::Visible);
		bTemporarilyDragHidden = false;
	}

	if (InMouseEvent.GetEffectingButton() == EKeys::LeftMouseButton && !ItemPayloadId.IsEmpty())
	{
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
			OnSlotClicked.Broadcast(SlotId, ItemPayloadId);
			return FReply::Handled();
		}
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

	UTextBlock* DragText = NewObject<UTextBlock>(DragOperation);
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
	SetVisibility(ESlateVisibility::HitTestInvisible);
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
		SetVisibility(ESlateVisibility::Visible);
		bTemporarilyDragHidden = false;
	}
}

bool UFableInventorySlotWidget::NativeOnDrop(const FGeometry& InGeometry, const FDragDropEvent& InDragDropEvent, UDragDropOperation* InOperation)
{
	if (bTemporarilyDragHidden)
	{
		SetVisibility(ESlateVisibility::Visible);
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
	OnItemDrop.Broadcast(DragOperation->SourceSlotId, SlotId, DragOperation->PayloadId, DragOperation->PayloadLabel);
	return true;
}

void UFableInventorySlotWidget::InitializeSlot(FName InSlotId, const FString& InDisplayName, bool bInEquipmentSlot)
{
	SlotId = InSlotId;
	EmptyDisplayName = InDisplayName;
	bEquipmentSlot = bInEquipmentSlot;
	RefreshVisual();
}

void UFableInventorySlotWidget::SetItemLabel(const FString& InItemLabel)
{
	ItemPayloadId = InItemLabel;
	ItemLabel = InItemLabel;
	ItemIconResource = nullptr;
	RefreshVisual();
}

void UFableInventorySlotWidget::SetItemData(const FString& InPayloadId, const FString& InItemLabel, UObject* InIconResource)
{
	ItemPayloadId = InPayloadId;
	ItemLabel = InItemLabel;
	ItemIconResource = InIconResource;
	RefreshVisual();
}

FName UFableInventorySlotWidget::GetSlotId() const
{
	return SlotId;
}

void UFableInventorySlotWidget::RefreshVisual()
{
	if (RootBorder != nullptr)
	{
		RootBorder->SetBrushColor(bEquipmentSlot ? UiSlotOutlineEquipment : UiSlotOutline);
	}

	if (InnerBorder != nullptr)
	{
		InnerBorder->SetBrushColor(bEquipmentSlot ? UiSlotBackgroundEquipment : UiSlotBackground);
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
			IconBrush.ImageSize = FVector2D(64.0f, 64.0f);
			IconImage->SetBrush(IconBrush);
			IconImage->SetVisibility(ESlateVisibility::HitTestInvisible);
		}
		else
		{
			IconImage->SetBrush(FSlateBrush());
			IconImage->SetVisibility(ESlateVisibility::Collapsed);
		}
	}

	if (ItemLabel.IsEmpty())
	{
		LabelText->SetText(FText::FromString(EmptyDisplayName));
		LabelText->SetColorAndOpacity(FSlateColor(UiSlotTextMuted));
		LabelText->SetVisibility(ESlateVisibility::HitTestInvisible);
		FSlateFontInfo FontInfo = LabelText->GetFont();
		FontInfo.Size = EmptyDisplayName.IsEmpty() ? 10 : 13;
		LabelText->SetFont(FontInfo);
		return;
	}

	LabelText->SetText(FText::FromString(ItemLabel));
	LabelText->SetColorAndOpacity(FSlateColor(UiSlotText));
	LabelText->SetVisibility(ItemIconResource != nullptr ? ESlateVisibility::Collapsed : ESlateVisibility::HitTestInvisible);
	FSlateFontInfo FontInfo = LabelText->GetFont();
	FontInfo.Size = ItemLabel.Len() <= 3 ? 30 : 15;
	LabelText->SetFont(FontInfo);
}
