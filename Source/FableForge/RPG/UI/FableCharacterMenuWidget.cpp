#include "RPG/UI/FableCharacterMenuWidget.h"

#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/ButtonSlot.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/ScrollBox.h"
#include "Components/SizeBox.h"
#include "Components/SlateWrapperTypes.h"
#include "Components/Spacer.h"
#include "Components/TextBlock.h"
#include "Components/UniformGridPanel.h"
#include "Components/UniformGridSlot.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Misc/FileHelper.h"
#include "RPG/Save/FableSaveSubsystem.h"
#include "RPG/UI/FableActionButton.h"
#include "RPG/UI/FableInventorySlotWidget.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "TimerManager.h"

namespace
{
	const FName InventoryAction = TEXT("tab_inventory");
	const FName SkillsAction = TEXT("tab_skills");
	const FName CompanionsAction = TEXT("tab_companions");
	const FName BuildAction = TEXT("tab_build");
	const FName CloseMenuAction = TEXT("close_menu");

	const FName CategoryWeaponsAction = TEXT("cat_weapons");
	const FName CategoryArmorAction = TEXT("cat_armor");
	const FName CategoryConsumablesAction = TEXT("cat_consumables");
	const FName CategoryMiscAction = TEXT("cat_misc");
	const FName CategoryKeyItemsAction = TEXT("cat_key_items");

	const FLinearColor UiPanelColor(0.01f, 0.01f, 0.01f, 0.96f);
	const FLinearColor UiSectionColor(0.03f, 0.03f, 0.03f, 0.94f);
	const FLinearColor UiButtonColor(0.05f, 0.05f, 0.05f, 1.0f);
	const FLinearColor UiButtonSelectedColor(0.0f, 0.0f, 0.0f, 1.0f);
	const FLinearColor UiTextColor(0.95f, 0.95f, 0.95f, 1.0f);
	const FLinearColor UiMutedTextColor(0.72f, 0.72f, 0.72f, 1.0f);
	const TArray<FString> EquipmentSlotNames = {
		TEXT("Weapon"),
		TEXT("Head"),
		TEXT("Chest"),
		TEXT("Hands"),
		TEXT("Legs"),
		TEXT("Feet")
	};

	const FString UnityItemsPath = TEXT("/Users/scottlandes/Projects/Unity/FableForge/Assets/Resources/Prefabs/Objects/items.json");
	const FString UnityWeaponsPath = TEXT("/Users/scottlandes/Projects/Unity/FableForge/Assets/Resources/Prefabs/Objects/weapons.json");
	const FString UnityArmorPath = TEXT("/Users/scottlandes/Projects/Unity/FableForge/Assets/Resources/Prefabs/Objects/armor.json");

	FName CategoryFromType(const FString& InType)
	{
		const FString Type = InType.ToLower();
		if (Type == TEXT("weapon"))
		{
			return CategoryWeaponsAction;
		}

		if (Type == TEXT("armor"))
		{
			return CategoryArmorAction;
		}

		if (Type == TEXT("consumable"))
		{
			return CategoryConsumablesAction;
		}

		if (Type == TEXT("key") || Type == TEXT("keyitem") || Type == TEXT("key_item") || Type == TEXT("quest"))
		{
			return CategoryKeyItemsAction;
		}

		return CategoryMiscAction;
	}

	FString BuildIconToken(const FString& InName)
	{
		FString Compact = InName;
		Compact.ReplaceInline(TEXT("_"), TEXT(" "));
		TArray<FString> Words;
		Compact.ParseIntoArray(Words, TEXT(" "), true);

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

		if (Token.Len() == 1)
		{
			return Token + TEXT("?");
		}

		return TEXT("??");
	}

	int32 ArmorSlotIndexFromString(const FString& InSlotName)
	{
		const FString Slot = InSlotName.ToLower();
		if (Slot == TEXT("head"))
		{
			return 1;
		}

		if (Slot == TEXT("chest"))
		{
			return 2;
		}

		if (Slot == TEXT("hands") || Slot == TEXT("arms"))
		{
			return 3;
		}

		if (Slot == TEXT("legs"))
		{
			return 4;
		}

		if (Slot == TEXT("feet"))
		{
			return 5;
		}

		return INDEX_NONE;
	}

	FString CategoryDisplayName(FName Category)
	{
		if (Category == CategoryWeaponsAction)
		{
			return TEXT("Weapons");
		}

		if (Category == CategoryArmorAction)
		{
			return TEXT("Armor");
		}

		if (Category == CategoryConsumablesAction)
		{
			return TEXT("Consumables");
		}

		if (Category == CategoryKeyItemsAction)
		{
			return TEXT("Key Items");
		}

		return TEXT("Misc");
	}
}

TSharedRef<SWidget> UFableCharacterMenuWidget::RebuildWidget()
{
	Rebuild();
	return Super::RebuildWidget();
}

