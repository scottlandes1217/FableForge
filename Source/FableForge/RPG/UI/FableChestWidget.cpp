#include "RPG/UI/FableChestWidget.h"

#include "Components/Border.h"
#include "Components/Overlay.h"
#include "Components/OverlaySlot.h"
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
#include "Brushes/SlateRoundedBoxBrush.h"
#include "FableForge.h"
#include "RPG/UI/FableItemIconLibrary.h"
#include "RPG/UI/FableBookStyle.h"
#include "IImageWrapper.h"
#include "IImageWrapperModule.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Modules/ModuleManager.h"
#include "UObject/StrongObjectPtr.h"

namespace
{
	static const TCHAR* ItemsDataTablePath = TEXT("/Game/Data/DT_Items.DT_Items");
	static const TCHAR* WeaponsDataTablePath = TEXT("/Game/Data/DT_Weapons.DT_Weapons");
	static const TCHAR* ArmorDataTablePath = TEXT("/Game/Data/DT_Armor.DT_Armor");
	static const TCHAR* WhiteSquareTexturePath = TEXT("/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture");
	static const TCHAR* ChestWoodPanelTexturePath = TEXT("/Game/Slate/Textures/ChestWoodPanel.ChestWoodPanel");
	const FLinearColor ChestSlotFrame(0.65f, 0.43f, 0.18f, 1.0f);

	UTexture2D* LoadChestPanelSourceTexture()
	{
		static TStrongObjectPtr<UTexture2D> CachedTexture;
		if (CachedTexture.IsValid())
		{
			return CachedTexture.Get();
		}

		TArray<uint8> CompressedData;
		const FString SourcePath = FPaths::ProjectContentDir() / TEXT("Slate/Textures/ChestWoodPanel.png");
		if (!FFileHelper::LoadFileToArray(CompressedData, *SourcePath))
		{
			return nullptr;
		}

		IImageWrapperModule& ImageWrapperModule = FModuleManager::LoadModuleChecked<IImageWrapperModule>(TEXT("ImageWrapper"));
		TSharedPtr<IImageWrapper> ImageWrapper = ImageWrapperModule.CreateImageWrapper(EImageFormat::PNG);
		if (!ImageWrapper.IsValid() || !ImageWrapper->SetCompressed(CompressedData.GetData(), CompressedData.Num()))
		{
			return nullptr;
		}

		TArray<uint8> RawBGRA;
		if (!ImageWrapper->GetRaw(ERGBFormat::BGRA, 8, RawBGRA))
		{
			return nullptr;
		}

		UTexture2D* Texture = UTexture2D::CreateTransient(ImageWrapper->GetWidth(), ImageWrapper->GetHeight(), PF_B8G8R8A8);
		if (Texture == nullptr || Texture->GetPlatformData() == nullptr || Texture->GetPlatformData()->Mips.Num() == 0)
		{
			return nullptr;
		}
		void* MipData = Texture->GetPlatformData()->Mips[0].BulkData.Lock(LOCK_READ_WRITE);
		FMemory::Memcpy(MipData, RawBGRA.GetData(), RawBGRA.Num());
		Texture->GetPlatformData()->Mips[0].BulkData.Unlock();
		Texture->SRGB = true;
		Texture->NeverStream = true;
		Texture->UpdateResource();
		CachedTexture.Reset(Texture);
		return Texture;
	}
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
		PanelCanvasSlot->SetSize(FVector2D(760.0f, 480.0f));
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
	if (UTexture2D* ChestWoodPanel = LoadObject<UTexture2D>(nullptr, ChestWoodPanelTexturePath))
	{
		Panel->SetBrushFromTexture(ChestWoodPanel);
	}
	else if (UTexture2D* SourceChestWoodPanel = LoadChestPanelSourceTexture())
	{
		Panel->SetBrushFromTexture(SourceChestWoodPanel);
	}
	else if (UTexture2D* WhiteSquare = LoadObject<UTexture2D>(nullptr, WhiteSquareTexturePath))
	{
		Panel->SetBrushFromTexture(WhiteSquare);
	}
	Panel->SetBrushColor(FLinearColor::White);
	Panel->SetPadding(FMargin(0.0f));
	if (UCanvasPanelSlot* CanvasSlot = RootCanvas->AddChildToCanvas(Panel))
	{
		CanvasSlot->SetAutoSize(false);
		CanvasSlot->SetAnchors(FAnchors(0.5f, 0.5f));
		CanvasSlot->SetAlignment(FVector2D(0.5f, 0.5f));
		CanvasSlot->SetPosition(FVector2D::ZeroVector);
		CanvasSlot->SetSize(FVector2D(760.0f, 480.0f));
		PanelCanvasSlot = CanvasSlot;
	}

