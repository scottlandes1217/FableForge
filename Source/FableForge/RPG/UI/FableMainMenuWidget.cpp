#include "RPG/UI/FableMainMenuWidget.h"
#include "RPG/UI/FableAppearancePresets.h"
#include "RPG/UI/FableAppearanceAssets.h"
#include "Components/Slider.h"
#include "Components/Image.h"
#include "Engine/Texture2D.h"
#include "ImageUtils.h"
#include "Misc/Paths.h"
#include "UObject/StrongObjectPtr.h"
#include "Input/Reply.h"
#include "InputCoreTypes.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/StaticMesh.h"
#if WITH_EDITOR
#include "AssetCompilingManager.h"
#endif

#include "Components/Border.h"
#include "Components/ButtonSlot.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/ContentWidget.h"
#include "Components/EditableTextBox.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/SizeBox.h"
#include "Components/ScaleBox.h"
#include "Components/ScrollBox.h"
#include "Components/Spacer.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Components/Viewport.h"
#include "RPG/UI/FableTransparentViewport.h"
#include "Components/Widget.h"
#include "Components/WidgetSwitcher.h"
#include "Components/PointLightComponent.h"
#include "Blueprint/WidgetTree.h"
#include "FableForge.h"
#include "FableForgePlayerController.h"
#include "RPG/Save/FableSaveSubsystem.h"
#include "RPG/UI/FableActionButton.h"
#include "Engine/SkeletalMesh.h"
#include "Animation/AnimSequence.h"
#include "Animation/Skeleton.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/SlateWrapperTypes.h"
#include "TimerManager.h"
#include "Components/Overlay.h"
#include "Components/OverlaySlot.h"
#include "RPG/UI/FableBookSurface.h"
#include "RPG/UI/FableBookStyle.h"

namespace
{
	const FName ContinueAction = TEXT("main_continue");
	const FName NewGameAction = TEXT("main_new_game");
	const FName ConfirmRaceAction = TEXT("confirm_race");
	const FName BackMainAction = TEXT("back_main");
	const FName BackCharactersAction = TEXT("back_characters");
	const FName BackRacesAction = TEXT("back_races");
	const FName BackCustomizationAction = TEXT("back_customization");
	const FName AppearanceAction = TEXT("appearance");
	const FName ResetAppearanceAction = TEXT("reset_appearance");
	const FName CreateCharacterAction = TEXT("create_character");
	const FName GenderMaleAction = TEXT("gender_male");
	const FName GenderFemaleAction = TEXT("gender_female");
	const FName RotateLeftAction = TEXT("preview_rotate_left");
	const FName RotateRightAction = TEXT("preview_rotate_right");

	const FName BackdropWidgetName(TEXT("Backdrop"));
	const FName PanelWidgetName(TEXT("Panel"));

	const TCHAR* MainMenuBaseCharacterMeshPath = TEXT("/Game/Characters/PlayableCharacter/Meshes/basecharacter_v2.basecharacter_v2");
	const TCHAR* LegacyMainMenuCharacterMeshPath = TEXT("/Game/Characters/Mannequins/Meshes/basecharacter_v2.basecharacter_v2");

	const FLinearColor UiBackdropColor(0.009f, 0.006f, 0.004f, 1.0f);
	const FLinearColor UiPanelColor = FLinearColor::Transparent;
	const FLinearColor MainMenuUiTextColor(0.075f, 0.035f, 0.015f, 1.0f);
	const FLinearColor UiMutedTextColor(0.22f, 0.13f, 0.065f, 1.0f);
	const FLinearColor MainMenuUiButtonColor(1.0f, 1.0f, 1.0f, 1.0f);
	const FLinearColor UiButtonSelectedColor(0.75f, 0.54f, 0.29f, 1.0f);
	const FLinearColor UiButtonDisabledColor(0.68f, 0.61f, 0.50f, 1.0f);

	void AddTitleOrnament(UWidgetTree* Tree, UVerticalBox* Parent)
	{
		UHorizontalBox* Ornament = Tree->ConstructWidget<UHorizontalBox>();
		if (UVerticalBoxSlot* OrnamentSlot = Parent->AddChildToVerticalBox(Ornament))
		{
			OrnamentSlot->SetHorizontalAlignment(HAlign_Center);
			OrnamentSlot->SetPadding(FMargin(0.0f, 12.0f));
		}
		for (int32 Index = 0; Index < 5; ++Index)
		{
			const bool bRule = Index == 0 || Index == 4;
			const float Edge = Index == 2 ? 10.0f : 5.0f;
			USizeBox* Size = Tree->ConstructWidget<USizeBox>();
			Size->SetWidthOverride(bRule ? 92.0f : Edge);
			Size->SetHeightOverride(bRule ? 1.0f : Edge);
			UBorder* Mark = Tree->ConstructWidget<UBorder>();
			Mark->SetPadding(FMargin(0.0f));
			Mark->SetBrushColor(FLinearColor(0.65f, 0.40f, 0.14f, bRule ? 0.55f : 1.0f));
			Mark->SetVisibility(ESlateVisibility::HitTestInvisible);
			if (!bRule)
			{
				Mark->SetRenderTransformAngle(45.0f);
			}
			Size->SetContent(Mark);
			if (UHorizontalBoxSlot* MarkSlot = Ornament->AddChildToHorizontalBox(Size))
			{
				MarkSlot->SetVerticalAlignment(VAlign_Center);
				MarkSlot->SetPadding(FMargin(8.0f, 0.0f));
			}
		}
	}

}

TSharedRef<SWidget> UFableMainMenuWidget::RebuildWidget()
{
	Rebuild();
	return Super::RebuildWidget();
}

UFableMainMenuWidget::UFableMainMenuWidget(const FObjectInitializer& ObjectInitializer)
	: Super(ObjectInitializer)
{
	SetIsFocusable(true);
}

void UFableMainMenuWidget::NativeConstruct()
{
	Super::NativeConstruct();
	OpenMainMenu();
}

void UFableMainMenuWidget::NativeDestruct()
{
	EndRotateHold();

	if (PreviewActor != nullptr)
	{
		PreviewActor->Destroy();
		PreviewActor = nullptr;
	}
	PreviewMeshComponent = nullptr;
	PreviewHair = nullptr;
	PreviewBeard = nullptr;
	PreviewKeyLightComponent = nullptr;

	Super::NativeDestruct();
}

void UFableMainMenuWidget::OpenMainMenu()
{
	CurrentState = EMainMenuState::Main;
	bIsSlotLoadMode = true;
	PendingCharacterId.Invalidate();
	Rebuild();
}

void UFableMainMenuWidget::Rebuild()
{
	if (WidgetTree == nullptr)
	{
		return;
	}

	AppearanceColumn=nullptr; ChoiceLabels.Reset(); ChoiceCounters.Reset(); ChoiceSwatches.Reset(); SelectionButtons.Reset();
	RaceDescriptionText=nullptr;
	ActionCounter = 0;
	CharacterActionMap.Reset();
	RaceActionMap.Reset();
	SlotActionMap.Reset();
	if (CharacterNameTextBox != nullptr)
	{
		PendingCharacterName = CharacterNameTextBox->GetText().ToString();
	}
	CharacterNameTextBox = nullptr;
	AppearanceSliders.Reset();
	AppearanceValues.Reset();
	PreviewViewport = nullptr;
	PreviewZoomSlider = nullptr;
	bDraggingPreview = false;
	PreviewMeshComponent = nullptr;
	PreviewHair = nullptr;
	PreviewBeard = nullptr;
	PreviewKeyLightComponent = nullptr;
	EndRotateHold();
	if (PreviewActor != nullptr)
	{
		PreviewActor->Destroy();
		PreviewActor = nullptr;
	}

	UCanvasPanel* RootCanvas = Cast<UCanvasPanel>(WidgetTree->RootWidget);
	if (RootCanvas == nullptr)
	{
		RootCanvas = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("RootCanvas"));
		WidgetTree->RootWidget = RootCanvas;
	}

	UBorder* Backdrop = nullptr;
	UBorder* Panel = nullptr;
	for (int32 ChildIndex = 0; ChildIndex < RootCanvas->GetChildrenCount(); ++ChildIndex)
	{
		UBorder* ChildBorder = Cast<UBorder>(RootCanvas->GetChildAt(ChildIndex));
		if (ChildBorder == nullptr)
		{
			continue;
		}

		if (ChildBorder->GetFName() == BackdropWidgetName)
		{
			Backdrop = ChildBorder;
			continue;
		}

		if (ChildBorder->GetFName() == PanelWidgetName)
		{
			Panel = ChildBorder;
		}
	}

	if (Backdrop == nullptr)
	{
		Backdrop = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), BackdropWidgetName);
		RootCanvas->AddChildToCanvas(Backdrop);
	}
	Backdrop->SetBrushColor(UiBackdropColor);
	if (UCanvasPanelSlot* BackdropSlot = Cast<UCanvasPanelSlot>(Backdrop->Slot))
	{
		BackdropSlot->SetAnchors(FAnchors(0.0f, 0.0f, 1.0f, 1.0f));
		BackdropSlot->SetOffsets(FMargin(0.0f));
	}

	if (Panel == nullptr)
	{
		Panel = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), PanelWidgetName);
		RootCanvas->AddChildToCanvas(Panel);
	}

	// Scale artwork and page contents together so their safe margins agree at every resolution.
	Panel->SetBrushColor(FLinearColor::Transparent);
	Panel->SetPadding(FMargin(0.0f));
	if (UCanvasPanelSlot* PanelSlot = Cast<UCanvasPanelSlot>(Panel->Slot))
	{
		PanelSlot->SetAnchors(FAnchors(0.0f, 0.0f, 1.0f, 1.0f));
		PanelSlot->SetOffsets(FMargin(CurrentState == EMainMenuState::Main ? 16.f : 6.f));
	}
	const bool bCover = CurrentState == EMainMenuState::Main;
	const bool bSpreadContent = CurrentState == EMainMenuState::RaceSelect || CurrentState == EMainMenuState::Customization || CurrentState == EMainMenuState::Appearance;
	UOverlay* BookLayers = WidgetTree->ConstructWidget<UOverlay>();
	{
		UScaleBox* Scale = WidgetTree->ConstructWidget<UScaleBox>();
		Scale->SetStretch(EStretch::ScaleToFit);
		Scale->SetStretchDirection(EStretchDirection::Both);
		Panel->SetContent(Scale);
		USizeBox* DesignSize = WidgetTree->ConstructWidget<USizeBox>();
		DesignSize->SetWidthOverride(bCover ? 660.f : 1440.f);
		DesignSize->SetHeightOverride(bCover ? 780.f : 900.f);
		Scale->SetContent(DesignSize);
		DesignSize->SetContent(BookLayers);
	}
	UFableBookSurface* Book = WidgetTree->ConstructWidget<UFableBookSurface>();
	Book->SetOpenBook(!bCover);
	UOverlaySlot* ArtSlot = BookLayers->AddChildToOverlay(Book);
	ArtSlot->SetHorizontalAlignment(HAlign_Fill);
	ArtSlot->SetVerticalAlignment(VAlign_Fill);
	UHorizontalBox* Pages = WidgetTree->ConstructWidget<UHorizontalBox>();
	UOverlaySlot* PageSlot = BookLayers->AddChildToOverlay(Pages);
	PageSlot->SetHorizontalAlignment(HAlign_Fill);
	PageSlot->SetVerticalAlignment(VAlign_Fill);
	PageSlot->SetPadding(bCover ? FMargin(150.0f, 80.0f, 110.0f, 72.0f) : FMargin(112.0f, 88.0f, 112.0f, 180.0f));
	UVerticalBox* PanelContent = WidgetTree->ConstructWidget<UVerticalBox>();
	MenuContent = PanelContent;
	FSlateChildSize PageFill; PageFill.SizeRule = ESlateSizeRule::Fill;
	Pages->AddChildToHorizontalBox(PanelContent)->SetSize(PageFill);
	if (!bCover && !bSpreadContent)
	{
		USpacer* Gutter = WidgetTree->ConstructWidget<USpacer>();
		Gutter->SetSize(FVector2D(90.0f, 1.0f));
		Pages->AddChildToHorizontalBox(Gutter);
		UVerticalBox* StoryPage = WidgetTree->ConstructWidget<UVerticalBox>();
		Pages->AddChildToHorizontalBox(StoryPage)->SetSize(PageFill);
		AddSpacer(StoryPage, 74.0f);
		CreateHeader(StoryPage, TEXT("FableForge"), 40);
		AddTitleOrnament(WidgetTree, StoryPage);

	}

	UE_LOG(LogFableForge, Log, TEXT("Main menu rebuild start. State=%d Panel=%s"), static_cast<int32>(CurrentState), *GetNameSafe(PanelContent));

	AddSpacer(PanelContent, 4.0f);

	switch (CurrentState)
	{
	case EMainMenuState::Main:
		BuildMainState();
		break;
	case EMainMenuState::CharacterSelect:
		BuildCharacterSelectState();
		break;
	case EMainMenuState::SlotSelect:
		BuildSlotSelectState();
		break;
	case EMainMenuState::RaceSelect:
		BuildRaceSelectState();
		break;
	case EMainMenuState::Appearance:
	case EMainMenuState::Customization:
		BuildCustomizationState();
		break;
	default:
		break;
	}

	UE_LOG(LogFableForge, Log, TEXT("Main menu rebuild complete. State=%d Children=%d"), static_cast<int32>(CurrentState), PanelContent->GetChildrenCount());
}

