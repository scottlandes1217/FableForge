#include "RPG/UI/FableActionBarWidget.h"

#include "Blueprint/WidgetLayoutLibrary.h"
#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/ButtonSlot.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/SizeBox.h"
#include "Components/Spacer.h"
#include "Components/TextBlock.h"
#include "Components/UniformGridPanel.h"
#include "Components/UniformGridSlot.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Engine/GameViewportClient.h"
#include "FableForge.h"
#include "RPG/UI/FableActionButton.h"
#include "RPG/UI/FableInventoryDragDropOperation.h"
#include "RPG/UI/FableInventorySlotWidget.h"

namespace
{
	const FLinearColor UiBarColor(0.01f, 0.01f, 0.01f, 0.95f);
	const FLinearColor UiTextColor(0.95f, 0.95f, 0.95f, 1.0f);
	const FLinearColor UiButtonColor(0.05f, 0.05f, 0.05f, 1.0f);
	const FLinearColor UiDragHandleColor(0.08f, 0.08f, 0.08f, 1.0f);
	const FVector2D UiSmallControlSize(26.0f, 26.0f);

	FString ShortToken(const FString& InValue)
	{
		if (InValue.IsEmpty())
		{
			return TEXT("");
		}

		FString Copy = InValue;
		Copy.ReplaceInline(TEXT("skill:"), TEXT(""));
		Copy.ReplaceInline(TEXT("_"), TEXT(" "));
		TArray<FString> Words;
		Copy.ParseIntoArray(Words, TEXT(" "), true);
		FString Token;
		for (const FString& Word : Words)
		{
			if (Word.IsEmpty())
			{
				continue;
			}

			Token += Word.Left(1).ToUpper();
			if (Token.Len() >= 2)
			{
				return Token.Left(2);
			}
		}

		return Copy.Left(2).ToUpper();
	}

	FName MakeActionSlotId(const FGuid& BarId, int32 SlotIndex)
	{
		const FString GuidToken = BarId.ToString(EGuidFormats::Digits);
		return FName(*FString::Printf(TEXT("action_%s_%d"), *GuidToken, SlotIndex));
	}
}