void UFableCharacterMenuWidget::NativeConstruct()
{
	Super::NativeConstruct();
	Close();
}

void UFableCharacterMenuWidget::Open()
{
	SetVisibility(ESlateVisibility::Visible);
	bInventoryLoaded = false;

	if (WidgetTree == nullptr || WidgetTree->RootWidget == nullptr || ContentRoot == nullptr)
	{
		Rebuild();
		return;
	}

	LoadInventoryFromSave();
	LoadItemDefinitionsFromUnityJson();
	RebuildTabContent();
}

void UFableCharacterMenuWidget::Close()
{
	SetVisibility(ESlateVisibility::Collapsed);
}

void UFableCharacterMenuWidget::Toggle()
{
	if (IsOpen())
	{
		Close();
	}
	else
	{
		Open();
	}
}

bool UFableCharacterMenuWidget::IsOpen() const
{
	return GetVisibility() == ESlateVisibility::Visible;
}

void UFableCharacterMenuWidget::Rebuild()
{
	if (WidgetTree == nullptr)
	{
		return;
	}

	SlotWidgets.Reset();

	UCanvasPanel* Root = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("CharacterMenuRoot"));
	WidgetTree->RootWidget = Root;

	UBorder* Frame = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("Frame"));
	Frame->SetBrushColor(UiPanelColor);
	if (UCanvasPanelSlot* FrameSlot = Root->AddChildToCanvas(Frame))
	{
		FrameSlot->SetAnchors(FAnchors(0.5f, 0.5f));
		FrameSlot->SetAlignment(FVector2D(0.5f, 0.5f));
		FrameSlot->SetSize(FVector2D(1260.0f, 780.0f));
	}

	UVerticalBox* VBox = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("FrameVBox"));
	Frame->SetContent(VBox);

	UHorizontalBox* HeaderRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("HeaderRow"));
	if (UVerticalBoxSlot* HeaderSlot = VBox->AddChildToVerticalBox(HeaderRow))
	{
		HeaderSlot->SetPadding(FMargin(20.0f, 14.0f, 20.0f, 8.0f));
	}

	USpacer* LeftSpacer = WidgetTree->ConstructWidget<USpacer>(USpacer::StaticClass());
	if (UHorizontalBoxSlot* SpacerSlot = HeaderRow->AddChildToHorizontalBox(LeftSpacer))
	{
		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		SpacerSlot->SetSize(FillSize);
	}

	UTextBlock* Title = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	Title->SetText(FText::FromString(TEXT("Character Menu")));
	Title->SetJustification(ETextJustify::Center);
	Title->SetColorAndOpacity(FSlateColor(UiTextColor));
	if (UHorizontalBoxSlot* TitleSlot = HeaderRow->AddChildToHorizontalBox(Title))
	{
		TitleSlot->SetHorizontalAlignment(HAlign_Center);
		TitleSlot->SetVerticalAlignment(VAlign_Center);
		TitleSlot->SetPadding(FMargin(10.0f, 0.0f, 10.0f, 0.0f));
	}

	UFableActionButton* CloseButton = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass(), TEXT("CloseButton"));
	CloseButton->InitializeAction(CloseMenuAction);
	CloseButton->OnActionClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleActionClicked);
	CloseButton->SetBackgroundColor(UiButtonColor);
	UTextBlock* CloseText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	CloseText->SetText(FText::FromString(TEXT("X")));
	CloseText->SetColorAndOpacity(FSlateColor(UiTextColor));
	CloseText->SetJustification(ETextJustify::Center);
	CloseButton->AddChild(CloseText);
	if (UButtonSlot* CloseTextSlot = Cast<UButtonSlot>(CloseText->Slot))
	{
		CloseTextSlot->SetHorizontalAlignment(HAlign_Center);
		CloseTextSlot->SetVerticalAlignment(VAlign_Center);
		CloseTextSlot->SetPadding(FMargin(10.0f, 4.0f));
	}
	if (UHorizontalBoxSlot* CloseSlot = HeaderRow->AddChildToHorizontalBox(CloseButton))
	{
		CloseSlot->SetHorizontalAlignment(HAlign_Right);
		CloseSlot->SetVerticalAlignment(VAlign_Center);
		CloseSlot->SetPadding(FMargin(12.0f, 0.0f, 0.0f, 0.0f));
	}

	UHorizontalBox* TabRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("TabRow"));
	if (UVerticalBoxSlot* TabRowSlot = VBox->AddChildToVerticalBox(TabRow))
	{
		TabRowSlot->SetPadding(FMargin(20.0f, 0.0f, 20.0f, 12.0f));
	}

	auto AddTabButton = [&](const FString& Label, FName ActionId, bool bSelected)
	{
		UFableActionButton* Button = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass());
		Button->InitializeAction(ActionId);
		Button->OnActionClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleActionClicked);
		Button->SetBackgroundColor(bSelected ? UiButtonSelectedColor : UiButtonColor);

		UTextBlock* Text = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		Text->SetText(FText::FromString(Label));
		Text->SetColorAndOpacity(FSlateColor(UiTextColor));
		Text->SetJustification(ETextJustify::Center);
		Button->AddChild(Text);
		if (UButtonSlot* TextSlot = Cast<UButtonSlot>(Text->Slot))
		{
			TextSlot->SetHorizontalAlignment(HAlign_Center);
			TextSlot->SetVerticalAlignment(VAlign_Center);
			TextSlot->SetPadding(FMargin(12.0f, 10.0f));
		}

		if (UHorizontalBoxSlot* HorizontalSlot = TabRow->AddChildToHorizontalBox(Button))
		{
			HorizontalSlot->SetPadding(FMargin(0.0f, 0.0f, 8.0f, 0.0f));
		}
	};

	AddTabButton(TEXT("Inventory"), InventoryAction, ActiveTab == TEXT("inventory"));
	AddTabButton(TEXT("Skills"), SkillsAction, ActiveTab == TEXT("skills"));
	AddTabButton(TEXT("Companions"), CompanionsAction, ActiveTab == TEXT("companions"));
	AddTabButton(TEXT("Build"), BuildAction, ActiveTab == TEXT("build"));

	UScrollBox* Scroll = WidgetTree->ConstructWidget<UScrollBox>(UScrollBox::StaticClass(), TEXT("TabContentScroll"));
	if (UVerticalBoxSlot* ScrollSlot = VBox->AddChildToVerticalBox(Scroll))
	{
		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		ScrollSlot->SetSize(FillSize);
		ScrollSlot->SetPadding(FMargin(20.0f, 0.0f, 20.0f, 20.0f));
	}

	ContentRoot = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("TabContent"));
	Scroll->AddChild(ContentRoot);
	RebuildTabContent();
}