void UFableMainMenuWidget::BuildMainState()
{
	UVerticalBox* Parent = MenuContent.Get();
	if (Parent == nullptr)
	{
		return;
	}
	
	AddSpacer(Parent, 44.0f);
	AddTitleOrnament(WidgetTree, Parent);
	AddSpacer(Parent, 24.0f);
	CreateHeader(Parent, TEXT("FableForge"), 64);
	AddSpacer(Parent, 56.0f);

	const UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	const bool bCanContinue = SaveSubsystem != nullptr && SaveSubsystem->HasAnySavedGames();
	if (bCanContinue)
	{
		CreateActionButton(Parent, TEXT("Continue"), ContinueAction);
		AddSpacer(Parent, 14.0f);
	}

	CreateActionButton(Parent, TEXT("New Game"), NewGameAction, true, 52.0f);
	USpacer* FooterSpace = WidgetTree->ConstructWidget<USpacer>();
	if (UVerticalBoxSlot* FooterSlot = Parent->AddChildToVerticalBox(FooterSpace))
	{
		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FooterSlot->SetSize(FillSize);
	}
	AddSpacer(Parent, 34.0f);
}

void UFableMainMenuWidget::BuildCharacterSelectState()
{
	UVerticalBox* Parent = MenuContent.Get();
	if (Parent == nullptr)
	{
		return;
	}

	CreateHeader(Parent, TEXT("Load Character"));
	CreateSubheader(Parent, TEXT("Select a saved character"));
	AddSpacer(Parent, 8.0f);

	UScrollBox* CharacterScroll = WidgetTree->ConstructWidget<UScrollBox>(UScrollBox::StaticClass());
	CharacterScroll->SetClipping(EWidgetClipping::ClipToBoundsAlways);
	if (UVerticalBoxSlot* ListSlot = Parent->AddChildToVerticalBox(CharacterScroll))
	{
		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		ListSlot->SetSize(FillSize);
	}
	UVerticalBox* CharacterList = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass());
	CharacterScroll->AddChild(CharacterList);

	const UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	bool bAny = false;
	if (SaveSubsystem != nullptr)
	{
		for (const FFableCharacterProfile& Profile : SaveSubsystem->GetCharacters())
		{
			if (!SaveSubsystem->CharacterHasAnySavedSlots(Profile))
			{
				continue;
			}

			bAny = true;
			const FString Label = FString::Printf(TEXT("%s (%s)"), *Profile.CharacterName, *Profile.RaceId);
			CreateActionButton(CharacterList, Label, RegisterCharacterAction(Profile.CharacterId));
			AddSpacer(CharacterList, 4.0f);
		}
	}

	if (!bAny)
	{
		CreateSubheader(Parent, TEXT("No saved characters found."));
		AddSpacer(Parent, 8.0f);
	}

	AddSpacer(Parent, 12.0f);
	CreateActionButton(Parent, TEXT("Back"), BackMainAction, true, 42.0f);
}

void UFableMainMenuWidget::BuildSlotSelectState()
{
	UVerticalBox* Parent = MenuContent.Get();
	if (Parent == nullptr)
	{
		return;
	}

	CreateHeader(Parent, TEXT("Save Slot"));
	CreateSubheader(Parent, bIsSlotLoadMode ? TEXT("Select a save to load.") : TEXT("Select a save slot."));
	AddSpacer(Parent, 8.0f);

	UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	if (SaveSubsystem == nullptr || !PendingCharacterId.IsValid())
	{
		CreateSubheader(Parent, TEXT("No character selected."));
		CreateActionButton(Parent, TEXT("Back"), BackMainAction, true, 42.0f);
		return;
	}

	TArray<FFableSaveSlotMeta> SaveSlots;
	SaveSubsystem->GetSaveSlots(PendingCharacterId, SaveSlots);
	for (const FFableSaveSlotMeta& SlotMeta : SaveSlots)
	{
		const bool bCanUseSlot = bIsSlotLoadMode ? SlotMeta.bHasSave : true;
		CreateActionButton(Parent, BuildSlotLabel(SlotMeta), RegisterSlotAction(SlotMeta.SlotIndex), bCanUseSlot);
		AddSpacer(Parent, 4.0f);
	}

	AddSpacer(Parent, 12.0f);
	CreateActionButton(Parent, TEXT("Back"), bIsSlotLoadMode ? BackCharactersAction : AppearanceAction, true, 42.0f);
}

void UFableMainMenuWidget::BuildRaceSelectState()
{
	UVerticalBox* Parent = MenuContent.Get();
	if (Parent == nullptr)
	{
		return;
	}



	TArray<FFableRaceDefinition> Races;
	const UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	if (SaveSubsystem != nullptr)
	{
		Races = SaveSubsystem->GetRaces();
	}

	if (Races.Num() == 0)
	{
		FFableRaceDefinition FallbackRace;
		FallbackRace.Id = TEXT("human");
		FallbackRace.Name = TEXT("Human");
		FallbackRace.Description = TEXT("Balanced and adaptable.");
		Races.Add(FallbackRace);
	}

	auto FindRaceById = [&](const FString& RaceId) -> const FFableRaceDefinition*
	{
		for (const FFableRaceDefinition& Race : Races)
		{
			if (Race.Id == RaceId)
			{
				return &Race;
			}
		}
		return nullptr;
	};

	if (FindRaceById(PendingRaceId) == nullptr)
	{
		PendingRaceId = Races[0].Id;
	}



	UHorizontalBox* MainRow = WidgetTree->ConstructWidget<UHorizontalBox>();
	if (UVerticalBoxSlot* RowSlot = Parent->AddChildToVerticalBox(MainRow))
	{
		RowSlot->SetHorizontalAlignment(HAlign_Fill);
		RowSlot->SetVerticalAlignment(VAlign_Fill);
		RowSlot->SetPadding(FMargin(0.0f));

		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		RowSlot->SetSize(FillSize);
	}

	UVerticalBox* LeftColumn = WidgetTree->ConstructWidget<UVerticalBox>();
	if (UHorizontalBoxSlot* LeftSlot = MainRow->AddChildToHorizontalBox(LeftColumn))
	{
		LeftSlot->SetPadding(FMargin(0.0f, 0.0f, 45.0f, 0.0f));

		FSlateChildSize LeftSize;
		LeftSize.SizeRule = ESlateSizeRule::Fill;
		LeftSize.Value = 1.0f;
		LeftSlot->SetSize(LeftSize);
	}

	CreateHeader(LeftColumn, TEXT("Choose Race"), 38);
	CreateSubheader(LeftColumn, TEXT("Select your character’s race."));
	AddSpacer(LeftColumn, 20.0f);
	AddSpacer(LeftColumn, 6.0f);
	// Two columns keep every current race visible without scrolling.
	for (int32 Index = 0; Index < Races.Num(); Index += 2)
	{
		UHorizontalBox* Row = WidgetTree->ConstructWidget<UHorizontalBox>();
		LeftColumn->AddChildToVerticalBox(Row)->SetPadding(FMargin(0.f, 0.f, 0.f, 12.f));
		for (int32 Column = 0; Column < 2; ++Column)
		{
			UVerticalBox* Cell = WidgetTree->ConstructWidget<UVerticalBox>();
			UHorizontalBoxSlot* CellSlot = Row->AddChildToHorizontalBox(Cell);
			FSlateChildSize CellSize; CellSize.SizeRule = ESlateSizeRule::Fill;
			CellSlot->SetSize(CellSize);
			CellSlot->SetPadding(FMargin(Column == 0 ? 0.f : 6.f, 0.f, Column == 0 ? 6.f : 0.f, 0.f));
			if (Index + Column >= Races.Num()) continue;
			const FFableRaceDefinition& Race = Races[Index + Column];
			UFableActionButton* RaceButton = CreateActionButton(Cell, Race.Name, RegisterRaceAction(Race.Id), true, 56.f);
			RaceButton->SetBackgroundColor(Race.Id == PendingRaceId ? UiButtonSelectedColor : MainMenuUiButtonColor);
		}
	}

	AddSpacer(LeftColumn,18.f);
	UTextBlock* RaceSummary=WidgetTree->ConstructWidget<UTextBlock>();
	RaceDescriptionText=RaceSummary;
	RaceSummary->SetText(FText::FromString(FableAppearance::RaceDescription(PendingRaceId)));
	RaceSummary->SetFont(FableBookStyle::Font(22));
	RaceSummary->SetColorAndOpacity(FableBookStyle::Ink);
	RaceSummary->SetAutoWrapText(true);
	RaceSummary->SetLineHeightPercentage(1.25f);
	LeftColumn->AddChildToVerticalBox(RaceSummary)->SetPadding(FMargin(10,8));
	USpacer* RaceSpace=WidgetTree->ConstructWidget<USpacer>();
	LeftColumn->AddChildToVerticalBox(RaceSpace)->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
	UHorizontalBox* RaceFooter=WidgetTree->ConstructWidget<UHorizontalBox>();
	LeftColumn->AddChildToVerticalBox(RaceFooter);
	AddCompactButton(RaceFooter,TEXT("Back"),BackCustomizationAction);
	AddCompactButton(RaceFooter,TEXT("Next"),ConfirmRaceAction,true);

	UVerticalBox* RightColumn = WidgetTree->ConstructWidget<UVerticalBox>();
	if (UHorizontalBoxSlot* RightSlot = MainRow->AddChildToHorizontalBox(RightColumn))
	{
		RightSlot->SetPadding(FMargin(45.0f, 0.0f, 0.0f, 0.0f));

		FSlateChildSize RightSize;
		RightSize.SizeRule = ESlateSizeRule::Fill;
		RightSize.Value = 1.0f;
		RightSlot->SetSize(RightSize);
	}

	BuildPreviewPane(RightColumn);
}