TSharedRef<SWidget> UFableActionBarWidget::RebuildWidget()
{
	if (WidgetTree == nullptr)
	{
		return Super::RebuildWidget();
	}

	SlotAddressMap.Reset();
	SlotWidgetsByIndex.Reset();

	UBorder* RootBorder = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("ActionBarBorder"));
	RootBorder->SetBrushColor(UiBarColor);
	RootBorder->SetPadding(FMargin(8.0f));
	WidgetTree->RootWidget = RootBorder;

	UHorizontalBox* RootRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("ActionBarRootRow"));
	RootBorder->SetContent(RootRow);

	UUniformGridPanel* SlotsGrid = WidgetTree->ConstructWidget<UUniformGridPanel>(UUniformGridPanel::StaticClass(), TEXT("SlotsGrid"));
	if (UHorizontalBoxSlot* GridSlot = RootRow->AddChildToHorizontalBox(SlotsGrid))
	{
		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		GridSlot->SetSize(FillSize);
	}

	const int32 GridRows = FMath::Max(1, BarData.Columns > 0 ? VisibleSlots.Num() / BarData.Columns : 1);
	const int32 GridColumns = FMath::Max(1, BarData.Columns);
	for (int32 RowIndex = 0; RowIndex < GridRows; ++RowIndex)
	{
		for (int32 ColumnIndex = 0; ColumnIndex < GridColumns; ++ColumnIndex)
		{
			// Reverse row mapping so expanded rows are added visually above existing rows.
			const int32 SourceRow = GridRows - 1 - RowIndex;
			const int32 SlotIndex = SourceRow * GridColumns + ColumnIndex;
			if (!VisibleSlots.IsValidIndex(SlotIndex))
			{
				continue;
			}

			const FFableActionSlotData& SlotData = VisibleSlots[SlotIndex];
			const FName SlotId = MakeActionSlotId(BarData.BarId, SlotIndex);

			UFableInventorySlotWidget* SlotWidget = WidgetTree->ConstructWidget<UFableInventorySlotWidget>(UFableInventorySlotWidget::StaticClass());
			SlotWidget->SetVisibility(ESlateVisibility::Visible);
			SlotWidget->SetIsEnabled(true);
			SlotWidget->InitializeSlot(SlotId, TEXT(""), false);
			SlotWidget->SetItemData(SlotData.EntryId, SlotData.EntryLabel.IsEmpty() ? ShortToken(SlotData.EntryId) : SlotData.EntryLabel);
			SlotWidget->OnItemDrop.AddDynamic(this, &UFableActionBarWidget::HandleSlotDrop);
			SlotWidget->OnSlotClicked.AddDynamic(this, &UFableActionBarWidget::HandleSlotClicked);

			USizeBox* SlotSizeBox = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
			SlotSizeBox->SetWidthOverride(60.0f);
			SlotSizeBox->SetHeightOverride(60.0f);
			SlotSizeBox->SetContent(SlotWidget);

			if (UUniformGridSlot* GridSlot = SlotsGrid->AddChildToUniformGrid(SlotSizeBox, RowIndex, ColumnIndex))
			{
				GridSlot->SetHorizontalAlignment(HAlign_Fill);
				GridSlot->SetVerticalAlignment(VAlign_Fill);
			}

			SlotAddressMap.Add(SlotId, SlotIndex);
			SlotWidgetsByIndex.Add(SlotIndex, SlotWidget);
		}
	}

	UVerticalBox* ControlsColumn = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("ControlsColumn"));
	if (UHorizontalBoxSlot* ControlsSlot = RootRow->AddChildToHorizontalBox(ControlsColumn))
	{
		ControlsSlot->SetPadding(FMargin(8.0f, 0.0f, 0.0f, 0.0f));
		ControlsSlot->SetHorizontalAlignment(HAlign_Fill);
		ControlsSlot->SetVerticalAlignment(VAlign_Fill);
	}

	auto AddSmallControlButton = [&](const TCHAR* WidgetName, const TCHAR* ActionName, const TCHAR* Label, const FLinearColor& ButtonColor, const FString& MultiLineLabel = FString())
	{
		UFableActionButton* Button = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass(), WidgetName);
		Button->InitializeAction(ActionName);
		Button->SetBackgroundColor(ButtonColor);

		UTextBlock* Text = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		Text->SetText(FText::FromString(MultiLineLabel.IsEmpty() ? FString(Label) : MultiLineLabel));
		Text->SetColorAndOpacity(FSlateColor(UiTextColor));
		Text->SetJustification(ETextJustify::Center);
		FSlateFontInfo FontInfo = Text->GetFont();
		FontInfo.Size = 10;
		Text->SetFont(FontInfo);
		Button->AddChild(Text);

		if (UButtonSlot* TextSlot = Cast<UButtonSlot>(Text->Slot))
		{
			TextSlot->SetHorizontalAlignment(HAlign_Center);
			TextSlot->SetVerticalAlignment(VAlign_Center);
			TextSlot->SetPadding(FMargin(1.0f));
		}

		USizeBox* SizeBox = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
		SizeBox->SetWidthOverride(UiSmallControlSize.X);
		SizeBox->SetHeightOverride(UiSmallControlSize.Y);
		SizeBox->SetContent(Button);
		return TPair<UFableActionButton*, USizeBox*>(Button, SizeBox);
	};

	if (bCanExpand)
	{
		if (BarData.bIsMainBar)
		{
			USpacer* TopSpacer = WidgetTree->ConstructWidget<USpacer>(USpacer::StaticClass());
			if (UVerticalBoxSlot* TopSpacerSlot = ControlsColumn->AddChildToVerticalBox(TopSpacer))
			{
				FSlateChildSize FillSize;
				FillSize.SizeRule = ESlateSizeRule::Fill;
				FillSize.Value = 1.0f;
				TopSpacerSlot->SetSize(FillSize);
			}
		}

		TPair<UFableActionButton*, USizeBox*> ExpandControl = AddSmallControlButton(
			TEXT("ExpandButton"),
			TEXT("expand_toggle"),
			TEXT(""),
			UiButtonColor,
			bShowExpanded ? TEXT("v") : TEXT("^"));
		UFableActionButton* ExpandButton = ExpandControl.Key;
		ExpandButton->OnActionClicked.AddDynamic(this, &UFableActionBarWidget::HandleExpandClicked);
		if (UVerticalBoxSlot* ExpandSlot = ControlsColumn->AddChildToVerticalBox(ExpandControl.Value))
		{
			ExpandSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 4.0f));
		}

		if (BarData.bIsMainBar)
		{
			USpacer* BottomSpacer = WidgetTree->ConstructWidget<USpacer>(USpacer::StaticClass());
			if (UVerticalBoxSlot* BottomSpacerSlot = ControlsColumn->AddChildToVerticalBox(BottomSpacer))
			{
				FSlateChildSize FillSize;
				FillSize.SizeRule = ESlateSizeRule::Fill;
				FillSize.Value = 1.0f;
				BottomSpacerSlot->SetSize(FillSize);
			}
		}
	}

	if (!BarData.bIsMainBar)
	{
		if (BarData.Orientation == EFableActionBarOrientation::Vertical)
		{
			USpacer* TopSpacer = WidgetTree->ConstructWidget<USpacer>(USpacer::StaticClass());
			if (UVerticalBoxSlot* TopSpacerSlot = ControlsColumn->AddChildToVerticalBox(TopSpacer))
			{
				FSlateChildSize FillSize;
				FillSize.SizeRule = ESlateSizeRule::Fill;
				FillSize.Value = 1.0f;
				TopSpacerSlot->SetSize(FillSize);
			}
		}

		TPair<UFableActionButton*, USizeBox*> MoveControl = AddSmallControlButton(
			TEXT("MoveButton"),
			TEXT("move_bar"),
			TEXT(""),
			UiDragHandleColor,
			BarData.Orientation == EFableActionBarOrientation::Horizontal ? TEXT(".\n.\n.") : TEXT("..."));
		UFableActionButton* MoveButton = MoveControl.Key;
		MoveButton->OnPressed.AddDynamic(this, &UFableActionBarWidget::HandleMovePressed);
		MoveButton->OnReleased.AddDynamic(this, &UFableActionBarWidget::HandleMoveReleased);
		if (UVerticalBoxSlot* MoveSlot = ControlsColumn->AddChildToVerticalBox(MoveControl.Value))
		{
			MoveSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 4.0f));
		}

		TPair<UFableActionButton*, USizeBox*> RemoveControl = AddSmallControlButton(
			TEXT("RemoveButton"),
			TEXT("remove_bar"),
			TEXT("X"),
			UiButtonColor);
		UFableActionButton* RemoveButton = RemoveControl.Key;
		RemoveButton->OnActionClicked.AddDynamic(this, &UFableActionBarWidget::HandleRemoveClicked);
		ControlsColumn->AddChildToVerticalBox(RemoveControl.Value);
	}

	return Super::RebuildWidget();
}