void UFableCharacterMenuWidget::RebuildTabContent()
{
	if (ContentRoot == nullptr)
	{
		return;
	}

	ContentRoot->ClearChildren();
	SlotWidgets.Reset();

	if (ActiveTab == TEXT("inventory"))
	{
		BuildInventoryTab();
		return;
	}

	if (ActiveTab == TEXT("skills"))
	{
		BuildSkillsTab();
		return;
	}

	if (ActiveTab == TEXT("companions"))
	{
		BuildSimpleInfoTab(TEXT("Companions"), TEXT("No companions recruited yet."));
		return;
	}

	BuildSimpleInfoTab(TEXT("Build"), TEXT("No structures queued."));
}

void UFableCharacterMenuWidget::BuildInventoryTab()
{
	LoadInventoryFromSave();
	LoadItemDefinitionsFromUnityJson();

	UHorizontalBox* CategoryRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("InventoryCategoryRow"));
	if (UVerticalBoxSlot* CategoryRowSlot = ContentRoot->AddChildToVerticalBox(CategoryRow))
	{
		CategoryRowSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 12.0f));
	}

	auto AddCategoryButton = [&](const FString& Label, FName CategoryAction)
	{
		UFableActionButton* Button = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass());
		Button->InitializeAction(CategoryAction);
		Button->OnActionClicked.AddDynamic(this, &UFableCharacterMenuWidget::HandleActionClicked);
		Button->SetBackgroundColor(ActiveInventoryCategory == CategoryAction ? UiButtonSelectedColor : UiButtonColor);

		UTextBlock* Text = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		Text->SetText(FText::FromString(Label));
		Text->SetColorAndOpacity(FSlateColor(UiTextColor));
		Text->SetJustification(ETextJustify::Center);
		FSlateFontInfo FontInfo = Text->GetFont();
		FontInfo.Size = 15;
		Text->SetFont(FontInfo);
		Button->AddChild(Text);
		if (UButtonSlot* TextSlot = Cast<UButtonSlot>(Text->Slot))
		{
			TextSlot->SetHorizontalAlignment(HAlign_Center);
			TextSlot->SetVerticalAlignment(VAlign_Center);
			TextSlot->SetPadding(FMargin(10.0f, 8.0f));
		}

		if (UHorizontalBoxSlot* HorizontalSlot = CategoryRow->AddChildToHorizontalBox(Button))
		{
			FSlateChildSize FillSize;
			FillSize.SizeRule = ESlateSizeRule::Fill;
			FillSize.Value = 1.0f;
			HorizontalSlot->SetSize(FillSize);
			HorizontalSlot->SetPadding(FMargin(0.0f, 0.0f, 8.0f, 0.0f));
		}
	};

	AddCategoryButton(TEXT("Armor"), CategoryArmorAction);
	AddCategoryButton(TEXT("Weapons"), CategoryWeaponsAction);
	AddCategoryButton(TEXT("Consumables"), CategoryConsumablesAction);
	AddCategoryButton(TEXT("Misc"), CategoryMiscAction);
	AddCategoryButton(TEXT("Key Items"), CategoryKeyItemsAction);

	UHorizontalBox* MainRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("InventoryMainRow"));
	if (UVerticalBoxSlot* MainRowSlot = ContentRoot->AddChildToVerticalBox(MainRow))
	{
		MainRowSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 8.0f));
	}

	UVerticalBox* LeftColumn = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("InventoryLeftColumn"));
	if (UHorizontalBoxSlot* LeftSlot = MainRow->AddChildToHorizontalBox(LeftColumn))
	{
		FSlateChildSize LeftSize;
		LeftSize.SizeRule = ESlateSizeRule::Fill;
		LeftSize.Value = 0.66f;
		LeftSlot->SetSize(LeftSize);
		LeftSlot->SetPadding(FMargin(0.0f, 0.0f, 12.0f, 0.0f));
	}

	UBorder* InventorySection = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("InventorySection"));
	InventorySection->SetBrushColor(UiSectionColor);
	InventorySection->SetPadding(FMargin(12.0f));
	LeftColumn->AddChildToVerticalBox(InventorySection);

	UVerticalBox* LeftSectionBox = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("InventorySectionVBox"));
	InventorySection->SetContent(LeftSectionBox);

	UTextBlock* CategoryHeading = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	CategoryHeading->SetText(FText::FromString(CategoryDisplayName(ActiveInventoryCategory)));
	CategoryHeading->SetColorAndOpacity(FSlateColor(UiTextColor));
	if (UVerticalBoxSlot* CategoryHeadingSlot = LeftSectionBox->AddChildToVerticalBox(CategoryHeading))
	{
		CategoryHeadingSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 8.0f));
	}

	UUniformGridPanel* InventoryGrid = WidgetTree->ConstructWidget<UUniformGridPanel>(UUniformGridPanel::StaticClass(), TEXT("InventoryGrid"));
	if (UVerticalBoxSlot* InventoryGridSlot = LeftSectionBox->AddChildToVerticalBox(InventoryGrid))
	{
		InventoryGridSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 8.0f));
	}

	for (int32 SlotIndex = 0; SlotIndex < UFableSaveSubsystem::InventorySlotsPerCharacter; ++SlotIndex)
	{
		const FName SlotId(*FString::Printf(TEXT("inv_%d"), SlotIndex));
		const FString ItemId = InventorySlots.IsValidIndex(SlotIndex) ? InventorySlots[SlotIndex] : TEXT("");
		const bool bMatchesCategory = ItemId.IsEmpty() || ResolveItemCategory(ItemId) == ActiveInventoryCategory;

		UFableInventorySlotWidget* SlotWidget = WidgetTree->ConstructWidget<UFableInventorySlotWidget>(UFableInventorySlotWidget::StaticClass());
		SlotWidget->InitializeSlot(SlotId, TEXT(""), false);
		SlotWidget->SetItemData(
			bMatchesCategory ? ItemId : TEXT(""),
			bMatchesCategory ? GetItemLabelForSlot(ItemId, false) : TEXT(""));
		SlotWidget->OnItemDrop.AddDynamic(this, &UFableCharacterMenuWidget::HandleInventorySlotDropped);

		USizeBox* SlotSizeBox = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
		SlotSizeBox->SetWidthOverride(94.0f);
		SlotSizeBox->SetHeightOverride(94.0f);
		SlotSizeBox->SetContent(SlotWidget);

		if (UUniformGridSlot* GridSlot = InventoryGrid->AddChildToUniformGrid(SlotSizeBox, SlotIndex / 5, SlotIndex % 5))
		{
			GridSlot->SetHorizontalAlignment(HAlign_Fill);
			GridSlot->SetVerticalAlignment(VAlign_Fill);
		}

		SlotWidgets.Add(SlotId, SlotWidget);
	}

	UVerticalBox* RightColumn = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("InventoryRightColumn"));
	if (UHorizontalBoxSlot* RightSlot = MainRow->AddChildToHorizontalBox(RightColumn))
	{
		FSlateChildSize RightSize;
		RightSize.SizeRule = ESlateSizeRule::Fill;
		RightSize.Value = 0.34f;
		RightSlot->SetSize(RightSize);
	}

	UBorder* EquipmentSection = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("EquipmentSection"));
	EquipmentSection->SetBrushColor(UiSectionColor);
	EquipmentSection->SetPadding(FMargin(12.0f));
	RightColumn->AddChildToVerticalBox(EquipmentSection);

	UVerticalBox* RightSectionBox = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("EquipmentSectionVBox"));
	EquipmentSection->SetContent(RightSectionBox);

	UTextBlock* EquipmentHeading = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	EquipmentHeading->SetText(FText::FromString(TEXT("Equipment")));
	EquipmentHeading->SetColorAndOpacity(FSlateColor(UiTextColor));
	if (UVerticalBoxSlot* EquipmentHeadingSlot = RightSectionBox->AddChildToVerticalBox(EquipmentHeading))
	{
		EquipmentHeadingSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 8.0f));
	}

	UUniformGridPanel* EquipmentGrid = WidgetTree->ConstructWidget<UUniformGridPanel>(UUniformGridPanel::StaticClass(), TEXT("EquipmentGrid"));
	RightSectionBox->AddChildToVerticalBox(EquipmentGrid);
	for (int32 SlotIndex = 0; SlotIndex < EquipmentSlotNames.Num(); ++SlotIndex)
	{
		const FName SlotId(*FString::Printf(TEXT("equip_%d"), SlotIndex));
		const FString ItemId = EquippedSlots.IsValidIndex(SlotIndex) ? EquippedSlots[SlotIndex] : TEXT("");

		UFableInventorySlotWidget* SlotWidget = WidgetTree->ConstructWidget<UFableInventorySlotWidget>(UFableInventorySlotWidget::StaticClass());
		SlotWidget->InitializeSlot(SlotId, EquipmentSlotNames[SlotIndex], true);
		SlotWidget->SetItemData(ItemId, GetItemLabelForSlot(ItemId, true));
		SlotWidget->OnItemDrop.AddDynamic(this, &UFableCharacterMenuWidget::HandleInventorySlotDropped);

		USizeBox* SlotSizeBox = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
		SlotSizeBox->SetWidthOverride(104.0f);
		SlotSizeBox->SetHeightOverride(104.0f);
		SlotSizeBox->SetContent(SlotWidget);

		if (UUniformGridSlot* GridSlot = EquipmentGrid->AddChildToUniformGrid(SlotSizeBox, SlotIndex / 2, SlotIndex % 2))
		{
			GridSlot->SetHorizontalAlignment(HAlign_Fill);
			GridSlot->SetVerticalAlignment(VAlign_Fill);
		}

		SlotWidgets.Add(SlotId, SlotWidget);
	}

	UTextBlock* Hint = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	Hint->SetText(FText::FromString(TEXT("Drag between slots to rearrange/equip items.")));
	Hint->SetColorAndOpacity(FSlateColor(UiMutedTextColor));
	Hint->SetAutoWrapText(true);
	if (UVerticalBoxSlot* HintSlot = ContentRoot->AddChildToVerticalBox(Hint))
	{
		HintSlot->SetPadding(FMargin(0.0f, 8.0f, 0.0f, 0.0f));
	}
}