	// Anchor rail controls to the artwork, independently of the item area.
	UCanvasPanel* PanelLayout = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("ChestPanelLayout"));
	Panel->SetContent(PanelLayout);
	RootContent = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("ChestRootContent"));
	if (UCanvasPanelSlot* ContentSlot = PanelLayout->AddChildToCanvas(RootContent))
	{
		ContentSlot->SetAnchors(FAnchors(0.08f, 0.14f, 0.92f, 0.86f));
		ContentSlot->SetOffsets(FMargin(0.0f));
	}

	HeaderText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("ChestHeader"));
	HeaderText->SetText(FText::FromString(TEXT("Chest")));
	HeaderText->SetJustification(ETextJustify::Center);
	HeaderText->SetColorAndOpacity(FSlateColor(FLinearColor(0.98f, 0.84f, 0.48f)));
	{
		FSlateFontInfo HeaderFont = HeaderText->GetFont();
		HeaderFont.Size = 20;
		HeaderText->SetFont(HeaderFont);
	}
	if (UCanvasPanelSlot* HeaderSlot = PanelLayout->AddChildToCanvas(HeaderText))
	{
		HeaderSlot->SetAnchors(FAnchors(0.5f, 0.09f));
		HeaderSlot->SetAlignment(FVector2D(0.5f, 0.5f));
		HeaderSlot->SetAutoSize(true);
		HeaderSlot->SetPosition(FVector2D(0.0f, -3.0f));
	}

	ItemGrid = WidgetTree->ConstructWidget<UWrapBox>(UWrapBox::StaticClass(), TEXT("ItemGrid"));
	ItemGrid->SetInnerSlotPadding(FVector2D(8.0f, 8.0f));
	ItemGrid->SetHorizontalAlignment(HAlign_Center);
	ItemGrid->SetExplicitWrapSize(true);
	ItemGrid->SetWrapSize(680.0f);
	if (UVerticalBoxSlot* ItemListSlot = RootContent->AddChildToVerticalBox(ItemGrid))
	{
		ItemListSlot->SetPadding(FMargin(0.0f, 6.0f, 0.0f, 6.0f));
		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		ItemListSlot->SetSize(FillSize);
	}

	UHorizontalBox* ActionRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("ActionRow"));
	if (UCanvasPanelSlot* ActionRowSlot = PanelLayout->AddChildToCanvas(ActionRow))
	{
		ActionRowSlot->SetAnchors(FAnchors(0.5f, 0.89f));
		ActionRowSlot->SetAlignment(FVector2D(0.5f, 0.5f));
		ActionRowSlot->SetAutoSize(true);
		ActionRowSlot->SetPosition(FVector2D(0.0f, 5.0f));
	}

	UFableActionButton* TakeAllButton = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass(), TEXT("TakeAllButton"));
	TakeAllButton->InitializeAction(TEXT("take_all"));
	FableBookStyle::ApplyButton(TakeAllButton, false);
	TakeAllButton->OnActionClicked.AddDynamic(this, &UFableChestWidget::HandleTakeAllAction);
	USizeBox* TakeAllSize = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("TakeAllSize"));
	TakeAllSize->SetWidthOverride(136.0f);
	TakeAllSize->SetHeightOverride(30.0f);
	TakeAllSize->SetContent(TakeAllButton);
	if (UHorizontalBoxSlot* TakeAllSlot = ActionRow->AddChildToHorizontalBox(TakeAllSize))
	{
		TakeAllSlot->SetPadding(FMargin(0.0f, 0.0f, 8.0f, 0.0f));
	}

	UTextBlock* TakeAllLabel = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("TakeAllLabel"));
	TakeAllLabel->SetText(FText::FromString(TEXT("Take All")));
	{
		FSlateFontInfo LabelFont = TakeAllLabel->GetFont();
		LabelFont.Size = 14;
		TakeAllLabel->SetFont(LabelFont);
	}
	TakeAllLabel->SetColorAndOpacity(FSlateColor(FLinearColor(0.16f, 0.07f, 0.025f)));
	TakeAllButton->AddChild(TakeAllLabel);

	UFableActionButton* CloseButton = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass(), TEXT("CloseButton"));
	CloseButton->InitializeAction(TEXT("close"));
	FableBookStyle::ApplyButton(CloseButton, true);
	CloseButton->OnActionClicked.AddDynamic(this, &UFableChestWidget::HandleCloseAction);
	USizeBox* CloseSize = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("CloseSize"));
	CloseSize->SetWidthOverride(112.0f);
	CloseSize->SetHeightOverride(30.0f);
	CloseSize->SetContent(CloseButton);
	ActionRow->AddChildToHorizontalBox(CloseSize);

	UTextBlock* CloseLabel = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("CloseLabel"));
	CloseLabel->SetText(FText::FromString(TEXT("Close")));
	{
		FSlateFontInfo LabelFont = CloseLabel->GetFont();
		LabelFont.Size = 14;
		CloseLabel->SetFont(LabelFont);
	}
	CloseLabel->SetColorAndOpacity(FSlateColor(FLinearColor(0.98f, 0.88f, 0.68f)));
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
		TileButton->SetToolTipText(FText::FromString(GetDisplayNameForItem(ItemEntry.ItemId)));
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
		TileSizeBox->SetWidthOverride(96.0f);
		TileSizeBox->SetHeightOverride(96.0f);

		UBorder* TileBorder = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass());
		// The item artwork remains transparent; this outer border defines the
		// square hit target and keeps chest cells visually consistent with the bag.
		TileBorder->SetBrush(FSlateRoundedBoxBrush(
			FLinearColor(0.0f, 0.0f, 0.0f, 0.0f),
			2.0f,
			ChestSlotFrame,
			2.0f));
		TileBorder->SetPadding(FMargin(3.0f));
		UBorder* TileSurface = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass());
		TileSurface->SetBrushColor(FLinearColor(0.0f, 0.0f, 0.0f, 0.0f));
		TileSurface->SetPadding(FMargin(0));
		TileBorder->SetContent(TileSurface);
		TileSizeBox->SetContent(TileBorder);

		UOverlay* TileContent = WidgetTree->ConstructWidget<UOverlay>();
		TileSurface->SetContent(TileContent);

		if (UTexture2D* ItemIcon = GetIconForItem(ItemEntry.ItemId))
		{
			USizeBox* IconSizeBox = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
			IconSizeBox->SetWidthOverride(70.0f);
			IconSizeBox->SetHeightOverride(70.0f);
			if (UOverlaySlot* IconSlot = TileContent->AddChildToOverlay(IconSizeBox))
			{
				IconSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 2.0f));
				IconSlot->SetHorizontalAlignment(HAlign_Center);
				IconSlot->SetVerticalAlignment(VAlign_Center);
			}

			UImage* IconImage = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass());
			FSlateBrush IconBrush;
			IconBrush.SetResourceObject(ItemIcon);
			IconBrush.ImageSize = FVector2D(70.0f, 70.0f);
			IconImage->SetBrush(IconBrush);
			IconImage->SetColorAndOpacity(FLinearColor::White);
			IconSizeBox->SetContent(IconImage);
		}
		else
		{
			UTextBlock* TokenText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
			TokenText->SetText(FText::FromString(GetDisplayNameForItem(ItemEntry.ItemId).Left(1).ToUpper()));
			TokenText->SetJustification(ETextJustify::Center);
			if (UOverlaySlot* TokenSlot = TileContent->AddChildToOverlay(TokenText))
			{
				TokenSlot->SetHorizontalAlignment(HAlign_Center);
				TokenSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 2.0f));
			}
		}

		UTextBlock* ItemLabel = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		ItemLabel->SetText(FText::FromString(FString::Printf(TEXT("x%d"), ItemEntry.Quantity)));
		ItemLabel->SetJustification(ETextJustify::Center);
		ItemLabel->SetAutoWrapText(false);
		ItemLabel->SetShadowOffset(FVector2D(1,1));
		ItemLabel->SetShadowColorAndOpacity(FLinearColor::Black);
		{
			FSlateFontInfo FontInfo = ItemLabel->GetFont();
			FontInfo.Size = 13;
			ItemLabel->SetFont(FontInfo);
		}
		if (UOverlaySlot* LabelSlot = TileContent->AddChildToOverlay(ItemLabel))
		{
			LabelSlot->SetHorizontalAlignment(HAlign_Right);
			LabelSlot->SetPadding(FMargin(2));
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
	UTexture2D* Texture = Definition != nullptr && !Definition->IconAssetPath.IsEmpty()
		? LoadObject<UTexture2D>(nullptr, *Definition->IconAssetPath) : nullptr;
	if (Texture == nullptr) { Texture = FableItemIcons::Get(ItemId); }
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