void UFableActionBarWidget::NativeConstruct()
{
	Super::NativeConstruct();
}

void UFableActionBarWidget::NativeTick(const FGeometry& MyGeometry, float InDeltaTime)
{
	Super::NativeTick(MyGeometry, InDeltaTime);
	(void)InDeltaTime;
	(void)MyGeometry;

	if (!bDragging)
	{
		return;
	}

	if (UCanvasPanelSlot* CanvasSlot = Cast<UCanvasPanelSlot>(Slot))
	{
		const FVector2D MousePosition = UWidgetLayoutLibrary::GetMousePositionOnViewport(this);
		FVector2D NewPosition = MousePosition - DragOffset;
		FVector2D ViewportSize = FVector2D(1920.0f, 1080.0f);
		if (GetWorld() != nullptr && GetWorld()->GetGameViewport() != nullptr)
		{
			GetWorld()->GetGameViewport()->GetViewportSize(ViewportSize);
		}

		const FVector2D WidgetSize = CanvasSlot->GetSize();
		NewPosition.X = FMath::Clamp(NewPosition.X, 0.0f, FMath::Max(0.0f, ViewportSize.X - WidgetSize.X));
		NewPosition.Y = FMath::Clamp(NewPosition.Y, 0.0f, FMath::Max(0.0f, ViewportSize.Y - WidgetSize.Y));
		CanvasSlot->SetPosition(NewPosition);
	}
}