void UFableCharacterMenuWidget::BuildSimpleInfoTab(const FString& Header, const FString& Body)
{
	auto AddLine = [&](const FString& Text, bool bMuted = false)
	{
		UTextBlock* Line = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		Line->SetText(FText::FromString(Text));
		Line->SetAutoWrapText(true);
		Line->SetColorAndOpacity(FSlateColor(bMuted ? UiMutedTextColor : UiTextColor));
		if (UVerticalBoxSlot* LineSlot = ContentRoot->AddChildToVerticalBox(Line))
		{
			LineSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 10.0f));
		}
	};

	AddLine(Header, false);
	AddLine(Body, true);
}

void UFableCharacterMenuWidget::BuildSkillsTab()
{
	TArray<FString> LearnedSkills;
	if (UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr)
	{
		SaveSubsystem->TryGetActiveLearnedSkills(LearnedSkills);
	}

	UTextBlock* Heading = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	Heading->SetText(FText::FromString(TEXT("Skills (Drag to action bars)")));
	Heading->SetColorAndOpacity(FSlateColor(UiTextColor));
	if (UVerticalBoxSlot* HeadingSlot = ContentRoot->AddChildToVerticalBox(Heading))
	{
		HeadingSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 10.0f));
	}

	if (LearnedSkills.Num() == 0)
	{
		BuildSimpleInfoTab(TEXT("Skills"), TEXT("No learned skills yet."));
		return;
	}

	UUniformGridPanel* SkillsGrid = WidgetTree->ConstructWidget<UUniformGridPanel>(UUniformGridPanel::StaticClass(), TEXT("SkillsGrid"));
	if (UVerticalBoxSlot* GridSlot = ContentRoot->AddChildToVerticalBox(SkillsGrid))
	{
		GridSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 8.0f));
	}

	for (int32 SkillIndex = 0; SkillIndex < LearnedSkills.Num(); ++SkillIndex)
	{
		const FString& SkillId = LearnedSkills[SkillIndex];
		const FString DisplayLabel = BuildIconToken(SkillId);
		const FName SlotId(*FString::Printf(TEXT("skill_%d"), SkillIndex));

		UFableInventorySlotWidget* SkillSlot = WidgetTree->ConstructWidget<UFableInventorySlotWidget>(UFableInventorySlotWidget::StaticClass());
		SkillSlot->InitializeSlot(SlotId, TEXT(""), false);
		SkillSlot->SetItemData(FString::Printf(TEXT("skill:%s"), *SkillId), DisplayLabel);

		USizeBox* SlotSizeBox = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
		SlotSizeBox->SetWidthOverride(96.0f);
		SlotSizeBox->SetHeightOverride(96.0f);
		SlotSizeBox->SetContent(SkillSlot);

		if (UUniformGridSlot* UniformSlot = SkillsGrid->AddChildToUniformGrid(SlotSizeBox, SkillIndex / 8, SkillIndex % 8))
		{
			UniformSlot->SetHorizontalAlignment(HAlign_Fill);
			UniformSlot->SetVerticalAlignment(VAlign_Fill);
		}
	}
}