void UFableMainMenuWidget::BuildCustomizationState()
{
	UVerticalBox* Parent = MenuContent.Get();
	if (Parent == nullptr)
	{
		return;
	}



	UHorizontalBox* MainRow = WidgetTree->ConstructWidget<UHorizontalBox>();
	if (UVerticalBoxSlot* RowSlot = Parent->AddChildToVerticalBox(MainRow))
	{
		RowSlot->SetHorizontalAlignment(HAlign_Fill);
		RowSlot->SetVerticalAlignment(VAlign_Fill);
		RowSlot->SetPadding(FMargin(0.0f));

		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		RowSlot->SetSize(FillSize);
	}

	UVerticalBox* LeftColumn = WidgetTree->ConstructWidget<UVerticalBox>();
	if (UHorizontalBoxSlot* LeftSlot = MainRow->AddChildToHorizontalBox(LeftColumn))
	{
		LeftSlot->SetPadding(FMargin(0.0f, 0.0f, 45.0f, 0.0f));
		LeftSlot->SetHorizontalAlignment(HAlign_Fill);
		LeftSlot->SetVerticalAlignment(VAlign_Fill);

		FSlateChildSize LeftSize;
		LeftSize.SizeRule = ESlateSizeRule::Fill;
		LeftSize.Value = 1.0f;
		LeftSlot->SetSize(LeftSize);
	}

	if (CurrentState == EMainMenuState::Appearance)
	{
		AppearanceColumn=LeftColumn;
		BuildAppearanceControls(LeftColumn);
	}
	else
	{
	CreateHeader(LeftColumn, TEXT("Create Character"), 38);
	AddSpacer(LeftColumn, 28.0f);
	CreateSubheader(LeftColumn, TEXT("Name"));
	CharacterNameTextBox = WidgetTree->ConstructWidget<UEditableTextBox>();
	CharacterNameTextBox->SetHintText(FText::FromString(TEXT("Enter character name")));
	CharacterNameTextBox->SetText(FText::FromString(PendingCharacterName));
	CharacterNameTextBox->SetForegroundColor(MainMenuUiTextColor);
	FEditableTextBoxStyle NameTextBoxStyle = CharacterNameTextBox->GetWidgetStyle();
	FSlateFontInfo NameFont = FableBookStyle::Font(24);
	NameFont.Size = 24;
	NameFont.TypefaceFontName = TEXT("Regular");
	NameTextBoxStyle.TextStyle.SetFont(NameFont);
	NameTextBoxStyle.SetPadding(FMargin(12.0f, 10.0f));
	NameTextBoxStyle.SetBackgroundColor(FSlateColor(FLinearColor(0.70f, 0.57f, 0.37f, 1.0f)));
	NameTextBoxStyle.SetForegroundColor(FSlateColor(MainMenuUiTextColor));
	NameTextBoxStyle.SetFocusedForegroundColor(FSlateColor(MainMenuUiTextColor));
	NameTextBoxStyle.SetReadOnlyForegroundColor(FSlateColor(UiMutedTextColor));
	CharacterNameTextBox->SetWidgetStyle(NameTextBoxStyle);
	CharacterNameTextBox->SetJustification(ETextJustify::Center);
	if (UVerticalBoxSlot* NameSlot = LeftColumn->AddChildToVerticalBox(CharacterNameTextBox))
	{
		NameSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 10.0f));
	}

	CreateSubheader(LeftColumn, TEXT("Body type"));
	UHorizontalBox* GenderRow=WidgetTree->ConstructWidget<UHorizontalBox>();
	LeftColumn->AddChildToVerticalBox(GenderRow)->SetPadding(FMargin(0,4,0,0));
	AddBodyTypeButton(GenderRow,false);
	AddBodyTypeButton(GenderRow,true);
	USpacer* IdentitySpace=WidgetTree->ConstructWidget<USpacer>();
	LeftColumn->AddChildToVerticalBox(IdentitySpace)->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
	UHorizontalBox* IdentityFooter=WidgetTree->ConstructWidget<UHorizontalBox>();
	LeftColumn->AddChildToVerticalBox(IdentityFooter)->SetPadding(FMargin(0,16,0,0));
	AddCompactButton(IdentityFooter,TEXT("Back"),BackMainAction);
	AddCompactButton(IdentityFooter,TEXT("Next"),BackRacesAction,true);

	}

	UVerticalBox* RightColumn = WidgetTree->ConstructWidget<UVerticalBox>();
	if (UHorizontalBoxSlot* RightSlot = MainRow->AddChildToHorizontalBox(RightColumn))
	{
		RightSlot->SetPadding(FMargin(45.0f, 0.0f, 0.0f, 0.0f));
		RightSlot->SetHorizontalAlignment(HAlign_Fill);
		RightSlot->SetVerticalAlignment(VAlign_Fill);

		FSlateChildSize RightSize;
		RightSize.SizeRule = ESlateSizeRule::Fill;
		RightSize.Value = 1.0f;
		RightSlot->SetSize(RightSize);
	}

	BuildPreviewPane(RightColumn);
}

void UFableMainMenuWidget::BuildPreviewPane(UVerticalBox* RightColumn)
{
	UBorder* PreviewBorder = WidgetTree->ConstructWidget<UBorder>();
	PreviewBorder->SetBrushColor(FLinearColor::Transparent);
	PreviewBorder->SetPadding(FMargin(0.0f));
	if (UVerticalBoxSlot* PreviewSlot = RightColumn->AddChildToVerticalBox(PreviewBorder))
	{
		PreviewSlot->SetHorizontalAlignment(HAlign_Fill);
		PreviewSlot->SetVerticalAlignment(VAlign_Fill);
		PreviewSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 12.0f));

		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		PreviewSlot->SetSize(FillSize);
	}

	PreviewViewport = WidgetTree->ConstructWidget<UFableTransparentViewport>();
	PreviewViewport->SetVisibility(ESlateVisibility::HitTestInvisible);
	PreviewBorder->SetContent(PreviewViewport);
	PreviewBorder->SetCursor(EMouseCursor::GrabHand);
	PreviewBorder->SetToolTipText(FText::FromString(TEXT("Drag sideways to rotate, vertically to pan. Scroll to zoom. Double-click to reset.")));

	UHorizontalBox* CameraRow = WidgetTree->ConstructWidget<UHorizontalBox>();
	RightColumn->AddChildToVerticalBox(CameraRow)->SetPadding(FMargin(0,8,0,0));
	UTextBlock* ZoomLabel=WidgetTree->ConstructWidget<UTextBlock>();
	ZoomLabel->SetText(FText::FromString(TEXT("Zoom")));
	ZoomLabel->SetFont(FableBookStyle::Font(18));
	ZoomLabel->SetColorAndOpacity(FableBookStyle::Ink);
	CameraRow->AddChildToHorizontalBox(ZoomLabel)->SetVerticalAlignment(VAlign_Center);
	PreviewZoomSlider=WidgetTree->ConstructWidget<USlider>(USlider::StaticClass(),MakeUniqueObjectName(WidgetTree,USlider::StaticClass(),TEXT("PreviewZoom")));
	PreviewZoomSlider->SetValue(PreviewZoom);
	PreviewZoomSlider->SetStepSize(.025f);
	PreviewZoomSlider->SetSliderBarColor(FLinearColor(.25f,.16f,.08f));
	PreviewZoomSlider->SetSliderHandleColor(FLinearColor(.55f,.33f,.11f));
	PreviewZoomSlider->OnValueChanged.AddDynamic(this,&UFableMainMenuWidget::HandlePreviewZoomChanged);
	UHorizontalBoxSlot* ZoomSlot=CameraRow->AddChildToHorizontalBox(PreviewZoomSlider);
	ZoomSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
	ZoomSlot->SetPadding(FMargin(14,0));
	AddCompactButton(CameraRow,TEXT("Reset view"),TEXT("preview_reset"));
	UTextBlock* PreviewHint=WidgetTree->ConstructWidget<UTextBlock>();
	PreviewHint->SetText(FText::FromString(TEXT("Drag: rotate / pan  ·  Scroll: zoom")));
	PreviewHint->SetFont(FableBookStyle::Font(16));
	PreviewHint->SetColorAndOpacity(UiMutedTextColor);
	PreviewHint->SetJustification(ETextJustify::Center);
	RightColumn->AddChildToVerticalBox(PreviewHint)->SetPadding(FMargin(0,6,0,0));

	if (EnsurePreviewActor())
	{
		UpdatePreviewMesh();
	}
}