bool UFableActionBarWidget::NativeOnDragOver(const FGeometry& InGeometry, const FDragDropEvent& InDragDropEvent, UDragDropOperation* InOperation)
{
	const UFableInventoryDragDropOperation* DragOperation = Cast<UFableInventoryDragDropOperation>(InOperation);
	if (DragOperation == nullptr || DragOperation->SourceSlotId == NAME_None)
	{
		return Super::NativeOnDragOver(InGeometry, InDragDropEvent, InOperation);
	}

	int32 SlotIndex = INDEX_NONE;
	if (ResolveSlotIndexFromDropPosition(InGeometry, InDragDropEvent, SlotIndex))
	{
		UE_LOG(LogFableForge, Verbose, TEXT("ActionBar drag over bar=%s slotIndex=%d payload=%s"),
			*BarData.BarId.ToString(EGuidFormats::Digits), SlotIndex, *DragOperation->PayloadId);
		return true;
	}

	return Super::NativeOnDragOver(InGeometry, InDragDropEvent, InOperation);
}

bool UFableActionBarWidget::NativeOnDrop(const FGeometry& InGeometry, const FDragDropEvent& InDragDropEvent, UDragDropOperation* InOperation)
{
	const UFableInventoryDragDropOperation* DragOperation = Cast<UFableInventoryDragDropOperation>(InOperation);
	if (DragOperation == nullptr || DragOperation->SourceSlotId == NAME_None)
	{
		return Super::NativeOnDrop(InGeometry, InDragDropEvent, InOperation);
	}

	int32 SlotIndex = INDEX_NONE;
	if (!ResolveSlotIndexFromDropPosition(InGeometry, InDragDropEvent, SlotIndex))
	{
		return Super::NativeOnDrop(InGeometry, InDragDropEvent, InOperation);
	}

	UE_LOG(LogFableForge, Log, TEXT("ActionBar root drop bar=%s slotIndex=%d from=%s payload=%s label=%s"),
		*BarData.BarId.ToString(EGuidFormats::Digits),
		SlotIndex,
		*DragOperation->SourceSlotId.ToString(),
		*DragOperation->PayloadId,
		*DragOperation->PayloadLabel);

	OnActionSlotDropped.Broadcast(BarData.BarId, SlotIndex, DragOperation->SourceSlotId, DragOperation->PayloadId, DragOperation->PayloadLabel);
	return true;
}

void UFableActionBarWidget::InitializeBar(const FFableActionBarData& InBarData, const TArray<FFableActionSlotData>& InVisibleSlots, bool bInCanExpand, bool bInShowExpanded)
{
	BarData = InBarData;
	VisibleSlots = InVisibleSlots;
	bCanExpand = bInCanExpand;
	bShowExpanded = bInShowExpanded;
	RebuildWidget();
}

FGuid UFableActionBarWidget::GetBarId() const
{
	return BarData.BarId;
}

