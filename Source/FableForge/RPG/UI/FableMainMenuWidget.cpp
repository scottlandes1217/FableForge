#include "RPG/UI/FableMainMenuWidget.h"

#include "Components/Border.h"
#include "Components/ButtonSlot.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/EditableTextBox.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/SizeBox.h"
#include "Components/Spacer.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Components/Viewport.h"
#include "Components/Widget.h"
#include "Components/WidgetSwitcher.h"
#include "Components/PointLightComponent.h"
#include "Blueprint/WidgetTree.h"
#include "FableForge.h"
#include "FableForgePlayerController.h"
#include "RPG/Save/FableSaveSubsystem.h"
#include "RPG/UI/FableActionButton.h"
#include "Engine/SkeletalMesh.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/SlateWrapperTypes.h"
#include "TimerManager.h"

namespace
{
	const FName ContinueAction = TEXT("main_continue");
	const FName NewGameAction = TEXT("main_new_game");
	const FName ConfirmRaceAction = TEXT("confirm_race");
	const FName BackMainAction = TEXT("back_main");
	const FName BackCharactersAction = TEXT("back_characters");
	const FName BackRacesAction = TEXT("back_races");
	const FName BackCustomizationAction = TEXT("back_customization");
	const FName CreateCharacterAction = TEXT("create_character");
	const FName GenderMaleAction = TEXT("gender_male");
	const FName GenderFemaleAction = TEXT("gender_female");
	const FName RotateLeftAction = TEXT("preview_rotate_left");
	const FName RotateRightAction = TEXT("preview_rotate_right");

	const FName BackdropWidgetName(TEXT("Backdrop"));
	const FName PanelWidgetName(TEXT("Panel"));

	const TCHAR* MainMenuBaseCharacterMeshPath = TEXT("/Game/Characters/Mannequins/Meshes/basecharacter.basecharacter");

	const FLinearColor UiBackdropColor(0.0f, 0.0f, 0.0f, 0.94f);
	const FLinearColor UiPanelColor(0.01f, 0.01f, 0.01f, 0.97f);
	const FLinearColor UiPreviewColor(0.0f, 0.0f, 0.0f, 0.97f);
	const FLinearColor MainMenuUiTextColor(0.95f, 0.95f, 0.95f, 1.0f);
	const FLinearColor UiMutedTextColor(0.72f, 0.72f, 0.72f, 1.0f);
	const FLinearColor MainMenuUiButtonColor(0.05f, 0.05f, 0.05f, 1.0f);
	const FLinearColor UiButtonSelectedColor(0.0f, 0.0f, 0.0f, 1.0f);
	const FLinearColor UiButtonDisabledColor(0.03f, 0.03f, 0.03f, 0.75f);

	UVerticalBox* ResolveVisiblePanelContent(UWidgetTree* InWidgetTree)
	{
		if (InWidgetTree == nullptr)
		{
			return nullptr;
		}

		UCanvasPanel* RootCanvas = Cast<UCanvasPanel>(InWidgetTree->RootWidget);
		if (RootCanvas == nullptr)
		{
			return nullptr;
		}

		for (int32 ChildIndex = 0; ChildIndex < RootCanvas->GetChildrenCount(); ++ChildIndex)
		{
			UBorder* ChildBorder = Cast<UBorder>(RootCanvas->GetChildAt(ChildIndex));
			if (ChildBorder == nullptr || ChildBorder->GetFName() != PanelWidgetName)
			{
				continue;
			}

			return Cast<UVerticalBox>(ChildBorder->GetContent());
		}

		return nullptr;
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

	ActionCounter = 0;
	CharacterActionMap.Reset();
	RaceActionMap.Reset();
	SlotActionMap.Reset();
	CharacterNameTextBox = nullptr;
	PreviewViewport = nullptr;
	PreviewMeshComponent = nullptr;
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

	Panel->SetBrushColor(UiPanelColor);
	if (UCanvasPanelSlot* PanelSlot = Cast<UCanvasPanelSlot>(Panel->Slot))
	{
		const bool bWideLayout = CurrentState == EMainMenuState::RaceSelect || CurrentState == EMainMenuState::Customization;
		if (bWideLayout)
		{
			PanelSlot->SetAutoSize(false);
			PanelSlot->SetAnchors(FAnchors(0.0f, 0.0f, 1.0f, 1.0f));
			PanelSlot->SetAlignment(FVector2D(0.0f, 0.0f));
			PanelSlot->SetOffsets(FMargin(56.0f, 40.0f, 56.0f, 40.0f));
		}
		else
		{
			PanelSlot->SetAutoSize(false);
			PanelSlot->SetAnchors(FAnchors(0.5f, 0.5f));
			PanelSlot->SetAlignment(FVector2D(0.5f, 0.5f));
			PanelSlot->SetPosition(FVector2D(0.0f, 0.0f));
			PanelSlot->SetSize(FVector2D(860.0f, 760.0f));
		}
	}

	UVerticalBox* PanelContent = Cast<UVerticalBox>(Panel->GetContent());
	if (PanelContent == nullptr)
	{
		PanelContent = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("PanelContent"));
		Panel->SetContent(PanelContent);
	}