void UFableMainMenuWidget::CreateHeader(UVerticalBox* Parent, const FString& Text, int32 FontSize) const
{
	if (Parent == nullptr)
	{
		return;
	}

	UTextBlock* Header = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	Header->SetText(FText::FromString(Text));
	Header->SetColorAndOpacity(FSlateColor(CurrentState == EMainMenuState::Main ? FableBookStyle::Gold : FableBookStyle::Ink));
	Header->SetJustification(ETextJustify::Center);
	FSlateFontInfo FontInfo = FableBookStyle::Font(FontSize, true);
	FontInfo.Size = FontSize;
	FontInfo.TypefaceFontName = NAME_None;
	FontInfo.LetterSpacing = 0;
	Header->SetFont(FontInfo);

	if (UVerticalBoxSlot* Slot = Parent->AddChildToVerticalBox(Header))
	{
		Slot->SetHorizontalAlignment(HAlign_Center);
		Slot->SetPadding(FMargin(0.0f, 14.0f, 0.0f, 4.0f));
	}
}

void UFableMainMenuWidget::CreateSubheader(UVerticalBox* Parent, const FString& Text) const
{
	if (Parent == nullptr)
	{
		return;
	}

	UTextBlock* Subheader = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	Subheader->SetText(FText::FromString(Text));
	Subheader->SetColorAndOpacity(FSlateColor(CurrentState == EMainMenuState::Main ? FLinearColor(0.72f, 0.53f, 0.28f) : UiMutedTextColor));
	Subheader->SetJustification(ETextJustify::Center);
	Subheader->SetAutoWrapText(true);
	FSlateFontInfo SubheaderFont = FableBookStyle::Font(19);
	SubheaderFont.Size = 19;
	SubheaderFont.TypefaceFontName = TEXT("Regular");
	SubheaderFont.LetterSpacing = 50;
	Subheader->SetFont(SubheaderFont);

	if (UVerticalBoxSlot* Slot = Parent->AddChildToVerticalBox(Subheader))
	{
		Slot->SetHorizontalAlignment(HAlign_Fill);
		Slot->SetPadding(FMargin(20.0f, 2.0f, 20.0f, 2.0f));
	}
}

void UFableMainMenuWidget::AddSpacer(UVerticalBox* Parent, float Height) const
{
	if (Parent == nullptr)
	{
		return;
	}

	USpacer* Spacer = WidgetTree->ConstructWidget<USpacer>(USpacer::StaticClass());
	Spacer->SetSize(FVector2D(1.0f, Height));
	Parent->AddChildToVerticalBox(Spacer);
}

UFableActionButton* UFableMainMenuWidget::CreateActionButton(UVerticalBox* Parent, const FString& Label, FName ActionId, bool bEnabled, float Height)
{
	if (Parent == nullptr)
	{
		return nullptr;
	}

	UFableActionButton* Button = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass());
	Button->InitializeAction(ActionId);
	SelectionButtons.Add(ActionId,Button);
	Button->SetIsEnabled(bEnabled);
	Button->OnActionClicked.AddDynamic(this, &UFableMainMenuWidget::HandleActionClicked);
	FableBookStyle::ApplyButton(Button, CurrentState == EMainMenuState::Main);

	UTextBlock* LabelWidget = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	LabelWidget->SetText(FText::FromString(Label));
	LabelWidget->SetJustification(ETextJustify::Center);
	LabelWidget->SetColorAndOpacity(FSlateColor(CurrentState == EMainMenuState::Main ? FableBookStyle::Gold : FableBookStyle::Ink));
	LabelWidget->SetAutoWrapText(false);
	LabelWidget->SetTextOverflowPolicy(ETextOverflowPolicy::Ellipsis);
	FSlateFontInfo LabelFont = FableBookStyle::Font(22, true);
	LabelFont.Size = CurrentState == EMainMenuState::Main ? 26 : 22;
	LabelFont.TypefaceFontName = NAME_None;
	LabelWidget->SetFont(LabelFont);
	Button->AddChild(LabelWidget);

	USizeBox* ButtonSize = WidgetTree->ConstructWidget<USizeBox>();
	ButtonSize->SetMinDesiredHeight(CurrentState == EMainMenuState::Main ? 68.f : FMath::Max(Height, 58.f));
	ButtonSize->SetContent(Button);
	if (UVerticalBoxSlot* ButtonSlot = Parent->AddChildToVerticalBox(ButtonSize))
	{
		ButtonSlot->SetPadding(FMargin(0.f));
		ButtonSlot->SetHorizontalAlignment(HAlign_Fill);
		ButtonSlot->SetVerticalAlignment(VAlign_Center);
	}

	if (UButtonSlot* ContentSlot = Cast<UButtonSlot>(LabelWidget->Slot))
	{
		ContentSlot->SetHorizontalAlignment(HAlign_Center);
		ContentSlot->SetVerticalAlignment(VAlign_Center);
		ContentSlot->SetPadding(FMargin(22.f, 12.f));
	}

	return Button;
}

FName UFableMainMenuWidget::RegisterCharacterAction(const FGuid& CharacterId)
{
	const FName Action = MakeActionName(TEXT("character"));
	CharacterActionMap.Add(Action, CharacterId);
	return Action;
}

FName UFableMainMenuWidget::RegisterRaceAction(const FString& RaceId)
{
	const FName Action = MakeActionName(TEXT("race"));
	RaceActionMap.Add(Action, RaceId);
	return Action;
}

FName UFableMainMenuWidget::RegisterSlotAction(int32 SlotIndex)
{
	const FName Action = MakeActionName(TEXT("slot"));
	SlotActionMap.Add(Action, SlotIndex);
	return Action;
}

FName UFableMainMenuWidget::MakeActionName(const FString& Prefix)
{
	++ActionCounter;
	return FName(*FString::Printf(TEXT("%s_%d"), *Prefix, ActionCounter));
}

void UFableMainMenuWidget::ApplyCharacterCreation()
{
	UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	if (SaveSubsystem == nullptr)
	{
		return;
	}

	const FString CharacterName = CharacterNameTextBox != nullptr ? CharacterNameTextBox->GetText().ToString() : PendingCharacterName;
	PendingCharacterId = SaveSubsystem->CreateCharacter(CharacterName, PendingRaceId, PendingGender, PendingBodyMorphs, PendingHeightScale, PendingSkinColor, PendingHairColor, PendingEyeColor, PendingHairStyle, PendingBeardStyle);
	// New characters always use the first save slot.  The slot picker remains
	// available when loading an existing character, but creation should flow
	// directly into the game instead of asking the player to choose a slot.
	if (AFableForgePlayerController* PlayerController = Cast<AFableForgePlayerController>(GetOwningPlayer()))
	{
		PlayerController->EnterGameFromCharacterSlot(PendingCharacterId, 0, true);
	}
}

void UFableMainMenuWidget::ResetAppearance(bool bResetColors)
{
 PendingBodyMorphs.Reset();
 for(const FableAppearance::FControl& Control : FableAppearance::Controls())
 {
  if(Control.Name != TEXT("Height")) PendingBodyMorphs.Add(Control.Name,FableAppearance::Range(Control.Name,PendingRaceId,PendingGender).Default);
 }
 PendingHeightScale=FableAppearance::Range(TEXT("Height"),PendingRaceId,PendingGender).Default;
 PendingSkinColor=FableAppearance::DefaultSkinColor(PendingRaceId);
 if(bResetColors)
 {
  const auto& HairColors=FableAppearanceAssets::ListHairColors();
  const auto& EyeColors=FableAppearanceAssets::ListEyeColors();
  PendingHairColor=HairColors[FMath::Min(1,HairColors.Num()-1)].Color;
  PendingEyeColor=EyeColors[FMath::Min(1,EyeColors.Num()-1)].Color;
 }
}

void UFableMainMenuWidget::HandleAppearanceChanged(float Value)
{
 (void)Value;
 for(const auto& Entry : AppearanceSliders)
 {
  const float Weight=Entry.Value->GetValue();
  if(Entry.Key==TEXT("Height")) PendingHeightScale=Weight;
  else PendingBodyMorphs.Add(Entry.Key,Weight);
  if(UTextBlock* Label=AppearanceValues.FindRef(Entry.Key))
   Label->SetText(FText::FromString(Entry.Key==TEXT("Height") ? FString::Printf(TEXT("%d cm"),FMath::RoundToInt(177.f*Weight)) : FString::Printf(TEXT("%d"),FMath::RoundToInt(Weight*100.f))));
 }
 ApplyPreviewAppearance();
}

void UFableMainMenuWidget::ApplyPreviewAppearance()
{
 if(!PreviewMeshComponent) return;
 PreviewMeshComponent->ClearMorphTargets();
 for(const auto& Entry : PendingBodyMorphs)
 {
  if(PendingGender==EFableGender::Female && Entry.Key==TEXT("FemaleBody")) continue;
  PreviewMeshComponent->SetMorphTarget(Entry.Key,Entry.Value);
 }
 PreviewMeshComponent->SetRelativeScale3D(FVector(PendingHeightScale));
 const USkeletalMesh* Mesh=PreviewMeshComponent->GetSkeletalMeshAsset();
 if(Mesh) PreviewMeshComponent->SetRelativeLocation(FVector(0,0,-Mesh->GetBounds().Origin.Z*PendingHeightScale));
 const FLinearColor Colors[]={PendingHairColor,PendingEyeColor,PendingSkinColor};
 const FName Parameters[]={TEXT("HairTint"),TEXT("EyeTint"),TEXT("SkinTint")};
 for(int32 Index=0;Index<3 && Index<PreviewMeshComponent->GetNumMaterials();++Index)
 {
  UMaterialInstanceDynamic* MID=Cast<UMaterialInstanceDynamic>(PreviewMeshComponent->GetMaterial(Index));
  if(!MID) MID=PreviewMeshComponent->CreateAndSetMaterialInstanceDynamic(Index);
  if(MID) MID->SetVectorParameterValue(Parameters[Index],Colors[Index]);
 }
 UpdatePreviewHair();
 UpdatePreviewCamera();
}