bool UFableActionBarWidget::TryResolveSlotIndexFromScreenPosition(const FVector2D& ScreenPosition, int32& OutSlotIndex) const
{
	OutSlotIndex = INDEX_NONE;
	if (!IsVisible())
	{
		return false;
	}

	const FGeometry& Geometry = GetCachedGeometry();
	if (!Geometry.IsUnderLocation(ScreenPosition))
	{
		return false;
	}

	const int32 Columns = FMath::Max(1, BarData.Columns);
	if (VisibleSlots.Num() == 0)
	{
		return false;
	}

	const int32 Rows = FMath::Max(1, FMath::CeilToInt(static_cast<float>(VisibleSlots.Num()) / static_cast<float>(Columns)));
	const FVector2D Local = Geometry.AbsoluteToLocal(ScreenPosition);

	constexpr float RootPadding = 8.0f;
	constexpr float CellSize = 60.0f;
	const float GridWidth = Columns * CellSize;
	const float GridHeight = Rows * CellSize;
	const float GridX = RootPadding;
	const float GridY = RootPadding;
	if (Local.X < GridX || Local.Y < GridY || Local.X >= GridX + GridWidth || Local.Y >= GridY + GridHeight)
	{
		return false;
	}

	const int32 VisualColumn = FMath::Clamp(FMath::FloorToInt((Local.X - GridX) / CellSize), 0, Columns - 1);
	const int32 VisualRow = FMath::Clamp(FMath::FloorToInt((Local.Y - GridY) / CellSize), 0, Rows - 1);
	const int32 SourceRow = Rows - 1 - VisualRow;
	const int32 CandidateIndex = SourceRow * Columns + VisualColumn;
	if (!VisibleSlots.IsValidIndex(CandidateIndex))
	{
		return false;
	}

	OutSlotIndex = CandidateIndex;
	return true;
}

void UFableActionBarWidget::SetSlotCooldownRemaining(int32 SlotIndex, float RemainingSeconds)
{
	if (TObjectPtr<UFableInventorySlotWidget>* SlotWidget = SlotWidgetsByIndex.Find(SlotIndex))
	{
		if (SlotWidget->Get() != nullptr)
		{
			SlotWidget->Get()->SetCooldownRemaining(RemainingSeconds);
		}
	}
}

void UFableActionBarWidget::PlaySlotUseFeedback(int32 SlotIndex)
{
	if (TObjectPtr<UFableInventorySlotWidget>* SlotWidget = SlotWidgetsByIndex.Find(SlotIndex))
	{
		if (SlotWidget->Get() != nullptr)
		{
			SlotWidget->Get()->PlayUseFeedback();
		}
	}
}

void UFableActionBarWidget::HandleMovePressed()
{
	if (BarData.bIsMainBar)
	{
		return;
	}

	if (UCanvasPanelSlot* CanvasSlot = Cast<UCanvasPanelSlot>(Slot))
	{
		const FVector2D MousePosition = UWidgetLayoutLibrary::GetMousePositionOnViewport(this);
		DragOffset = MousePosition - CanvasSlot->GetPosition();
		bDragging = true;
	}
}

void UFableActionBarWidget::HandleMoveReleased()
{
	if (BarData.bIsMainBar)
	{
		return;
	}

	bDragging = false;
	if (UCanvasPanelSlot* CanvasSlot = Cast<UCanvasPanelSlot>(Slot))
	{
		OnBarMoved.Broadcast(BarData.BarId, CanvasSlot->GetPosition());
	}
}

void UFableActionBarWidget::HandleExpandClicked(FName ActionId)
{
	(void)ActionId;
	OnExpandToggled.Broadcast(BarData.BarId);
}

void UFableActionBarWidget::HandleRemoveClicked(FName ActionId)
{
	(void)ActionId;
	OnRemoveRequested.Broadcast(BarData.BarId);
}