	PanelContent->ClearChildren();
	UE_LOG(LogFableForge, Log, TEXT("Main menu rebuild start. State=%d Panel=%s"), static_cast<int32>(CurrentState), *GetNameSafe(PanelContent));

	AddSpacer(PanelContent, 20.0f);

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
	UVerticalBox* Parent = ResolveVisiblePanelContent(WidgetTree);
	if (Parent == nullptr)
	{
		return;
	}
	
	AddSpacer(Parent, 12.0f);

	const UFableSaveSubsystem* SaveSubsystem = GetGameInstance() ? GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	const bool bCanContinue = SaveSubsystem != nullptr && SaveSubsystem->HasAnySavedGames();
	if (bCanContinue)
	{
		CreateActionButton(Parent, TEXT("Continue"), ContinueAction);
		AddSpacer(Parent, 6.0f);
	}

	CreateActionButton(Parent, TEXT("New Game"), NewGameAction);
}

void UFableMainMenuWidget::BuildCharacterSelectState()
{
	UVerticalBox* Parent = ResolveVisiblePanelContent(WidgetTree);
	if (Parent == nullptr)
	{
		return;
	}

	CreateSubheader(Parent, TEXT("Select a saved character"));
	AddSpacer(Parent, 8.0f);

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
			CreateActionButton(Parent, Label, RegisterCharacterAction(Profile.CharacterId));
			AddSpacer(Parent, 4.0f);
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
	UVerticalBox* Parent = ResolveVisiblePanelContent(WidgetTree);
	if (Parent == nullptr)
	{
		return;
	}

	CreateSubheader(Parent, bIsSlotLoadMode ? TEXT("Pick a save slot to load") : TEXT("Choose a slot for your new character"));
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
	CreateActionButton(Parent, TEXT("Back"), bIsSlotLoadMode ? BackCharactersAction : BackCustomizationAction, true, 42.0f);
}