bool UFableMainMenuWidget::IsOverPreview(const FPointerEvent& Event) const
{
 return PreviewViewport && PreviewViewport->GetCachedGeometry().IsUnderLocation(Event.GetScreenSpacePosition());
}

FReply UFableMainMenuWidget::NativeOnMouseButtonDown(const FGeometry& Geometry, const FPointerEvent& Event)
{
 if(Event.GetEffectingButton()==EKeys::LeftMouseButton && IsOverPreview(Event))
 {
  bDraggingPreview=true;
  PreviewDragPosition=Geometry.AbsoluteToLocal(Event.GetScreenSpacePosition());
  return FReply::Handled().CaptureMouse(TakeWidget()).SetUserFocus(TakeWidget());
 }
 return Super::NativeOnMouseButtonDown(Geometry,Event);
}

FReply UFableMainMenuWidget::NativeOnMouseButtonUp(const FGeometry& Geometry, const FPointerEvent& Event)
{
 if(bDraggingPreview && Event.GetEffectingButton()==EKeys::LeftMouseButton)
 {
  bDraggingPreview=false;
  return FReply::Handled().ReleaseMouseCapture();
 }
 return Super::NativeOnMouseButtonUp(Geometry,Event);
}

FReply UFableMainMenuWidget::NativeOnMouseMove(const FGeometry& Geometry, const FPointerEvent& Event)
{
 if(bDraggingPreview)
 {
  const FVector2D Position=Geometry.AbsoluteToLocal(Event.GetScreenSpacePosition());
  const FVector2D Delta=Position-PreviewDragPosition;
  ApplyRotationDelta(Delta.X*.5f);
  // Dragging vertically moves the subject under the pointer. Scale sensitivity
  // with zoom so inspecting a face does not pan as far as a full-body drag.
  PreviewPanOffset+=Delta.Y*FMath::Lerp(.65f,.18f,PreviewZoom);
  UpdatePreviewCamera();
  PreviewDragPosition=Position;
  return FReply::Handled();
 }
 return Super::NativeOnMouseMove(Geometry,Event);
}

FReply UFableMainMenuWidget::NativeOnKeyDown(const FGeometry& Geometry, const FKeyEvent& Event)
{
 if(HasKeyboardFocus() && PreviewViewport && (Event.GetKey()==EKeys::Left || Event.GetKey()==EKeys::Right))
 {
  ApplyRotationDelta(Event.GetKey()==EKeys::Left ? -8.f : 8.f);
  return FReply::Handled();
 }
 return Super::NativeOnKeyDown(Geometry,Event);
}

FReply UFableMainMenuWidget::NativeOnMouseWheel(const FGeometry& Geometry, const FPointerEvent& Event)
{
 if(IsOverPreview(Event))
 {
  SetPreviewZoom(PreviewZoom+Event.GetWheelDelta()*.075f);
  return FReply::Handled();
 }
 return Super::NativeOnMouseWheel(Geometry,Event);
}

FReply UFableMainMenuWidget::NativeOnMouseButtonDoubleClick(const FGeometry& Geometry, const FPointerEvent& Event)
{
 if(Event.GetEffectingButton()==EKeys::LeftMouseButton && IsOverPreview(Event))
 {
  ResetPreviewView();
  return FReply::Handled().ReleaseMouseCapture();
 }
 return Super::NativeOnMouseButtonDoubleClick(Geometry,Event);
}

void UFableMainMenuWidget::NativeOnMouseCaptureLost(const FCaptureLostEvent& Event)
{
 bDraggingPreview=false;
 Super::NativeOnMouseCaptureLost(Event);
}

void UFableMainMenuWidget::SetPreviewZoom(float Zoom)
{
 PreviewZoom=FMath::Clamp(Zoom,0.f,1.f);
 if(PreviewZoomSlider && !FMath::IsNearlyEqual(PreviewZoomSlider->GetValue(),PreviewZoom))
  PreviewZoomSlider->SetValue(PreviewZoom);
 UpdatePreviewCamera();
}

void UFableMainMenuWidget::HandlePreviewZoomChanged(float Value)
{
 SetPreviewZoom(Value);
}

void UFableMainMenuWidget::ResetPreviewView()
{
 bDraggingPreview=false;
 PreviewYawDegrees=-90.f;
 PreviewPanOffset=0.f;
 ApplyRotationDelta(0.f);
 SetPreviewZoom(0.f);
}

void UFableMainMenuWidget::UpdatePreviewCamera()
{
 if(!PreviewViewport || !PreviewMeshComponent || !PreviewMeshComponent->GetSkeletalMeshAsset()) return;
 const float HalfHeight=PreviewMeshComponent->GetSkeletalMeshAsset()->GetBounds().BoxExtent.Z;
 const float Height=HalfHeight*PendingHeightScale;
 const float BaseFocus=FMath::Lerp(-Height*.05f,Height*.82f,PreviewZoom);
 const float FocusZ=FMath::Clamp(BaseFocus+PreviewPanOffset,-Height*.95f,Height*.95f);
 PreviewPanOffset=FocusZ-BaseFocus;
 const FVector Focus(0,0,FocusZ);
 const float Distance=FMath::Lerp(HalfHeight*1.75f*FMath::Max(1.f,PendingHeightScale),45.f,PreviewZoom);
 PreviewViewport->SetViewLocation(Focus+FVector(Distance,0,0));
 PreviewViewport->SetViewRotation(FRotator(0,180,0));
}

void UFableMainMenuWidget::UpdatePreviewMesh()
{
	if (!EnsurePreviewActor())
	{
		return;
	}

	USkeletalMesh* PreviewMesh = LoadObject<USkeletalMesh>(nullptr, PendingGender==EFableGender::Female ? TEXT("/Game/Characters/PlayableCharacter/Meshes/femalecharacter_v2.femalecharacter_v2") : MainMenuBaseCharacterMeshPath);
	if (PreviewMesh == nullptr)
	{
		PreviewMesh = LoadObject<USkeletalMesh>(nullptr, LegacyMainMenuCharacterMeshPath);
	}
	if (PreviewMesh == nullptr)
	{
		UE_LOG(LogFableForge, Warning, TEXT("Preview mesh could not be loaded: %s"), MainMenuBaseCharacterMeshPath);
		return;
	}

	PreviewMeshComponent->SetSkeletalMesh(PreviewMesh);
	PreviewMeshComponent->EmptyOverrideMaterials();
	// Use the existing character idle instead of displaying the reference A-pose.
	UAnimSequence* Idle = LoadObject<UAnimSequence>(nullptr,
		TEXT("/Game/Characters/PlayableCharacter/Anims/Unarmed/MM_Idle.MM_Idle"));
	if (Idle && Idle->GetSkeleton() && Idle->GetSkeleton()->IsCompatibleMesh(PreviewMesh))
	{
		PreviewMeshComponent->PlayAnimation(Idle, true);
		UE_LOG(LogFableForge, Log, TEXT("Character preview idle enabled."));
	}

	PreviewMeshComponent->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	PreviewMeshComponent->SetCastShadow(false);
	PreviewMeshComponent->SetReceivesDecals(false);
	const FBoxSphereBounds MeshBounds = PreviewMeshComponent->CalcBounds(FTransform::Identity);
	const float HalfHeight = FMath::Max(MeshBounds.BoxExtent.Z, 80.0f);
	const float MaxHalfWidth = static_cast<float>(FMath::Max3(MeshBounds.BoxExtent.X, MeshBounds.BoxExtent.Y, 42.0));
	const float CenterOffsetZ = -MeshBounds.Origin.Z;
	const float CameraDistance = FMath::Clamp(FMath::Max(HalfHeight, MaxHalfWidth) * 1.75f, 140.0f, 320.0f);
	const float CenteredViewZ = CenterOffsetZ + MeshBounds.Origin.Z;

	PreviewMeshComponent->SetRelativeLocation(FVector(0.0f, 0.0f, CenterOffsetZ));
	PreviewMeshComponent->SetRelativeRotation(FRotator(0.0f, PreviewYawDegrees, 0.0f));
	ApplyPreviewAppearance();

	if (PreviewViewport != nullptr)
	{
		UpdatePreviewCamera();
	}

	if (PreviewKeyLightComponent != nullptr)
	{
		PreviewKeyLightComponent->SetWorldLocation(FVector(CameraDistance * 0.75f, -CameraDistance * 0.35f, HalfHeight * 0.85f));
	}
#if WITH_EDITOR
	// Editor-only first-use permutations must finish before showing the preview.
	FAssetCompilingManager::Get().FinishAllCompilation();
#endif
}

bool UFableMainMenuWidget::EnsurePreviewActor()
{
	if (PreviewViewport == nullptr)
	{
		return false;
	}

	if (PreviewActor != nullptr && PreviewMeshComponent != nullptr)
	{
		return true;
	}

	PreviewViewport->TakeWidget();
	PreviewViewport->SetEnableAdvancedFeatures(false);
	PreviewViewport->SetBackgroundColor(FLinearColor::Black);
	PreviewViewport->SetLightIntensity(0.65f);
	PreviewViewport->SetSkyIntensity(0.5f);
	PreviewViewport->SetViewLocation(FVector(220.0f, 0.0f, 0.0f));
	PreviewViewport->SetViewRotation(FRotator(0.0f, 180.0f, 0.0f));

	PreviewActor = PreviewViewport->Spawn(AActor::StaticClass());
	if (PreviewActor == nullptr)
	{
		UE_LOG(LogFableForge, Warning, TEXT("Failed to spawn preview actor in viewport."));
		return false;
	}

	PreviewMeshComponent = NewObject<USkeletalMeshComponent>(PreviewActor, TEXT("PreviewMeshComponent"));
	if (PreviewMeshComponent == nullptr)
	{
		return false;
	}

	PreviewMeshComponent->RegisterComponent();
	PreviewActor->SetRootComponent(PreviewMeshComponent);

	PreviewKeyLightComponent = NewObject<UPointLightComponent>(PreviewActor, TEXT("PreviewKeyLight"));
	if (PreviewKeyLightComponent != nullptr)
	{
		PreviewKeyLightComponent->SetupAttachment(PreviewMeshComponent);
		// Keep the studio light fixed while the model rotates.
		PreviewKeyLightComponent->SetAbsolute(true, true, true);
		PreviewKeyLightComponent->SetIntensityUnits(ELightUnits::Lumens);
		PreviewKeyLightComponent->SetIntensity(80.0f);
		PreviewKeyLightComponent->SetAttenuationRadius(520.0f);
		PreviewKeyLightComponent->SetSourceRadius(90.0f);
		PreviewKeyLightComponent->SetSoftSourceRadius(120.0f);
		PreviewKeyLightComponent->SetSpecularScale(0.1f);
		PreviewKeyLightComponent->SetCastShadows(false);
		PreviewKeyLightComponent->SetLightColor(FColor(242, 240, 235));
		PreviewKeyLightComponent->SetRelativeLocation(FVector(78.0f, 0.0f, 200.0f));
		PreviewKeyLightComponent->RegisterComponent();
	}

	return true;
}

