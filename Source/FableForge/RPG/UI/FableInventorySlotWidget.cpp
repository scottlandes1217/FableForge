#include "RPG/UI/FableInventorySlotWidget.h"

#include "Blueprint/DragDropOperation.h"
#include "Blueprint/WidgetBlueprintLibrary.h"
#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/BorderSlot.h"
#include "Components/TextBlock.h"
#include "InputCoreTypes.h"
#include "RPG/UI/FableInventoryDragDropOperation.h"

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

	LabelText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("SlotText"));
	LabelText->SetAutoWrapText(false);
	LabelText->SetJustification(ETextJustify::Center);
	InnerBorder->SetContent(LabelText);

	if (UBorderSlot* BorderSlot = Cast<UBorderSlot>(LabelText->Slot))
	{
		BorderSlot->SetHorizontalAlignment(HAlign_Center);
		BorderSlot->SetVerticalAlignment(VAlign_Center);
	}

	WidgetTree->RootWidget = RootBorder;
	RefreshVisual();
	return Super::RebuildWidget();
}

FReply UFableInventorySlotWidget::NativeOnMouseButtonDown(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent)
{
	if (!ItemLabel.IsEmpty())
	{
		return UWidgetBlueprintLibrary::DetectDragIfPressed(InMouseEvent, this, EKeys::LeftMouseButton).NativeReply;
	}

	return Super::NativeOnMouseButtonDown(InGeometry, InMouseEvent);
}

void UFableInventorySlotWidget::NativeOnDragDetected(const FGeometry& InGeometry, const FPointerEvent& InMouseEvent, UDragDropOperation*& OutOperation)
{
	Super::NativeOnDragDetected(InGeometry, InMouseEvent, OutOperation);

	if (ItemLabel.IsEmpty())
	{
		return;
	}

	UFableInventoryDragDropOperation* DragOperation = NewObject<UFableInventoryDragDropOperation>(this);
	if (DragOperation == nullptr)
	{
		return;
	}

	UTextBlock* DragText = NewObject<UTextBlock>(DragOperation);
	if (DragText != nullptr)
	{
		DragText->SetText(FText::FromString(ItemLabel));
		DragText->SetColorAndOpacity(FSlateColor(UiSlotText));
		FSlateFontInfo FontInfo = DragText->GetFont();
		FontInfo.Size = ItemLabel.Len() <= 3 ? 22 : 16;
		DragText->SetFont(FontInfo);
		DragOperation->DefaultDragVisual = DragText;
	}

	DragOperation->SourceSlotId = SlotId;
	DragOperation->PayloadId = ItemPayloadId;
	DragOperation->PayloadLabel = ItemLabel;
	DragOperation->Pivot = EDragPivot::MouseDown;
	OutOperation = DragOperation;
}

bool UFableInventorySlotWidget::NativeOnDrop(const FGeometry& InGeometry, const FDragDropEvent& InDragDropEvent, UDragDropOperation* InOperation)
{
	const UFableInventoryDragDropOperation* DragOperation = Cast<UFableInventoryDragDropOperation>(InOperation);
	if (DragOperation == nullptr || DragOperation->SourceSlotId == NAME_None || DragOperation->SourceSlotId == SlotId)
	{
		return Super::NativeOnDrop(InGeometry, InDragDropEvent, InOperation);
	}

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
	RefreshVisual();
}

void UFableInventorySlotWidget::SetItemData(const FString& InPayloadId, const FString& InItemLabel)
{
	ItemPayloadId = InPayloadId;
	ItemLabel = InItemLabel;
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

	if (ItemLabel.IsEmpty())
	{
		LabelText->SetText(FText::FromString(EmptyDisplayName));
		LabelText->SetColorAndOpacity(FSlateColor(UiSlotTextMuted));
		FSlateFontInfo FontInfo = LabelText->GetFont();
		FontInfo.Size = EmptyDisplayName.IsEmpty() ? 10 : 13;
		LabelText->SetFont(FontInfo);
		return;
	}

	LabelText->SetText(FText::FromString(ItemLabel));
	LabelText->SetColorAndOpacity(FSlateColor(UiSlotText));
	FSlateFontInfo FontInfo = LabelText->GetFont();
	FontInfo.Size = ItemLabel.Len() <= 3 ? 30 : 15;
	LabelText->SetFont(FontInfo);
}
