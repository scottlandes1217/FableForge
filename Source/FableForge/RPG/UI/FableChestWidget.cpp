#include "RPG/UI/FableChestWidget.h"

#include "Components/Border.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Blueprint/WidgetTree.h"
#include "FableForgePlayerController.h"
#include "Interaction/FFChestInteractable.h"
#include "RPG/UI/FableActionButton.h"

TSharedRef<SWidget> UFableChestWidget::RebuildWidget()
{
	const TSharedRef<SWidget> Rebuilt = Super::RebuildWidget();
	RebuildContent();
	return Rebuilt;
}

void UFableChestWidget::OpenForChest(AFFChestInteractable* InChest, AFableForgePlayerController* InOwningController)
{
	ActiveChest = InChest;
	CachedController = InOwningController;

	if (!IsInViewport())
	{
		AddToViewport(40);
	}

	SetVisibility(ESlateVisibility::Visible);
	RefreshItemRows();
}

void UFableChestWidget::CloseChest()
{
	ActiveChest = nullptr;
	CachedController = nullptr;
	SetVisibility(ESlateVisibility::Collapsed);
}

bool UFableChestWidget::IsChestOpen() const
{
	return ActiveChest != nullptr && GetVisibility() != ESlateVisibility::Collapsed;
}

void UFableChestWidget::RebuildContent()
{
	if (WidgetTree == nullptr)
	{
		return;
	}

	WidgetTree->RootWidget = nullptr;

	UBorder* Panel = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("ChestPanel"));
	Panel->SetBrushColor(FLinearColor(0.05f, 0.05f, 0.05f, 0.95f));
	Panel->SetPadding(FMargin(16.0f));
	WidgetTree->RootWidget = Panel;

	RootContent = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("ChestRootContent"));
	Panel->SetContent(RootContent);

	HeaderText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("ChestHeader"));
	HeaderText->SetText(FText::FromString(TEXT("Chest")));
	HeaderText->SetFont(FSlateFontInfo(TEXT("/Engine/EngineFonts/RobotoBold"), 20));
	RootContent->AddChildToVerticalBox(HeaderText);

	ItemListBox = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("ItemListBox"));
	if (UVerticalBoxSlot* ItemListSlot = RootContent->AddChildToVerticalBox(ItemListBox))
	{
		ItemListSlot->SetPadding(FMargin(0.0f, 12.0f, 0.0f, 12.0f));
	}

	UHorizontalBox* ActionRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("ActionRow"));
	RootContent->AddChildToVerticalBox(ActionRow);

	UFableActionButton* TakeAllButton = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass(), TEXT("TakeAllButton"));
	TakeAllButton->InitializeAction(TEXT("take_all"));
	TakeAllButton->OnActionClicked.AddDynamic(this, &UFableChestWidget::HandleTakeAllAction);
	if (UHorizontalBoxSlot* TakeAllSlot = ActionRow->AddChildToHorizontalBox(TakeAllButton))
	{
		TakeAllSlot->SetPadding(FMargin(0.0f, 0.0f, 8.0f, 0.0f));
	}

	UTextBlock* TakeAllLabel = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("TakeAllLabel"));
	TakeAllLabel->SetText(FText::FromString(TEXT("Take All")));
	TakeAllButton->AddChild(TakeAllLabel);

	UFableActionButton* CloseButton = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass(), TEXT("CloseButton"));
	CloseButton->InitializeAction(TEXT("close"));
	CloseButton->OnActionClicked.AddDynamic(this, &UFableChestWidget::HandleCloseAction);
	ActionRow->AddChildToHorizontalBox(CloseButton);

	UTextBlock* CloseLabel = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("CloseLabel"));
	CloseLabel->SetText(FText::FromString(TEXT("Close")));
	CloseButton->AddChild(CloseLabel);

	SetVisibility(ESlateVisibility::Collapsed);
}

void UFableChestWidget::RefreshItemRows()
{
	if (ItemListBox == nullptr)
	{
		return;
	}

	ItemListBox->ClearChildren();

	if (ActiveChest == nullptr)
	{
		if (HeaderText != nullptr)
		{
			HeaderText->SetText(FText::FromString(TEXT("Chest")));
		}
		return;
	}

	const TArray<FFChestItemEntry>& Items = ActiveChest->GetChestItems();
	if (HeaderText != nullptr)
	{
		HeaderText->SetText(FText::FromString(FString::Printf(TEXT("Chest (%d item types)"), Items.Num())));
	}

	if (Items.IsEmpty())
	{
		UTextBlock* EmptyText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		EmptyText->SetText(FText::FromString(TEXT("Empty")));
		ItemListBox->AddChildToVerticalBox(EmptyText);
		return;
	}

	for (int32 Index = 0; Index < Items.Num(); ++Index)
	{
		const FFChestItemEntry& ItemEntry = Items[Index];

		UHorizontalBox* Row = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass());
		if (UVerticalBoxSlot* RowSlot = ItemListBox->AddChildToVerticalBox(Row))
		{
			RowSlot->SetPadding(FMargin(0.0f, 2.0f));
		}

		UTextBlock* ItemLabel = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		ItemLabel->SetText(FText::FromString(FString::Printf(TEXT("%s x%d"), *ItemEntry.ItemId, ItemEntry.Quantity)));
		if (UHorizontalBoxSlot* LabelSlot = Row->AddChildToHorizontalBox(ItemLabel))
		{
			const FSlateChildSize FillSize(ESlateSizeRule::Fill);
			LabelSlot->SetSize(FillSize);
			LabelSlot->SetHorizontalAlignment(HAlign_Left);
			LabelSlot->SetVerticalAlignment(VAlign_Center);
		}

		UFableActionButton* TakeButton = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass());
		TakeButton->InitializeAction(FName(*FString::Printf(TEXT("take_%d"), Index)));
		TakeButton->OnActionClicked.AddDynamic(this, &UFableChestWidget::HandleTakeAction);
		Row->AddChildToHorizontalBox(TakeButton);

		UTextBlock* TakeLabel = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		TakeLabel->SetText(FText::FromString(TEXT("Take")));
		TakeButton->AddChild(TakeLabel);
	}
}

void UFableChestWidget::HandleTakeAction(FName ActionId)
{
	if (ActiveChest == nullptr || CachedController == nullptr)
	{
		return;
	}

	FString ActionString = ActionId.ToString();
	ActionString.RemoveFromStart(TEXT("take_"));

	const int32 ItemIndex = FCString::Atoi(*ActionString);
	ActiveChest->TakeOneAtIndex(ItemIndex, CachedController);
	RefreshItemRows();
}

void UFableChestWidget::HandleTakeAllAction(FName ActionId)
{
	if (ActiveChest == nullptr || CachedController == nullptr)
	{
		return;
	}

	ActiveChest->TakeAll(CachedController);
	RefreshItemRows();
}

void UFableChestWidget::HandleCloseAction(FName ActionId)
{
	if (CachedController != nullptr)
	{
		CachedController->CloseChest();
	}
	else
	{
		CloseChest();
	}
}