void UFableMainMenuWidget::ApplyRotationDelta(float DeltaYaw)
{
	PreviewYawDegrees += DeltaYaw;
	if (PreviewMeshComponent != nullptr)
	{
		PreviewMeshComponent->SetRelativeRotation(FRotator(0.0f, PreviewYawDegrees, 0.0f));
	}
}

void UFableMainMenuWidget::BeginRotateHold(float DeltaYaw)
{
	PreviewHoldDeltaYaw = DeltaYaw;
	ApplyRotationDelta(DeltaYaw);

	if (UWorld* World = GetWorld())
	{
		World->GetTimerManager().SetTimer(PreviewRotateTimerHandle, this, &UFableMainMenuWidget::TickRotateHold, 0.016f, true);
	}
}

void UFableMainMenuWidget::EndRotateHold()
{
	PreviewHoldDeltaYaw = 0.0f;
	if (UWorld* World = GetWorld())
	{
		World->GetTimerManager().ClearTimer(PreviewRotateTimerHandle);
	}
}

void UFableMainMenuWidget::HandleRotateLeftPressed()
{
	BeginRotateHold(2.0f);
}

void UFableMainMenuWidget::HandleRotateRightPressed()
{
	BeginRotateHold(-2.0f);
}

void UFableMainMenuWidget::HandleRotateReleased()
{
	EndRotateHold();
}

void UFableMainMenuWidget::TickRotateHold()
{
	if (FMath::IsNearlyZero(PreviewHoldDeltaYaw))
	{
		return;
	}

	ApplyRotationDelta(PreviewHoldDeltaYaw);
}

FString UFableMainMenuWidget::BuildSlotLabel(const FFableSaveSlotMeta& SlotMeta) const
{
	const FString Prefix = FString::Printf(TEXT("Slot %d"), SlotMeta.SlotIndex + 1);
	if (!SlotMeta.bHasSave)
	{
		return Prefix + TEXT(" - Empty");
	}

	if (SlotMeta.LastPlayedUtc.IsEmpty())
	{
		return Prefix + TEXT(" - Saved");
	}

	return Prefix + FString::Printf(TEXT(" - %s"), *SlotMeta.LastPlayedUtc);
}

void UFableMainMenuWidget::HandleActionClicked(FName ActionId)
{
 const FString Action=ActionId.ToString();
 if(Action.StartsWith(TEXT("appearance_category_")))
 {
  int32 Category=FMath::Clamp(FCString::Atoi(*Action.RightChop(20)),0,7);
  if(Category==6) Category=7;
  if(Category==AppearanceCategory || (Category==1 && AppearanceCategory>=1 && AppearanceCategory<=5)) return;
  AppearanceCategory=Category;
  RefreshAppearanceSection(); return;
 }
 if(Action==TEXT("preview_reset"))
 {
  ResetPreviewView(); return;
 }
 if(Action.StartsWith(TEXT("cycle_")))
 {
  const int32 Step=Action.EndsWith(TEXT("_prev")) ? -1 : 1;
  auto Next=[&](int32 Index,int32 Count){ return Count>0 ? (Index+Step+Count)%Count : 0; };
  if(Action.StartsWith(TEXT("cycle_feature_"))) AppearanceCategory=1+Next(AppearanceCategory-1,5);
  else if(Action.StartsWith(TEXT("cycle_hair_")) || Action.StartsWith(TEXT("cycle_beard_")))
  {
   const bool Beard=Action.StartsWith(TEXT("cycle_beard_"));
   const auto& Styles=Beard ? FableAppearanceAssets::ListBeardStyles(PendingGender==EFableGender::Female) : FableAppearanceAssets::ListHairStyles(PendingGender==EFableGender::Female);
   FString& Style=Beard ? PendingBeardStyle : PendingHairStyle;
   int32 Index=Styles.IndexOfByPredicate([&](const auto& Entry){return Entry.Id==Style;});
   if(!Styles.IsEmpty()) Style=Styles[Next(FMath::Max(0,Index),Styles.Num())].Id;
  }
  else if(Action.StartsWith(TEXT("cycle_skin_")))
  {
   const auto& Colors=FableAppearance::SkinPalette(PendingRaceId);
   int32 Index=Colors.IndexOfByPredicate([&](const auto& Entry){return Entry.Color.Equals(PendingSkinColor,.001f);});
   PendingSkinColor=Colors[Next(FMath::Max(0,Index),Colors.Num())].Color;
  }
  else
  {
   const bool Eyes=Action.StartsWith(TEXT("cycle_eyecolor_"));
   const auto& Colors=Eyes ? FableAppearanceAssets::ListEyeColors() : FableAppearanceAssets::ListHairColors();
   FLinearColor& Color=Eyes ? PendingEyeColor : PendingHairColor;
   int32 Index=Colors.IndexOfByPredicate([&](const auto& Entry){return Entry.Color.Equals(Color,.001f);});
   if(!Colors.IsEmpty()) Color=Colors[Index==INDEX_NONE ? (Step>0 ? 0 : Colors.Num()-1) : Next(Index,Colors.Num())].Color;
  }
  if(Action.StartsWith(TEXT("cycle_feature_"))) RefreshAppearanceSection();
  else { RefreshAppearanceChoices(); ApplyPreviewAppearance(); }
  return;
 }

	if (ActionId == ContinueAction)
	{
		UE_LOG(LogFableForge, Log, TEXT("Main menu: Continue selected"));
		CurrentState = EMainMenuState::CharacterSelect;
		bIsSlotLoadMode = true;
		Rebuild();
		return;
	}

	if (ActionId == NewGameAction)
	{
		UE_LOG(LogFableForge, Log, TEXT("Main menu: New Game selected"));
		CurrentState = EMainMenuState::Customization;
		PendingCharacterId.Invalidate();
		PendingCharacterName = TEXT("Adventurer");
		PendingRaceId = TEXT("human");
		AppearanceCategory = 0;
		PreviewZoom = 0.f;
		PreviewPanOffset = 0.f;
		PreviewYawDegrees = -90.f;
		PendingGender = EFableGender::Male;
		PendingHairStyle=TEXT("parted");
		PendingBeardStyle=TEXT("none");
		ResetAppearance(true);
		bIsSlotLoadMode = false;
		Rebuild();
		return;
	}

	if (ActionId == ConfirmRaceAction)
	{
		CurrentState = EMainMenuState::Appearance;
		PreviewYawDegrees = -90.0f;
		Rebuild();
		return;
	}

	if (ActionId == BackMainAction)
	{
		CurrentState = EMainMenuState::Main;
		Rebuild();
		return;
	}

	if (ActionId == BackCharactersAction)
	{
		CurrentState = EMainMenuState::CharacterSelect;
		Rebuild();
		return;
	}

	if (ActionId == BackRacesAction)
	{
		CurrentState = EMainMenuState::RaceSelect;
		Rebuild();
		return;
	}

	if (ActionId == BackCustomizationAction)
	{
		CurrentState = EMainMenuState::Customization;
		Rebuild();
		return;
	}

	if (ActionId == GenderMaleAction)
	{
		if (PendingGender == EFableGender::Male) return;
		PendingGender = EFableGender::Male;
		const FLinearColor Skin=PendingSkinColor;
		ResetAppearance();
		PendingSkinColor=FableAppearance::NormalizeSkinColor(Skin,PendingRaceId);
		RefreshSelectionButtons(); UpdatePreviewMesh();
		return;
	}

	if (ActionId == GenderFemaleAction)
	{
		if (PendingGender == EFableGender::Female) return;
		PendingGender = EFableGender::Female;
		const FLinearColor Skin=PendingSkinColor;
		ResetAppearance();
		PendingSkinColor=FableAppearance::NormalizeSkinColor(Skin,PendingRaceId);
		RefreshSelectionButtons(); UpdatePreviewMesh();
		return;
	}

	if (ActionId == AppearanceAction)
	{
		CurrentState = EMainMenuState::Appearance;
		Rebuild(); return;
	}
	if (ActionId == ResetAppearanceAction)
	{
		for(const auto& Control:FableAppearance::Controls())
  {
   if(Control.Category!=AppearanceCategory) continue;
   const float Default=FableAppearance::Range(Control.Name,PendingRaceId,PendingGender).Default;
   if(Control.Name==TEXT("Height")) PendingHeightScale=Default; else PendingBodyMorphs.Add(Control.Name,Default);
  }
  if(AppearanceCategory==7)
  {
   PendingSkinColor=FableAppearance::DefaultSkinColor(PendingRaceId);
   const auto& HairColors=FableAppearanceAssets::ListHairColors();
   PendingHairColor=HairColors[FMath::Min(1,HairColors.Num()-1)].Color;
   const auto& EyeColors=FableAppearanceAssets::ListEyeColors();
   PendingEyeColor=EyeColors[FMath::Min(1,EyeColors.Num()-1)].Color;
   PendingHairStyle=TEXT("none"); PendingBeardStyle=TEXT("none");
  }
  for(const auto& Entry:AppearanceSliders) Entry.Value->SetValue(Entry.Key==TEXT("Height") ? PendingHeightScale : PendingBodyMorphs.FindRef(Entry.Key));
  RefreshAppearanceChoices(); HandleAppearanceChanged(0); return;
	}

	if (ActionId == CreateCharacterAction)
	{
		ApplyCharacterCreation();
		return;
	}

	if (const FGuid* CharacterId = CharacterActionMap.Find(ActionId))
	{
		PendingCharacterId = *CharacterId;
		CurrentState = EMainMenuState::SlotSelect;
		bIsSlotLoadMode = true;
		Rebuild();
		return;
	}

	if (const FString* RaceId = RaceActionMap.Find(ActionId))
	{
		if (PendingRaceId != *RaceId)
		{
			PendingRaceId = *RaceId;
			ResetAppearance();
		}
		RefreshSelectionButtons();
		if(RaceDescriptionText) RaceDescriptionText->SetText(FText::FromString(FableAppearance::RaceDescription(PendingRaceId)));
		ApplyPreviewAppearance();
		return;
	}

	if (const int32* SlotIndex = SlotActionMap.Find(ActionId))
	{
		AFableForgePlayerController* PlayerController = Cast<AFableForgePlayerController>(GetOwningPlayer());
		if (PlayerController != nullptr && PendingCharacterId.IsValid())
		{
			PlayerController->EnterGameFromCharacterSlot(PendingCharacterId, *SlotIndex, !bIsSlotLoadMode);
		}
		return;
	}
}

