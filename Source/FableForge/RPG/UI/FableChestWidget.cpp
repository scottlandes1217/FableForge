#include "RPG/UI/FableChestWidget.h"

#include "Components/Border.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/WrapBox.h"
#include "Components/WrapBoxSlot.h"
#include "Blueprint/WidgetTree.h"
#include "FableForgePlayerController.h"
#include "Interaction/FFChestInteractable.h"
#include "Components/Image.h"
#include "Components/SizeBox.h"
#include "RPG/UI/FableActionButton.h"
#include "Components/ButtonSlot.h"
#include "Engine/DataTable.h"
#include "Engine/Texture2D.h"
#include "RPG/Data/FableItemDefinitionTableRow.h"
#include "Styling/SlateBrush.h"
#include "FableForge.h"

namespace
{
	const TCHAR* ItemsDataTablePath = TEXT("/Game/Data/DT_Items.DT_Items");
	const TCHAR* WeaponsDataTablePath = TEXT("/Game/Data/DT_Weapons.DT_Weapons");
	const TCHAR* ArmorDataTablePath = TEXT("/Game/Data/DT_Armor.DT_Armor");
	const TCHAR* WhiteSquareTexturePath = TEXT("/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture");
}

TSharedRef<SWidget> UFableChestWidget::RebuildWidget()
{
	RebuildContent();
	return Super::RebuildWidget();
}