void UFableMainMenuWidget::BuildRaceSelectState()
{
	UVerticalBox* Parent = ResolveVisiblePanelContent(WidgetTree);
	if (Parent == nullptr)
	{
		return;
	}

	CreateSubheader(Parent, TEXT("Select your race"));
	AddSpacer(Parent, 14.0f);

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

	const FFableRaceDefinition* SelectedRace = FindRaceById(PendingRaceId);

	UHorizontalBox* MainRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("RaceSelectionMainRow"));
	if (UVerticalBoxSlot* RowSlot = Parent->AddChildToVerticalBox(MainRow))
	{
		RowSlot->SetHorizontalAlignment(HAlign_Fill);
		RowSlot->SetVerticalAlignment(VAlign_Fill);
		RowSlot->SetPadding(FMargin(16.0f, 0.0f, 16.0f, 16.0f));

		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		RowSlot->SetSize(FillSize);
	}

	UVerticalBox* LeftColumn = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("RaceLeftColumn"));
	if (UHorizontalBoxSlot* LeftSlot = MainRow->AddChildToHorizontalBox(LeftColumn))
	{
		LeftSlot->SetPadding(FMargin(0.0f, 0.0f, 14.0f, 0.0f));

		FSlateChildSize LeftSize;
		LeftSize.SizeRule = ESlateSizeRule::Fill;
		LeftSize.Value = 0.42f;
		LeftSlot->SetSize(LeftSize);
	}

	CreateSubheader(LeftColumn, TEXT("Races"));
	AddSpacer(LeftColumn, 6.0f);
	for (const FFableRaceDefinition& Race : Races)
	{
		const bool bSelectedRace = Race.Id == PendingRaceId;
		UFableActionButton* RaceButton = CreateActionButton(LeftColumn, Race.Name, RegisterRaceAction(Race.Id), true, 44.0f);
		if (RaceButton != nullptr)
		{
			RaceButton->SetBackgroundColor(bSelectedRace ? UiButtonSelectedColor : MainMenuUiButtonColor);
		}
		AddSpacer(LeftColumn, 6.0f);
	}

	AddSpacer(LeftColumn, 18.0f);
	CreateActionButton(LeftColumn, TEXT("Continue"), ConfirmRaceAction, true, 46.0f);
	AddSpacer(LeftColumn, 10.0f);
	CreateActionButton(LeftColumn, TEXT("Back"), BackMainAction, true, 42.0f);

	UVerticalBox* RightColumn = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("RaceRightColumn"));
	if (UHorizontalBoxSlot* RightSlot = MainRow->AddChildToHorizontalBox(RightColumn))
	{
		RightSlot->SetPadding(FMargin(14.0f, 0.0f, 0.0f, 0.0f));

		FSlateChildSize RightSize;
		RightSize.SizeRule = ESlateSizeRule::Fill;
		RightSize.Value = 0.58f;
		RightSlot->SetSize(RightSize);
	}

	CreateSubheader(RightColumn, SelectedRace != nullptr ? SelectedRace->Name : TEXT("Race"));
	AddSpacer(RightColumn, 8.0f);

	UBorder* DescriptionPanel = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("RaceDescriptionPanel"));
	DescriptionPanel->SetBrushColor(MainMenuUiButtonColor);
	DescriptionPanel->SetPadding(FMargin(18.0f, 16.0f, 18.0f, 16.0f));
	if (UVerticalBoxSlot* DescriptionSlot = RightColumn->AddChildToVerticalBox(DescriptionPanel))
	{
		DescriptionSlot->SetHorizontalAlignment(HAlign_Fill);
		DescriptionSlot->SetVerticalAlignment(VAlign_Fill);

		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		DescriptionSlot->SetSize(FillSize);
	}

	UTextBlock* DescriptionText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("RaceDescriptionText"));
	DescriptionText->SetAutoWrapText(true);
	DescriptionText->SetJustification(ETextJustify::Left);
	DescriptionText->SetColorAndOpacity(FSlateColor(MainMenuUiTextColor));
	DescriptionText->SetText(FText::FromString(
		(SelectedRace != nullptr && !SelectedRace->Description.IsEmpty())
			? SelectedRace->Description
			: TEXT("No description available.")));
	DescriptionPanel->SetContent(DescriptionText);
}