UFableActionButton* UFableMainMenuWidget::AddCompactButton(UHorizontalBox* Row, const FString& Label, FName Action, bool bSelected)
{
 UFableActionButton* Button=WidgetTree->ConstructWidget<UFableActionButton>();
 Button->InitializeAction(Action);
 SelectionButtons.Add(Action,Button);
 Button->OnActionClicked.AddDynamic(this,&UFableMainMenuWidget::HandleActionClicked);
 FableBookStyle::ApplyButton(Button);
 Button->SetBackgroundColor(bSelected ? UiButtonSelectedColor : FLinearColor::White);
 UTextBlock* Text=WidgetTree->ConstructWidget<UTextBlock>();
 Text->SetText(FText::FromString(Label));
 Text->SetFont(FableBookStyle::Font(19,true));
 Text->SetJustification(ETextJustify::Center);
 Text->SetColorAndOpacity(FableBookStyle::Ink);
 Button->AddChild(Text);
 Cast<UButtonSlot>(Text->Slot)->SetPadding(FMargin(12,7));
 USizeBox* Size=WidgetTree->ConstructWidget<USizeBox>();
 Size->SetHeightOverride(42);
 Size->SetContent(Button);
 UHorizontalBoxSlot* Slot=Row->AddChildToHorizontalBox(Size);
 Slot->SetPadding(FMargin(2));
 Slot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
 return Button;
}

void UFableMainMenuWidget::AddChoiceSelector(UVerticalBox* Parent,const FString& Label,const FString& Value,int32 Index,int32 Count,const FString& ActionPrefix,const FLinearColor* Swatch)
{
 UHorizontalBox* Heading=WidgetTree->ConstructWidget<UHorizontalBox>();
 Parent->AddChildToVerticalBox(Heading)->SetPadding(FMargin(2,3,2,1));
 UTextBlock* Caption=WidgetTree->ConstructWidget<UTextBlock>();
 Caption->SetText(FText::FromString(Label)); Caption->SetFont(FableBookStyle::Font(16)); Caption->SetColorAndOpacity(UiMutedTextColor);
 Heading->AddChildToHorizontalBox(Caption)->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
 UTextBlock* Counter=WidgetTree->ConstructWidget<UTextBlock>();
 Counter->SetText(FText::FromString(Index==INDEX_NONE ? FString::Printf(TEXT("%d presets"),Count) : FString::Printf(TEXT("%d / %d"),Index+1,Count))); Counter->SetFont(FableBookStyle::Font(16)); Counter->SetColorAndOpacity(UiMutedTextColor);
 Heading->AddChildToHorizontalBox(Counter); ChoiceCounters.Add(ActionPrefix,Counter);
 UHorizontalBox* Row=WidgetTree->ConstructWidget<UHorizontalBox>();
 USizeBox* RowSize=WidgetTree->ConstructWidget<USizeBox>(); RowSize->SetHeightOverride(40); RowSize->SetContent(Row); Parent->AddChildToVerticalBox(RowSize);
 auto Arrow=[&](const TCHAR* Symbol,const TCHAR* Direction)
 {
  UFableActionButton* Button=AddCompactButton(Row,Symbol,FName(*(ActionPrefix+Direction)));
  USizeBox* Size=CastChecked<USizeBox>(Button->GetParent()); Size->SetWidthOverride(42);
  CastChecked<UHorizontalBoxSlot>(Size->Slot)->SetSize(FSlateChildSize(ESlateSizeRule::Automatic));
  Button->SetIsEnabled(Count>1 || (Count==1 && Index==INDEX_NONE));
  Button->SetToolTipText(FText::FromString((FString(Direction)==TEXT("_prev")?TEXT("Previous "):TEXT("Next "))+Label.ToLower()));
 };
 Arrow(TEXT("‹"),TEXT("_prev"));
 UBorder* Card=WidgetTree->ConstructWidget<UBorder>(); Card->SetPadding(FMargin(10,3));
 Card->SetBrushColor(FLinearColor(.38f,.27f,.13f,.12f));
 UHorizontalBox* Content=WidgetTree->ConstructWidget<UHorizontalBox>(); Card->SetContent(Content);
 if(Swatch)
 {
  USizeBox* ChipSize=WidgetTree->ConstructWidget<USizeBox>(); ChipSize->SetWidthOverride(28); ChipSize->SetHeightOverride(28);
  UBorder* Chip=WidgetTree->ConstructWidget<UBorder>(); Chip->SetBrushColor(*Swatch); ChipSize->SetContent(Chip); ChoiceSwatches.Add(ActionPrefix,Chip);
  Content->AddChildToHorizontalBox(ChipSize)->SetVerticalAlignment(VAlign_Center);
 }
 UTextBlock* Selection=WidgetTree->ConstructWidget<UTextBlock>();
 ChoiceLabels.Add(ActionPrefix,Selection);
 Selection->SetText(FText::FromString(Value)); Selection->SetFont(FableBookStyle::Font(18,true)); Selection->SetColorAndOpacity(FableBookStyle::Ink); Selection->SetJustification(ETextJustify::Center);
 Selection->SetTextOverflowPolicy(ETextOverflowPolicy::Ellipsis); Selection->SetToolTipText(FText::FromString(Value));
 UHorizontalBoxSlot* TextSlot=Content->AddChildToHorizontalBox(Selection); TextSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill)); TextSlot->SetVerticalAlignment(VAlign_Center);
 UHorizontalBoxSlot* CardSlot=Row->AddChildToHorizontalBox(Card); CardSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill)); CardSlot->SetPadding(FMargin(6,2));
 Arrow(TEXT("›"),TEXT("_next"));
}

void UFableMainMenuWidget::BuildAppearanceControls(UVerticalBox* Parent)
{
 CreateHeader(Parent,TEXT("Appearance"),32);
 UTextBlock* Context=WidgetTree->ConstructWidget<UTextBlock>();
 Context->SetText(FText::FromString(FableAppearance::RaceDisplayName(PendingRaceId)));
 Context->SetFont(FableBookStyle::Font(18)); Context->SetColorAndOpacity(UiMutedTextColor);
 Context->SetJustification(ETextJustify::Center);
 Parent->AddChildToVerticalBox(Context)->SetPadding(FMargin(0,0,0,12));
 UHorizontalBox* Sections=WidgetTree->ConstructWidget<UHorizontalBox>(); Parent->AddChildToVerticalBox(Sections);
 AddCompactButton(Sections,TEXT("Body"),TEXT("appearance_category_0"),AppearanceCategory==0);
 AddCompactButton(Sections,TEXT("Face"),TEXT("appearance_category_1"),AppearanceCategory>=1 && AppearanceCategory<=5);
 AddCompactButton(Sections,TEXT("Style"),TEXT("appearance_category_7"),AppearanceCategory==7);
 AddSpacer(Parent,12);
 UVerticalBox* Controls=WidgetTree->ConstructWidget<UVerticalBox>();
 UVerticalBoxSlot* ControlsSlot=Parent->AddChildToVerticalBox(Controls);
 ControlsSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
 if(AppearanceCategory>=1 && AppearanceCategory<=5)
 {
  const TCHAR* Features[]={TEXT("Face shape"),TEXT("Eyes and brows"),TEXT("Nose"),TEXT("Mouth"),TEXT("Ears")};
  AddChoiceSelector(Controls,TEXT("Feature"),Features[AppearanceCategory-1],AppearanceCategory-1,5,TEXT("cycle_feature"));
 }
 auto AddSlider=[&](FName Name,const FString& Label,float Min,float Max,float Value)
 {
  UHorizontalBox* Row=WidgetTree->ConstructWidget<UHorizontalBox>();
  Controls->AddChildToVerticalBox(Row)->SetPadding(FMargin(0,4));
  USizeBox* LabelBox=WidgetTree->ConstructWidget<USizeBox>();
  LabelBox->SetWidthOverride(145); LabelBox->SetHeightOverride(27);
  UTextBlock* Text=WidgetTree->ConstructWidget<UTextBlock>();
  Text->SetText(FText::FromString(Label)); Text->SetFont(FableBookStyle::Font(20)); Text->SetColorAndOpacity(FableBookStyle::Ink);
  LabelBox->SetContent(Text); Row->AddChildToHorizontalBox(LabelBox)->SetVerticalAlignment(VAlign_Center);
  USlider* Slider=WidgetTree->ConstructWidget<USlider>(USlider::StaticClass(),MakeUniqueObjectName(WidgetTree,USlider::StaticClass(),FName(*(FString(TEXT("Appearance_"))+Name.ToString()))));
  Slider->SetMinValue(Min); Slider->SetMaxValue(Max); Slider->SetStepSize(.01f); Slider->SetValue(Value);
  Slider->SetSliderBarColor(FLinearColor(.25f,.16f,.08f)); Slider->SetSliderHandleColor(FLinearColor(.55f,.33f,.11f));
  UHorizontalBoxSlot* SliderSlot=Row->AddChildToHorizontalBox(Slider);
  SliderSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill)); SliderSlot->SetPadding(FMargin(5,0,8,0));
  UTextBlock* Number=WidgetTree->ConstructWidget<UTextBlock>();
  Number->SetFont(FableBookStyle::Font(18)); Number->SetColorAndOpacity(FableBookStyle::Ink);
  Number->SetMinDesiredWidth(68); Number->SetJustification(ETextJustify::Right);
  Row->AddChildToHorizontalBox(Number)->SetVerticalAlignment(VAlign_Center);
  AppearanceSliders.Add(Name,Slider); AppearanceValues.Add(Name,Number);
  Slider->OnValueChanged.AddDynamic(this,&UFableMainMenuWidget::HandleAppearanceChanged);
 };
 for(const FableAppearance::FControl& Control:FableAppearance::Controls())
 {
  if(Control.Category!=AppearanceCategory) continue;
  const auto Range=FableAppearance::Range(Control.Name,PendingRaceId,PendingGender);
  AddSlider(Control.Name,Control.Label,Range.Min,Range.Max,Control.Name==TEXT("Height") ? PendingHeightScale : PendingBodyMorphs.FindRef(Control.Name));
 }
 if(AppearanceCategory==7)
 {
  const bool Female=PendingGender==EFableGender::Female;
  const auto& Hair=FableAppearanceAssets::ListHairStyles(Female);
  const auto& Beard=FableAppearanceAssets::ListBeardStyles(Female);
  auto AddStyle=[&](const auto& Styles,FString& Selected,const TCHAR* Label,const TCHAR* Action)
  {
   if(Styles.IsEmpty()) return;
   int32 Index=Styles.IndexOfByPredicate([&](const auto& Entry){return Entry.Id==Selected;});
   if(Index==INDEX_NONE) {Index=0;Selected=Styles[0].Id;}
   AddChoiceSelector(Controls,Label,Styles[Index].DisplayName,Index,Styles.Num(),Action);
  };
  const auto& Skin=FableAppearance::SkinPalette(PendingRaceId);
  PendingSkinColor=FableAppearance::NormalizeSkinColor(PendingSkinColor,PendingRaceId);
  const int32 SkinIndex=FMath::Max(0,Skin.IndexOfByPredicate([&](const auto& Entry){return Entry.Color.Equals(PendingSkinColor,.001f);}));
  AddChoiceSelector(Controls,TEXT("Skin tone"),Skin[SkinIndex].Label,SkinIndex,Skin.Num(),TEXT("cycle_skin"),&PendingSkinColor);
  AddStyle(Hair,PendingHairStyle,TEXT("Hairstyle"),TEXT("cycle_hair"));
  AddStyle(Beard,PendingBeardStyle,TEXT("Facial hair"),TEXT("cycle_beard"));
  auto AddColor=[&](const auto& Colors,FLinearColor Color,const TCHAR* Label,const TCHAR* Action)
  {
   const int32 Index=Colors.IndexOfByPredicate([&](const auto& Entry){return Entry.Color.Equals(Color,.001f);});
   AddChoiceSelector(Controls,Label,Index==INDEX_NONE?TEXT("Custom"):Colors[Index].DisplayName,Index,Colors.Num(),Action,&Color);
  };
  AddColor(FableAppearanceAssets::ListHairColors(),PendingHairColor,TEXT("Hair color"),TEXT("cycle_haircolor"));
  AddColor(FableAppearanceAssets::ListEyeColors(),PendingEyeColor,TEXT("Eye color"),TEXT("cycle_eyecolor"));
 }
 AddSpacer(Controls,10);
 UHorizontalBox* ResetRow=WidgetTree->ConstructWidget<UHorizontalBox>();
 Controls->AddChildToVerticalBox(ResetRow)->SetHorizontalAlignment(HAlign_Right);
 UFableActionButton* ResetButton=AddCompactButton(ResetRow,TEXT("Reset section"),ResetAppearanceAction);
 if(USizeBox* ResetSize=Cast<USizeBox>(ResetButton->GetParent())) ResetSize->SetMinDesiredWidth(210.f);
 AddSpacer(Parent,12);
 UHorizontalBox* Footer=WidgetTree->ConstructWidget<UHorizontalBox>(); Parent->AddChildToVerticalBox(Footer);
 AddCompactButton(Footer,TEXT("Back"),BackRacesAction);
 AddCompactButton(Footer,TEXT("Create Character"),CreateCharacterAction,true);
 HandleAppearanceChanged(0);
}