void UFableActionBarWidget::HandleSlotDrop(FName FromSlotId, FName ToSlotId, const FString& PayloadId, const FString& PayloadLabel)
{
	if (const int32* SlotIndex = SlotAddressMap.Find(ToSlotId))
	{
		UE_LOG(LogFableForge, Log, TEXT("ActionBar slot drop bar=%s toSlot=%s resolvedIndex=%d from=%s payload=%s label=%s"),
			*BarData.BarId.ToString(EGuidFormats::Digits),
			*ToSlotId.ToString(),
			*SlotIndex,
			*FromSlotId.ToString(),
			*PayloadId,
			*PayloadLabel);
		OnActionSlotDropped.Broadcast(BarData.BarId, *SlotIndex, FromSlotId, PayloadId, PayloadLabel);
		return;
	}

	UE_LOG(LogFableForge, Warning, TEXT("ActionBar slot drop target not found bar=%s toSlot=%s from=%s payload=%s"),
		*BarData.BarId.ToString(EGuidFormats::Digits),
		*ToSlotId.ToString(),
		*FromSlotId.ToString(),
		*PayloadId);
}

void UFableActionBarWidget::HandleSlotClicked(FName SlotId, const FString& PayloadId)
{
	if (PayloadId.IsEmpty())
	{
		UE_LOG(LogFableForge, Warning, TEXT("ActionBar slot click ignored (empty payload) bar=%s slotId=%s"),
			*BarData.BarId.ToString(EGuidFormats::Digits), *SlotId.ToString());
		return;
	}

	if (const int32* SlotIndex = SlotAddressMap.Find(SlotId))
	{
		UE_LOG(LogFableForge, Log, TEXT("ActionBar slot click bar=%s slot=%d payload=%s"),
			*BarData.BarId.ToString(EGuidFormats::Digits), *SlotIndex, *PayloadId);
		OnActionSlotClicked.Broadcast(BarData.BarId, *SlotIndex, PayloadId);
		return;
	}

	UE_LOG(LogFableForge, Warning, TEXT("ActionBar slot click could not resolve slotId bar=%s slotId=%s payload=%s"),
		*BarData.BarId.ToString(EGuidFormats::Digits), *SlotId.ToString(), *PayloadId);
}

bool UFableActionBarWidget::ResolveSlotIndexFromDropPosition(const FGeometry& InGeometry, const FDragDropEvent& InDragDropEvent, int32& OutSlotIndex) const
{
	OutSlotIndex = INDEX_NONE;

	const int32 Columns = FMath::Max(1, BarData.Columns);
	if (VisibleSlots.Num() == 0)
	{
		return false;
	}

	const int32 Rows = FMath::Max(1, FMath::CeilToInt(static_cast<float>(VisibleSlots.Num()) / static_cast<float>(Columns)));
	const FVector2D Local = InGeometry.AbsoluteToLocal(InDragDropEvent.GetScreenSpacePosition());

	constexpr float RootPadding = 8.0f;
	constexpr float SlotSize = 60.0f;
	constexpr float CellSize = 60.0f;
	const float GridWidth = Columns * CellSize;
	const float GridHeight = Rows * CellSize;

	const float GridX = RootPadding;
	const float GridY = RootPadding;
	if (Local.X < GridX || Local.Y < GridY || Local.X >= GridX + GridWidth || Local.Y >= GridY + GridHeight)
	{
		return false;
	}

	const int32 VisualColumn = FMath::Clamp(FMath::FloorToInt((Local.X - GridX) / CellSize), 0, Columns - 1);
	const int32 VisualRow = FMath::Clamp(FMath::FloorToInt((Local.Y - GridY) / CellSize), 0, Rows - 1);
	const int32 SourceRow = Rows - 1 - VisualRow;
	const int32 CandidateIndex = SourceRow * Columns + VisualColumn;
	if (!VisibleSlots.IsValidIndex(CandidateIndex))
	{
		return false;
	}

	OutSlotIndex = CandidateIndex;
	return true;
}