void UFableMainMenuWidget::BuildCustomizationState()
{
	UVerticalBox* Parent = ResolveVisiblePanelContent(WidgetTree);
	if (Parent == nullptr)
	{
		return;
	}

	CreateSubheader(Parent, TEXT("Character Customization"));
	AddSpacer(Parent, 14.0f);

	UHorizontalBox* MainRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("CustomizationMainRow"));
	if (UVerticalBoxSlot* RowSlot = Parent->AddChildToVerticalBox(MainRow))
	{
		RowSlot->SetHorizontalAlignment(HAlign_Fill);
		RowSlot->SetVerticalAlignment(VAlign_Fill);
		RowSlot->SetPadding(FMargin(16.0f, 0.0f, 16.0f, 16.0f));

		FSlateChildSize FillSize;
		FillSize.SizeRule = ESlateSizeRule::Fill;
		FillSize.Value = 1.0f;
		RowSlot->SetSize(FillSize);
	}

	UVerticalBox* LeftColumn = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("LeftColumn"));
	if (UHorizontalBoxSlot* LeftSlot = MainRow->AddChildToHorizontalBox(LeftColumn))
	{
		LeftSlot->SetPadding(FMargin(0.0f, 0.0f, 16.0f, 0.0f));
		LeftSlot->SetHorizontalAlignment(HAlign_Fill);
		LeftSlot->SetVerticalAlignment(VAlign_Top);

		FSlateChildSize LeftSize;
		LeftSize.SizeRule = ESlateSizeRule::Fill;
		LeftSize.Value = 0.40f;
		LeftSlot->SetSize(LeftSize);
	}

	CreateSubheader(LeftColumn, TEXT("Name"));
	CharacterNameTextBox = WidgetTree->ConstructWidget<UEditableTextBox>(UEditableTextBox::StaticClass(), TEXT("CharacterNameTextBox"));
	CharacterNameTextBox->SetHintText(FText::FromString(TEXT("Enter character name")));
	CharacterNameTextBox->SetText(FText::FromString(TEXT("Adventurer")));
	CharacterNameTextBox->SetForegroundColor(MainMenuUiTextColor);
	FEditableTextBoxStyle NameTextBoxStyle = CharacterNameTextBox->GetWidgetStyle();
	NameTextBoxStyle.SetBackgroundColor(FSlateColor(MainMenuUiButtonColor));
	NameTextBoxStyle.SetForegroundColor(FSlateColor(MainMenuUiTextColor));
	NameTextBoxStyle.SetFocusedForegroundColor(FSlateColor(MainMenuUiTextColor));
	NameTextBoxStyle.SetReadOnlyForegroundColor(FSlateColor(UiMutedTextColor));
	CharacterNameTextBox->SetWidgetStyle(NameTextBoxStyle);
	CharacterNameTextBox->SetJustification(ETextJustify::Center);
	if (UVerticalBoxSlot* NameSlot = LeftColumn->AddChildToVerticalBox(CharacterNameTextBox))
	{
		NameSlot->SetPadding(FMargin(0.0f, 0.0f, 0.0f, 10.0f));
	}

	CreateSubheader(LeftColumn, TEXT("Gender"));
	UFableActionButton* MaleButton = CreateActionButton(LeftColumn, TEXT("Male"), GenderMaleAction, true, 40.0f);
	if (MaleButton != nullptr)
	{
		MaleButton->SetBackgroundColor(PendingGender == EFableGender::Male ? UiButtonSelectedColor : MainMenuUiButtonColor);
	}
	AddSpacer(LeftColumn, 4.0f);
	UFableActionButton* FemaleButton = CreateActionButton(LeftColumn, TEXT("Female"), GenderFemaleAction, true, 40.0f);
	if (FemaleButton != nullptr)
	{
		FemaleButton->SetBackgroundColor(PendingGender == EFableGender::Female ? UiButtonSelectedColor : MainMenuUiButtonColor);
	}
	AddSpacer(LeftColumn, 30.0f);

	CreateActionButton(LeftColumn, TEXT("Create Character"), CreateCharacterAction, true, 46.0f);
	AddSpacer(LeftColumn, 8.0f);
	CreateActionButton(LeftColumn, TEXT("Back"), BackRacesAction, true, 42.0f);

	UVerticalBox* RightColumn = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("RightColumn"));
	if (UHorizontalBoxSlot* RightSlot = MainRow->AddChildToHorizontalBox(RightColumn))
	{
		RightSlot->SetPadding(FMargin(16.0f, 0.0f, 0.0f, 0.0f));
		RightSlot->SetHorizontalAlignment(HAlign_Fill);
		RightSlot->SetVerticalAlignment(VAlign_Fill);

		FSlateChildSize RightSize;
		RightSize.SizeRule = ESlateSizeRule::Fill;
		RightSize.Value = 0.60f;
		RightSlot->SetSize(RightSize);
	}

	CreateSubheader(RightColumn, TEXT("Preview"));
	AddSpacer(RightColumn, 8.0f);
	UBorder* PreviewBorder = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("PreviewBorder"));
	PreviewBorder->SetBrushColor(UiPreviewColor);
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

	PreviewViewport = WidgetTree->ConstructWidget<UViewport>(UViewport::StaticClass(), TEXT("CharacterPreviewViewport"));
	PreviewBorder->SetContent(PreviewViewport);

	UHorizontalBox* RotateRow = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("RotateRow"));
	if (UVerticalBoxSlot* RotateSlot = RightColumn->AddChildToVerticalBox(RotateRow))
	{
		RotateSlot->SetHorizontalAlignment(HAlign_Fill);
		RotateSlot->SetVerticalAlignment(VAlign_Bottom);
	}

	auto AddRotateButton = [&](const FString& Label, FName Action) -> UFableActionButton*
	{
		UFableActionButton* Button = WidgetTree->ConstructWidget<UFableActionButton>(UFableActionButton::StaticClass());
		Button->InitializeAction(Action);
		Button->OnActionClicked.AddDynamic(this, &UFableMainMenuWidget::HandleActionClicked);
		Button->SetBackgroundColor(MainMenuUiButtonColor);

		UTextBlock* LabelWidget = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		LabelWidget->SetText(FText::FromString(Label));
		LabelWidget->SetColorAndOpacity(FSlateColor(MainMenuUiTextColor));
		LabelWidget->SetJustification(ETextJustify::Center);
		FSlateFontInfo FontInfo = LabelWidget->GetFont();
		FontInfo.Size = 30;
		LabelWidget->SetFont(FontInfo);
		Button->AddChild(LabelWidget);

		if (UButtonSlot* ContentSlot = Cast<UButtonSlot>(LabelWidget->Slot))
		{
			ContentSlot->SetHorizontalAlignment(HAlign_Center);
			ContentSlot->SetVerticalAlignment(VAlign_Center);
			ContentSlot->SetPadding(FMargin(12.0f, 8.0f));
		}

		if (UHorizontalBoxSlot* ButtonSlot = RotateRow->AddChildToHorizontalBox(Button))
		{
			ButtonSlot->SetPadding(FMargin(0.0f, 0.0f, 8.0f, 0.0f));

			FSlateChildSize FillSize;
			FillSize.SizeRule = ESlateSizeRule::Fill;
			FillSize.Value = 1.0f;
			ButtonSlot->SetSize(FillSize);
		}

		return Button;
	};

	UFableActionButton* RotateLeftButton = AddRotateButton(TEXT("<"), RotateLeftAction);
	UFableActionButton* RotateRightButton = AddRotateButton(TEXT(">"), RotateRightAction);

	if (RotateLeftButton != nullptr)
	{
		RotateLeftButton->OnPressed.AddDynamic(this, &UFableMainMenuWidget::HandleRotateLeftPressed);
		RotateLeftButton->OnReleased.AddDynamic(this, &UFableMainMenuWidget::HandleRotateReleased);
	}

	if (RotateRightButton != nullptr)
	{
		RotateRightButton->OnPressed.AddDynamic(this, &UFableMainMenuWidget::HandleRotateRightPressed);
		RotateRightButton->OnReleased.AddDynamic(this, &UFableMainMenuWidget::HandleRotateReleased);
	}

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
	Header->SetColorAndOpacity(FSlateColor(MainMenuUiTextColor));
	Header->SetJustification(ETextJustify::Center);
	FSlateFontInfo FontInfo = Header->GetFont();
	FontInfo.Size = FontSize;
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
	Subheader->SetColorAndOpacity(FSlateColor(UiMutedTextColor));
	Subheader->SetJustification(ETextJustify::Center);
	Subheader->SetAutoWrapText(true);

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
	Button->SetIsEnabled(bEnabled);
	Button->OnActionClicked.AddDynamic(this, &UFableMainMenuWidget::HandleActionClicked);
	Button->SetBackgroundColor(bEnabled ? MainMenuUiButtonColor : UiButtonDisabledColor);

	UTextBlock* LabelWidget = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	LabelWidget->SetText(FText::FromString(Label));
	LabelWidget->SetJustification(ETextJustify::Center);
	LabelWidget->SetColorAndOpacity(FSlateColor(FLinearColor::White));
	Button->AddChild(LabelWidget);

	if (UVerticalBoxSlot* ButtonSlot = Parent->AddChildToVerticalBox(Button))
	{
		ButtonSlot->SetPadding(FMargin(24.0f, 0.0f, 24.0f, 0.0f));
		ButtonSlot->SetHorizontalAlignment(HAlign_Fill);
		ButtonSlot->SetVerticalAlignment(VAlign_Center);
	}

	if (UButtonSlot* ContentSlot = Cast<UButtonSlot>(LabelWidget->Slot))
	{
		ContentSlot->SetHorizontalAlignment(HAlign_Center);
		ContentSlot->SetVerticalAlignment(VAlign_Center);
		ContentSlot->SetPadding(FMargin(8.0f, Height * 0.25f));
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

	const FString CharacterName = CharacterNameTextBox != nullptr ? CharacterNameTextBox->GetText().ToString() : TEXT("Adventurer");
	PendingCharacterId = SaveSubsystem->CreateCharacter(CharacterName, PendingRaceId, PendingGender);
	bIsSlotLoadMode = false;
	CurrentState = EMainMenuState::SlotSelect;
	Rebuild();
}