void UFableCharacterMenuWidget::LoadInventoryFromSave()
{
	if (bInventoryLoaded)
	{
		return;
	}

	InventorySlots.SetNum(UFableSaveSubsystem::InventorySlotsPerCharacter);
	EquippedSlots.SetNum(UFableSaveSubsystem::EquipmentSlotsPerCharacter);

	if (UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr)
	{
		TArray<FString> SavedInventory;
		TArray<FString> SavedEquipment;
		if (SaveSubsystem->TryGetActiveInventory(SavedInventory, SavedEquipment))
		{
			InventorySlots = SavedInventory;
			EquippedSlots = SavedEquipment;
		}
	}

	if (InventorySlots.Num() != UFableSaveSubsystem::InventorySlotsPerCharacter)
	{
		InventorySlots.SetNum(UFableSaveSubsystem::InventorySlotsPerCharacter);
	}
	if (EquippedSlots.Num() != UFableSaveSubsystem::EquipmentSlotsPerCharacter)
	{
		EquippedSlots.SetNum(UFableSaveSubsystem::EquipmentSlotsPerCharacter);
	}

	bInventoryLoaded = true;
}

void UFableCharacterMenuWidget::SaveInventoryToSaveSubsystem() const
{
	if (UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr)
	{
		SaveSubsystem->SetActiveInventory(InventorySlots, EquippedSlots);
	}
}