void UFableMainMenuWidget::UpdatePreviewHair()
{
 if(!PreviewActor || !PreviewMeshComponent) return;
 auto EnsureComponent=[&](TObjectPtr<UStaticMeshComponent>& Component)
 {
  if(!Component) { Component=NewObject<UStaticMeshComponent>(PreviewActor); Component->RegisterComponent(); }
 };
 EnsureComponent(PreviewHair); EnsureComponent(PreviewBeard);
 FableAppearanceAssets::ConfigureStyle(PreviewHair,PreviewMeshComponent,PendingHairStyle,false,PendingHairColor,PendingBodyMorphs.FindRef(TEXT("HeadSize")));
 FableAppearanceAssets::ConfigureStyle(PreviewBeard,PreviewMeshComponent,PendingBeardStyle,true,PendingHairColor,PendingBodyMorphs.FindRef(TEXT("HeadSize")));
}

void UFableMainMenuWidget::RefreshSelectionButtons()
{
 for(const auto& Entry:SelectionButtons)
 {
  bool Selected=false;
  if(const FString* Race=RaceActionMap.Find(Entry.Key)) Selected=*Race==PendingRaceId;
  else if(Entry.Key==GenderMaleAction) Selected=PendingGender==EFableGender::Male;
  else if(Entry.Key==GenderFemaleAction) Selected=PendingGender==EFableGender::Female;
  else continue;
  Entry.Value->SetBackgroundColor(Selected ? UiButtonSelectedColor : MainMenuUiButtonColor);
 }
}

void UFableMainMenuWidget::RefreshAppearanceSection()
{
 if(!AppearanceColumn) return;
 AppearanceSliders.Reset(); AppearanceValues.Reset(); ChoiceLabels.Reset(); ChoiceCounters.Reset(); ChoiceSwatches.Reset();
 // Only the controls change; keep the viewport, world, actor and camera alive.
 SelectionButtons.Reset();
 AppearanceColumn->ClearChildren();
 BuildAppearanceControls(AppearanceColumn);
}

void UFableMainMenuWidget::RefreshAppearanceChoices()
{
 auto Update=[&](const FString& Key,const FString& Label,int32 Index,int32 Count,const FLinearColor* Color=nullptr)
 {
  if(UTextBlock* Text=ChoiceLabels.FindRef(Key)) { Text->SetText(FText::FromString(Label)); Text->SetToolTipText(FText::FromString(Label)); }
  if(UTextBlock* Text=ChoiceCounters.FindRef(Key)) Text->SetText(FText::FromString(Index==INDEX_NONE ? FString::Printf(TEXT("%d presets"),Count) : FString::Printf(TEXT("%d / %d"),Index+1,Count)));
  if(Color) if(UBorder* Chip=ChoiceSwatches.FindRef(Key)) Chip->SetBrushColor(*Color);
  for(const TCHAR* Suffix:{TEXT("_prev"),TEXT("_next")}) if(UFableActionButton* Button=SelectionButtons.FindRef(FName(*(Key+Suffix)))) Button->SetIsEnabled(Count>1 || (Count==1 && Index==INDEX_NONE));
 };
 const auto& Skin=FableAppearance::SkinPalette(PendingRaceId);
 const int32 SkinIndex=FMath::Max(0,Skin.IndexOfByPredicate([&](const auto& Entry){return Entry.Color.Equals(PendingSkinColor,.001f);}));
 Update(TEXT("cycle_skin"),Skin[SkinIndex].Label,SkinIndex,Skin.Num(),&PendingSkinColor);
 auto Style=[&](const auto& Styles,const FString& Id,const TCHAR* Key)
 {
  const int32 Index=Styles.IndexOfByPredicate([&](const auto& Entry){return Entry.Id==Id;});
  if(Styles.IsValidIndex(Index)) Update(Key,Styles[Index].DisplayName,Index,Styles.Num());
 };
 Style(FableAppearanceAssets::ListHairStyles(PendingGender==EFableGender::Female),PendingHairStyle,TEXT("cycle_hair"));
 Style(FableAppearanceAssets::ListBeardStyles(PendingGender==EFableGender::Female),PendingBeardStyle,TEXT("cycle_beard"));
 auto Color=[&](const auto& Colors,const FLinearColor& Value,const TCHAR* Key)
 {
  const int32 Index=Colors.IndexOfByPredicate([&](const auto& Entry){return Entry.Color.Equals(Value,.001f);});
  Update(Key,Index==INDEX_NONE ? TEXT("Custom") : Colors[Index].DisplayName,Index,Colors.Num(),&Value);
 };
 Color(FableAppearanceAssets::ListHairColors(),PendingHairColor,TEXT("cycle_haircolor"));
 Color(FableAppearanceAssets::ListEyeColors(),PendingEyeColor,TEXT("cycle_eyecolor"));
}

void UFableMainMenuWidget::AddBodyTypeButton(UHorizontalBox* Row, bool Female)
{
 static TStrongObjectPtr<UTexture2D> MaleIcon,FemaleIcon;
 TStrongObjectPtr<UTexture2D>& Icon=Female ? FemaleIcon : MaleIcon;
 if(!Icon.IsValid()) Icon.Reset(FImageUtils::ImportFileAsTexture2D(FPaths::ProjectContentDir()/TEXT("Slate/Textures")/(Female ? TEXT("BodyTypeFemale.png") : TEXT("BodyTypeMale.png"))));
 UFableActionButton* Button=WidgetTree->ConstructWidget<UFableActionButton>();
 const FName Action=Female ? GenderFemaleAction : GenderMaleAction;
 Button->InitializeAction(Action); Button->OnActionClicked.AddDynamic(this,&UFableMainMenuWidget::HandleActionClicked);
 SelectionButtons.Add(Action,Button); FableBookStyle::ApplyButton(Button);
 Button->SetBackgroundColor((PendingGender==EFableGender::Female)==Female ? UiButtonSelectedColor : MainMenuUiButtonColor);
 Button->SetToolTipText(FText::FromString(Female ? TEXT("Body type 2") : TEXT("Body type 1")));
 UImage* Image=WidgetTree->ConstructWidget<UImage>(); Image->SetBrushFromTexture(Icon.Get(),true);
 UScaleBox* Fit=WidgetTree->ConstructWidget<UScaleBox>(); Fit->SetStretch(EStretch::ScaleToFit); Fit->SetContent(Image);
 Button->AddChild(Fit);
 UButtonSlot* ImageSlot=CastChecked<UButtonSlot>(Fit->Slot); ImageSlot->SetPadding(FMargin(14,12)); ImageSlot->SetHorizontalAlignment(HAlign_Fill); ImageSlot->SetVerticalAlignment(VAlign_Fill);
 USizeBox* Size=WidgetTree->ConstructWidget<USizeBox>(); Size->SetHeightOverride(230); Size->SetContent(Button);
 UHorizontalBoxSlot* Slot=Row->AddChildToHorizontalBox(Size); Slot->SetSize(FSlateChildSize(ESlateSizeRule::Fill)); Slot->SetPadding(FMargin(6,0));
}