void UFableChestWidget::OpenForChest(AFFChestInteractable* InChest, AFableForgePlayerController* InOwningController)
{
	ActiveChest = InChest;
	CachedController = InOwningController;

	if (WidgetTree == nullptr || WidgetTree->RootWidget == nullptr || ItemGrid == nullptr)
	{
		RebuildContent();
	}

	if (!IsInViewport())
	{
		AddToViewport(40);
	}

	SetVisibility(ESlateVisibility::Visible);
	SetAnchorsInViewport(FAnchors(0.0f, 0.0f, 1.0f, 1.0f));
	SetAlignmentInViewport(FVector2D(0.0f, 0.0f));
	SetPositionInViewport(FVector2D::ZeroVector, false);
	SetDesiredSizeInViewport(FVector2D(1920.0f, 1080.0f));
	if (PanelCanvasSlot != nullptr)
	{
		PanelCanvasSlot->SetAnchors(FAnchors(0.5f, 0.5f));
		PanelCanvasSlot->SetAlignment(FVector2D(0.5f, 0.5f));
		PanelCanvasSlot->SetPosition(FVector2D::ZeroVector);
		PanelCanvasSlot->SetSize(FVector2D(560.0f, 320.0f));
		PanelCanvasSlot->SetAutoSize(false);
	}
	RefreshItemRows();

	UE_LOG(LogFableForge, Log, TEXT("Chest UI opened. ActiveChest=%s Visibility=%d"),
		*GetNameSafe(ActiveChest),
		static_cast<int32>(GetVisibility()));
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

	RootCanvas = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("ChestRootCanvas"));
	WidgetTree->RootWidget = RootCanvas;

	UBorder* Panel = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("ChestPanel"));
	if (UTexture2D* WhiteSquare = LoadObject<UTexture2D>(nullptr, WhiteSquareTexturePath))
	{
		Panel->SetBrushFromTexture(WhiteSquare);
	}
	Panel->SetBrushColor(FLinearColor(0.05f, 0.05f, 0.05f, 1.0f));
	Panel->SetPadding(FMargin(12.0f));
	if (UCanvasPanelSlot* CanvasSlot = RootCanvas->AddChildToCanvas(Panel))
	{
		CanvasSlot->SetAutoSize(false);
		CanvasSlot->SetAnchors(FAnchors(0.5f, 0.5f));
		CanvasSlot->SetAlignment(FVector2D(0.5f, 0.5f));
		CanvasSlot->SetPosition(FVector2D::ZeroVector);
		CanvasSlot->SetSize(FVector2D(560.0f, 320.0f));
		PanelCanvasSlot = CanvasSlot;
	}

	RootContent = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("ChestRootContent"));
	Panel->SetContent(RootContent);

	HeaderText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("ChestHeader"));
	HeaderText->SetText(FText::FromString(TEXT("Chest")));
	HeaderText->SetJustification(ETextJustify::Center);
	{
		FSlateFontInfo HeaderFont = HeaderText->GetFont();
		HeaderFont.Size = 20;
		HeaderText->SetFont(HeaderFont);
	}
	if (UVerticalBoxSlot* HeaderSlot = RootContent->AddChildToVerticalBox(HeaderText))
	{
		HeaderSlot->SetHorizontalAlignment(HAlign_Fill);
		HeaderSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 4.0f));
	}

	ItemGrid = WidgetTree->ConstructWidget<UWrapBox>(UWrapBox::StaticClass(), TEXT("ItemGrid"));
	ItemGrid->SetInnerSlotPadding(FVector2D(0.0f, 0.0f));
	ItemGrid->SetHorizontalAlignment(HAlign_Left);
	ItemGrid->SetExplicitWrapSize(true);
	ItemGrid->SetWrapSize(520.0f);
	if (UVerticalBoxSlot* ItemListSlot = RootContent->AddChildToVerticalBox(ItemGrid))
	{
		ItemListSlot->SetPadding(FMargin(0.0f, 6.0f, 0.0f, 6.0f));
		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		ItemListSlot->SetSize(FillSize);
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
	if (ItemGrid == nullptr)
	{
		return;
	}

	ItemGrid->ClearChildren();

	if (ActiveChest == nullptr)
	{
		if (HeaderText != nullptr)
		{
			HeaderText->SetText(FText::FromString(TEXT("Chest")));
		}
		return;
	}

	EnsureItemDefinitionsLoaded();

	const TArray<FFChestItemEntry>& Items = ActiveChest->GetChestItems();
	if (HeaderText != nullptr)
	{
		HeaderText->SetText(FText::FromString(ActiveChest->GetChestDisplayName()));
	}

	if (Items.IsEmpty())
	{
		UTextBlock* EmptyText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		EmptyText->SetText(FText::FromString(TEXT("Empty")));
		ItemGrid->AddChildToWrapBox(EmptyText);
		return;
	}

	for (int32 Index = 0; Index < Items.Num(); ++Index)
	{
		const FFChestItemEntry& ItemEntry = Items[Index];

		UFableActionButton* TileButton = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass());
		TileButton->InitializeAction(FName(*FString::Printf(TEXT("take_%d"), Index)));
		TileButton->OnActionClicked.AddDynamic(this, &UFableChestWidget::HandleTakeAction);
		TileButton->SetBackgroundColor(FLinearColor(0.0f, 0.0f, 0.0f, 0.0f));
		TileButton->SetColorAndOpacity(FLinearColor::White);
		{
			FButtonStyle TileStyle = TileButton->GetStyle();
			TileStyle.Normal.DrawAs = ESlateBrushDrawType::NoDrawType;
			TileStyle.Hovered.DrawAs = ESlateBrushDrawType::NoDrawType;
			TileStyle.Pressed.DrawAs = ESlateBrushDrawType::NoDrawType;
			TileStyle.Disabled.DrawAs = ESlateBrushDrawType::NoDrawType;
			TileStyle.NormalPadding = FMargin(0.0f);
			TileStyle.PressedPadding = FMargin(0.0f);
			TileButton->SetStyle(TileStyle);
		}

		USizeBox* TileSizeBox = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
		TileSizeBox->SetWidthOverride(68.0f);
		TileSizeBox->SetHeightOverride(68.0f);

		UBorder* TileBorder = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass());
		TileBorder->SetBrushColor(FLinearColor(0.13f, 0.13f, 0.13f, 0.98f));
		TileBorder->SetPadding(FMargin(4.0f));
		TileSizeBox->SetContent(TileBorder);

		UVerticalBox* TileContent = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass());
		TileBorder->SetContent(TileContent);

		if (UTexture2D* ItemIcon = GetIconForItem(ItemEntry.ItemId))
		{
			USizeBox* IconSizeBox = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
			IconSizeBox->SetWidthOverride(24.0f);
			IconSizeBox->SetHeightOverride(24.0f);
			if (UVerticalBoxSlot* IconSlot = TileContent->AddChildToVerticalBox(IconSizeBox))
			{
				IconSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 2.0f));
				IconSlot->SetHorizontalAlignment(HAlign_Center);
			}

			UImage* IconImage = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass());
			FSlateBrush IconBrush;
			IconBrush.SetResourceObject(ItemIcon);
			IconBrush.ImageSize = FVector2D(24.0f, 24.0f);
			IconImage->SetBrush(IconBrush);
			IconSizeBox->SetContent(IconImage);
		}
		else
		{
			UTextBlock* TokenText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
			TokenText->SetText(FText::FromString(GetDisplayNameForItem(ItemEntry.ItemId).Left(1).ToUpper()));
			TokenText->SetJustification(ETextJustify::Center);
			if (UVerticalBoxSlot* TokenSlot = TileContent->AddChildToVerticalBox(TokenText))
			{
				TokenSlot->SetHorizontalAlignment(HAlign_Center);
				TokenSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 2.0f));
			}
		}

		UTextBlock* ItemLabel = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		ItemLabel->SetText(FText::FromString(FString::Printf(TEXT("x%d"), ItemEntry.Quantity)));
		ItemLabel->SetJustification(ETextJustify::Center);
		ItemLabel->SetAutoWrapText(false);
		{
			FSlateFontInfo FontInfo = ItemLabel->GetFont();
			FontInfo.Size = 12;
			ItemLabel->SetFont(FontInfo);
		}
		if (UVerticalBoxSlot* LabelSlot = TileContent->AddChildToVerticalBox(ItemLabel))
		{
			LabelSlot->SetHorizontalAlignment(HAlign_Center);
			LabelSlot->SetVerticalAlignment(VAlign_Bottom);
		}

		TileButton->AddChild(TileSizeBox);
		if (UButtonSlot* TileButtonSlot = Cast<UButtonSlot>(TileSizeBox->Slot))
		{
			TileButtonSlot->SetPadding(FMargin(0.0f));
			TileButtonSlot->SetHorizontalAlignment(HAlign_Fill);
			TileButtonSlot->SetVerticalAlignment(VAlign_Fill);
		}
		if (UWrapBoxSlot* GridSlot = ItemGrid->AddChildToWrapBox(TileButton))
		{
			GridSlot->SetPadding(FMargin(0.0f));
			GridSlot->SetFillEmptySpace(false);
			GridSlot->SetFillSpanWhenLessThan(0.0f);
			GridSlot->SetHorizontalAlignment(HAlign_Left);
			GridSlot->SetVerticalAlignment(VAlign_Top);
		}
	}
}