void UFableCharacterMenuWidget::LoadItemDefinitionsFromUnityJson()
{
	if (bItemDefinitionsLoaded)
	{
		return;
	}

	ItemDefinitions.Reset();

	auto ParseRootObject = [&](const FString& FilePath, TSharedPtr<FJsonObject>& OutRootObject) -> bool
	{
		FString JsonText;
		if (!FFileHelper::LoadFileToString(JsonText, *FilePath))
		{
			return false;
		}

		const TSharedRef<TJsonReader<>> Reader = TJsonReaderFactory<>::Create(JsonText);
		return FJsonSerializer::Deserialize(Reader, OutRootObject) && OutRootObject.IsValid();
	};

	auto AddDefinition = [&](const FFableUiItemDefinition& Definition)
	{
		if (Definition.Id.IsEmpty())
		{
			return;
		}

		ItemDefinitions.Add(Definition.Id, Definition);
	};

	auto ReadStringField = [](const TSharedPtr<FJsonObject>& JsonObject, const TCHAR* FieldName, const FString& DefaultValue = FString()) -> FString
	{
		if (!JsonObject.IsValid())
		{
			return DefaultValue;
		}

		FString Value;
		return JsonObject->TryGetStringField(FieldName, Value) ? Value : DefaultValue;
	};

	auto ReadBoolField = [](const TSharedPtr<FJsonObject>& JsonObject, const TCHAR* FieldName, bool bDefaultValue = false) -> bool
	{
		if (!JsonObject.IsValid())
		{
			return bDefaultValue;
		}

		bool bValue = bDefaultValue;
		JsonObject->TryGetBoolField(FieldName, bValue);
		return bValue;
	};

	TSharedPtr<FJsonObject> ItemsRoot;
	if (ParseRootObject(UnityItemsPath, ItemsRoot))
	{
		const TArray<TSharedPtr<FJsonValue>>* ItemsArray = nullptr;
		if (ItemsRoot->TryGetArrayField(TEXT("items"), ItemsArray) && ItemsArray != nullptr)
		{
			for (const TSharedPtr<FJsonValue>& ItemValue : *ItemsArray)
			{
				const TSharedPtr<FJsonObject> ItemObject = ItemValue.IsValid() ? ItemValue->AsObject() : nullptr;
				if (!ItemObject.IsValid())
				{
					continue;
				}

				FFableUiItemDefinition Definition;
				Definition.Id = ReadStringField(ItemObject, TEXT("id"));
				Definition.Name = ReadStringField(ItemObject, TEXT("name"), Definition.Id);
				Definition.Category = CategoryFromType(ReadStringField(ItemObject, TEXT("type"), TEXT("misc")));
				Definition.bStackable = ReadBoolField(ItemObject, TEXT("stackable"), true);
				Definition.bEquipable = false;
				Definition.ModelPath = ReadStringField(ItemObject, TEXT("prefab3d"));
				Definition.IconToken = BuildIconToken(Definition.Name);
				AddDefinition(Definition);
			}
		}
	}

	TSharedPtr<FJsonObject> WeaponsRoot;
	if (ParseRootObject(UnityWeaponsPath, WeaponsRoot))
	{
		const TArray<TSharedPtr<FJsonValue>>* WeaponsArray = nullptr;
		if (WeaponsRoot->TryGetArrayField(TEXT("weapons"), WeaponsArray) && WeaponsArray != nullptr)
		{
			for (const TSharedPtr<FJsonValue>& WeaponValue : *WeaponsArray)
			{
				const TSharedPtr<FJsonObject> WeaponObject = WeaponValue.IsValid() ? WeaponValue->AsObject() : nullptr;
				if (!WeaponObject.IsValid())
				{
					continue;
				}

				FFableUiItemDefinition Definition;
				Definition.Id = ReadStringField(WeaponObject, TEXT("id"));
				Definition.Name = ReadStringField(WeaponObject, TEXT("name"), Definition.Id);
				Definition.Category = CategoryWeaponsAction;
				Definition.bStackable = ReadBoolField(WeaponObject, TEXT("stackable"), false);
				Definition.bEquipable = true;
				Definition.EquipmentSlot = 0;
				Definition.ModelPath = ReadStringField(WeaponObject, TEXT("prefab3d"));
				Definition.IconToken = BuildIconToken(Definition.Name);
				AddDefinition(Definition);
			}
		}
	}

	TSharedPtr<FJsonObject> ArmorRoot;
	if (ParseRootObject(UnityArmorPath, ArmorRoot))
	{
		const TArray<TSharedPtr<FJsonValue>>* ArmorArray = nullptr;
		if (ArmorRoot->TryGetArrayField(TEXT("armor"), ArmorArray) && ArmorArray != nullptr)
		{
			for (const TSharedPtr<FJsonValue>& ArmorValue : *ArmorArray)
			{
				const TSharedPtr<FJsonObject> ArmorObject = ArmorValue.IsValid() ? ArmorValue->AsObject() : nullptr;
				if (!ArmorObject.IsValid())
				{
					continue;
				}

				FFableUiItemDefinition Definition;
				Definition.Id = ReadStringField(ArmorObject, TEXT("id"));
				Definition.Name = ReadStringField(ArmorObject, TEXT("name"), Definition.Id);
				Definition.Category = CategoryArmorAction;
				Definition.bStackable = ReadBoolField(ArmorObject, TEXT("stackable"), false);
				Definition.bEquipable = true;
				Definition.IconToken = BuildIconToken(Definition.Name);
				Definition.ModelPathMale = ReadStringField(ArmorObject, TEXT("prefab3dMale"));
				Definition.ModelPathFemale = ReadStringField(ArmorObject, TEXT("prefab3dFemale"));

				const TSharedPtr<FJsonObject>* ArmorDataObject = nullptr;
				if (ArmorObject->TryGetObjectField(TEXT("armorData"), ArmorDataObject) && ArmorDataObject != nullptr && ArmorDataObject->IsValid())
				{
					Definition.EquipmentSlot = ArmorSlotIndexFromString(ReadStringField(*ArmorDataObject, TEXT("slot")));
				}

				AddDefinition(Definition);
			}
		}
	}

	bItemDefinitionsLoaded = true;
}