void UFableMainMenuWidget::UpdatePreviewMesh()
{
	if (!EnsurePreviewActor())
	{
		return;
	}

	USkeletalMesh* PreviewMesh = LoadObject<USkeletalMesh>(nullptr, MainMenuBaseCharacterMeshPath);
	if (PreviewMesh == nullptr)
	{
		UE_LOG(LogFableForge, Warning, TEXT("Preview mesh could not be loaded: %s"), MainMenuBaseCharacterMeshPath);
		return;
	}

	PreviewMeshComponent->SetSkeletalMesh(PreviewMesh);
	PreviewMeshComponent->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	PreviewMeshComponent->SetCastShadow(false);
	PreviewMeshComponent->SetReceivesDecals(false);
	const FBoxSphereBounds MeshBounds = PreviewMeshComponent->CalcBounds(FTransform::Identity);
	const float HalfHeight = FMath::Max(MeshBounds.BoxExtent.Z, 80.0f);
	const float MaxHalfWidth = static_cast<float>(FMath::Max3(MeshBounds.BoxExtent.X, MeshBounds.BoxExtent.Y, 42.0));
	const float CenterOffsetZ = -MeshBounds.Origin.Z;
	const float CameraDistance = FMath::Clamp(FMath::Max(HalfHeight, MaxHalfWidth) * 2.25f, 190.0f, 300.0f);
	const float CenteredViewZ = CenterOffsetZ + MeshBounds.Origin.Z;

	PreviewMeshComponent->SetRelativeLocation(FVector(0.0f, 0.0f, CenterOffsetZ));
	PreviewMeshComponent->SetRelativeRotation(FRotator(0.0f, PreviewYawDegrees, 0.0f));
	PreviewMeshComponent->SetRelativeScale3D(FVector(1.28f));

	if (PreviewViewport != nullptr)
	{
		PreviewViewport->SetViewLocation(FVector(CameraDistance, 0.0f, CenteredViewZ + (HalfHeight * 0.02f)));
		PreviewViewport->SetViewRotation(FRotator(0.0f, 180.0f, 0.0f));
	}

	if (PreviewKeyLightComponent != nullptr)
	{
		PreviewKeyLightComponent->SetRelativeLocation(FVector(CameraDistance * 0.36f, 0.0f, CenterOffsetZ + (HalfHeight * 1.6f)));
	}
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

	PreviewViewport->SetEnableAdvancedFeatures(false);
	PreviewViewport->SetLightIntensity(1.9f);
	PreviewViewport->SetSkyIntensity(0.08f);
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
		PreviewKeyLightComponent->SetIntensity(540.0f);
		PreviewKeyLightComponent->SetAttenuationRadius(520.0f);
		PreviewKeyLightComponent->SetSourceRadius(90.0f);
		PreviewKeyLightComponent->SetSoftSourceRadius(120.0f);
		PreviewKeyLightComponent->SetSpecularScale(0.25f);
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
		CurrentState = EMainMenuState::RaceSelect;
		PendingCharacterId.Invalidate();
		bIsSlotLoadMode = false;
		Rebuild();
		return;
	}

	if (ActionId == ConfirmRaceAction)
	{
		CurrentState = EMainMenuState::Customization;
		PendingGender = EFableGender::Male;
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
		PendingGender = EFableGender::Male;
		Rebuild();
		return;
	}

	if (ActionId == GenderFemaleAction)
	{
		PendingGender = EFableGender::Female;
		Rebuild();
		return;
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
		PendingRaceId = *RaceId;
		Rebuild();
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