void UFableChestWidget::EnsureItemDefinitionsLoaded()
{
	if (bItemDefinitionsLoaded)
	{
		return;
	}

	bItemDefinitionsLoaded = true;
	ItemDefinitions.Reset();
	IconTextureCache.Reset();

	auto LoadDefinitionsFromTable = [&](const TCHAR* TablePath, const TCHAR* TableLabel) -> bool
	{
		UDataTable* ItemDefinitionsTable = LoadObject<UDataTable>(nullptr, TablePath);
		if (ItemDefinitionsTable == nullptr)
		{
			UE_LOG(LogFableForge, Warning, TEXT("%s DataTable not found at '%s'."), TableLabel, TablePath);
			return false;
		}

		const FString ContextString = FString::Printf(TEXT("UFableChestWidget::EnsureItemDefinitionsLoaded(%s)"), TableLabel);
		TArray<FFableItemDefinitionTableRow*> Rows;
		ItemDefinitionsTable->GetAllRows(ContextString, Rows);

		for (const FFableItemDefinitionTableRow* Row : Rows)
		{
			if (Row == nullptr || Row->ItemId.IsEmpty())
			{
				continue;
			}

			FFableChestUiItemDefinition& Definition = ItemDefinitions.FindOrAdd(Row->ItemId);
			Definition.DisplayName = !Row->DisplayName.IsEmpty() ? Row->DisplayName : Row->ItemId;
			Definition.IconAssetPath = Row->IconTexture.ToSoftObjectPath().ToString();
		}

		return true;
	};

	const bool bLoadedAny =
		LoadDefinitionsFromTable(ItemsDataTablePath, TEXT("Items")) |
		LoadDefinitionsFromTable(WeaponsDataTablePath, TEXT("Weapons")) |
		LoadDefinitionsFromTable(ArmorDataTablePath, TEXT("Armor"));

	if (!bLoadedAny)
	{
		UE_LOG(LogFableForge, Warning, TEXT("No item definition DataTables were loaded. Expected '%s', '%s', '%s'."),
			ItemsDataTablePath, WeaponsDataTablePath, ArmorDataTablePath);
	}
}

FString UFableChestWidget::GetDisplayNameForItem(const FString& ItemId) const
{
	if (const FFableChestUiItemDefinition* Definition = ItemDefinitions.Find(ItemId))
	{
		if (!Definition->DisplayName.IsEmpty())
		{
			return Definition->DisplayName;
		}
	}

	return ItemId;
}

UTexture2D* UFableChestWidget::GetIconForItem(const FString& ItemId)
{
	if (ItemId.IsEmpty())
	{
		return nullptr;
	}

	if (TObjectPtr<UTexture2D>* CachedTexture = IconTextureCache.Find(ItemId))
	{
		return CachedTexture->Get();
	}

	const FFableChestUiItemDefinition* Definition = ItemDefinitions.Find(ItemId);
	if (Definition == nullptr || Definition->IconAssetPath.IsEmpty())
	{
		IconTextureCache.Add(ItemId, nullptr);
		return nullptr;
	}

	UTexture2D* Texture = LoadObject<UTexture2D>(nullptr, *Definition->IconAssetPath);
	IconTextureCache.Add(ItemId, Texture);
	return Texture;
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

	if (ActiveChest != nullptr && ActiveChest->GetChestItems().IsEmpty())
	{
		if (CachedController != nullptr)
		{
			CachedController->CloseChest();
		}
		else
		{
			CloseChest();
		}
		return;
	}

	RefreshItemRows();
}

void UFableChestWidget::HandleTakeAllAction(FName ActionId)
{
	if (ActiveChest == nullptr || CachedController == nullptr)
	{
		return;
	}

	ActiveChest->TakeAll(CachedController);

	if (ActiveChest != nullptr && ActiveChest->GetChestItems().IsEmpty())
	{
		if (CachedController != nullptr)
		{
			CachedController->CloseChest();
		}
		else
		{
			CloseChest();
		}
		return;
	}

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