void UFableCharacterMenuWidget::RefreshInventorySlotWidgets()
{
	for (TPair<FName, TObjectPtr<UFableInventorySlotWidget>>& Pair : SlotWidgets)
	{
		const FName SlotId = Pair.Key;
		UFableInventorySlotWidget* SlotWidget = Pair.Value;
		if (SlotWidget == nullptr)
		{
			continue;
		}

		bool bEquipmentSlot = false;
		int32 SlotIndex = INDEX_NONE;
		if (!ResolveSlotAddress(SlotId, bEquipmentSlot, SlotIndex))
		{
			continue;
		}

		const TArray<FString>& SourceArray = bEquipmentSlot ? EquippedSlots : InventorySlots;
		if (!SourceArray.IsValidIndex(SlotIndex))
		{
			continue;
		}

		const FString ItemId = SourceArray[SlotIndex];
		if (!bEquipmentSlot && !ItemId.IsEmpty() && ResolveItemCategory(ItemId) != ActiveInventoryCategory)
		{
			SlotWidget->SetItemData(TEXT(""), TEXT(""));
			continue;
		}

		SlotWidget->SetItemData(ItemId, GetItemLabelForSlot(ItemId, bEquipmentSlot));
	}
}

bool UFableCharacterMenuWidget::ResolveSlotAddress(FName SlotId, bool& bOutEquipmentSlot, int32& OutSlotIndex) const
{
	bOutEquipmentSlot = false;
	OutSlotIndex = INDEX_NONE;

	const FString SlotString = SlotId.ToString();
	FString Prefix;
	FString IndexString;
	if (!SlotString.Split(TEXT("_"), &Prefix, &IndexString, ESearchCase::CaseSensitive, ESearchDir::FromEnd))
	{
		return false;
	}

	int32 ParsedIndex = INDEX_NONE;
	if (!LexTryParseString(ParsedIndex, *IndexString))
	{
		return false;
	}

	if (Prefix == TEXT("equip"))
	{
		bOutEquipmentSlot = true;
		OutSlotIndex = ParsedIndex;
		return true;
	}

	if (Prefix == TEXT("inv"))
	{
		bOutEquipmentSlot = false;
		OutSlotIndex = ParsedIndex;
		return true;
	}

	return false;
}

bool UFableCharacterMenuWidget::IsItemAllowedInEquipmentSlot(const FString& ItemId, int32 EquipmentSlotIndex) const
{
	if (ItemId.IsEmpty())
	{
		return true;
	}

	const FFableUiItemDefinition* Definition = ItemDefinitions.Find(ItemId);
	if (Definition == nullptr || !Definition->bEquipable)
	{
		return false;
	}

	return Definition->EquipmentSlot == EquipmentSlotIndex;
}

FString UFableCharacterMenuWidget::GetItemLabelForSlot(const FString& ItemId, bool bEquipmentSlot) const
{
	if (ItemId.IsEmpty())
	{
		return TEXT("");
	}

	if (const FFableUiItemDefinition* Definition = ItemDefinitions.Find(ItemId))
	{
		if (!Definition->IconToken.IsEmpty())
		{
			return Definition->IconToken;
		}
	}

	return bEquipmentSlot ? BuildIconToken(ItemId) : BuildIconToken(ItemId);
}

FName UFableCharacterMenuWidget::ResolveItemCategory(const FString& ItemId) const
{
	if (ItemId.IsEmpty())
	{
		return CategoryMiscAction;
	}

	if (const FFableUiItemDefinition* Definition = ItemDefinitions.Find(ItemId))
	{
		return Definition->Category;
	}

	return CategoryMiscAction;
}

void UFableCharacterMenuWidget::HandleInventorySlotDropped(FName FromSlotId, FName ToSlotId, const FString& PayloadId, const FString& PayloadLabel)
{
	(void)PayloadId;
	(void)PayloadLabel;

	bool bFromEquipment = false;
	int32 FromIndex = INDEX_NONE;
	bool bToEquipment = false;
	int32 ToIndex = INDEX_NONE;

	if (!ResolveSlotAddress(FromSlotId, bFromEquipment, FromIndex) || !ResolveSlotAddress(ToSlotId, bToEquipment, ToIndex))
	{
		return;
	}

	TArray<FString>& FromArray = bFromEquipment ? EquippedSlots : InventorySlots;
	TArray<FString>& ToArray = bToEquipment ? EquippedSlots : InventorySlots;
	if (!FromArray.IsValidIndex(FromIndex) || !ToArray.IsValidIndex(ToIndex))
	{
		return;
	}

	const FString SourceItemId = FromArray[FromIndex];
	const FString DestinationItemId = ToArray[ToIndex];
	if (SourceItemId.IsEmpty())
	{
		return;
	}

	if (bToEquipment && !IsItemAllowedInEquipmentSlot(SourceItemId, ToIndex))
	{
		return;
	}

	if (bFromEquipment && !DestinationItemId.IsEmpty() && !IsItemAllowedInEquipmentSlot(DestinationItemId, FromIndex))
	{
		return;
	}

	const FString TempValue = FromArray[FromIndex];
	FromArray[FromIndex] = ToArray[ToIndex];
	ToArray[ToIndex] = TempValue;

	RefreshInventorySlotWidgets();
	SaveInventoryToSaveSubsystem();
}

void UFableCharacterMenuWidget::HandleActionClicked(FName ActionId)
{
	if (ActionId == CloseMenuAction)
	{
		if (UWorld* World = GetWorld())
		{
			World->GetTimerManager().SetTimerForNextTick(FTimerDelegate::CreateUObject(this, &UFableCharacterMenuWidget::Close));
		}
		else
		{
			Close();
		}
		return;
	}

	if (ActionId == InventoryAction)
	{
		ActiveTab = TEXT("inventory");
		RebuildTabContent();
		return;
	}

	if (ActionId == SkillsAction)
	{
		ActiveTab = TEXT("skills");
		RebuildTabContent();
		return;
	}

	if (ActionId == CompanionsAction)
	{
		ActiveTab = TEXT("companions");
		RebuildTabContent();
		return;
	}

	if (ActionId == BuildAction)
	{
		ActiveTab = TEXT("build");
		RebuildTabContent();
		return;
	}

	if (ActionId == CategoryWeaponsAction || ActionId == CategoryArmorAction || ActionId == CategoryConsumablesAction || ActionId == CategoryMiscAction || ActionId == CategoryKeyItemsAction)
	{
		ActiveInventoryCategory = ActionId;
		if (ActiveTab == TEXT("inventory"))
		{
			RebuildTabContent();
		}
	}
}
