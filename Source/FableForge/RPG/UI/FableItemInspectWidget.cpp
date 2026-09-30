#include "RPG/UI/FableItemInspectWidget.h"

#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/Button.h"
#include "Components/ButtonSlot.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/Image.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/ScrollBox.h"
#include "Components/ScrollBoxSlot.h"
#include "Components/SizeBox.h"
#include "Components/Spacer.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "InputCoreTypes.h"
#include "Input/Events.h"
#include "Input/Reply.h"
#include "RPG/UI/FableBookStyle.h"

namespace
{
	const FLinearColor ScrimColor(0.015f, 0.010f, 0.008f, 0.76f);
	const FLinearColor ParchmentShadow(0.21f, 0.11f, 0.055f, 0.96f);
	const FLinearColor ParchmentPage(0.87f, 0.79f, 0.62f, 0.99f);
	const FLinearColor MutedInk(0.28f, 0.19f, 0.12f, 1.f);
}

TSharedRef<SWidget> UFableItemInspectWidget::RebuildWidget()
{
	RebuildContent();
	return Super::RebuildWidget();
}

void UFableItemInspectWidget::NativeConstruct()
{
	Super::NativeConstruct();
	SetIsFocusable(true);
	if (RootCanvas == nullptr)
	{
		RebuildContent();
	}
}

void UFableItemInspectWidget::Open(const FString& InTitle, const TArray<TPair<FString, FString>>& InDetails, UTexture2D* InIcon)
{
	Title = InTitle;
	Details = InDetails;
	Icon = InIcon;
	bOpen = true;
	RightStickY = 0.f;
	AnalogScrollCooldown = 0.f;
	RebuildContent();

	if (APlayerController* Controller = GetOwningPlayer())
	{
		SetUserFocus(Controller);
	}
}

void UFableItemInspectWidget::Close()
{
	if (!bOpen)
	{
		return;
	}

	bOpen = false;
	RightStickY = 0.f;
	if (RootCanvas != nullptr)
	{
		RootCanvas->SetVisibility(ESlateVisibility::Collapsed);
	}
	OnClosed.Broadcast();
}

void UFableItemInspectWidget::HandleCloseClicked()
{
	Close();
}

void UFableItemInspectWidget::ScrollBy(float Amount)
{
	if (DetailsScroll == nullptr || FMath::IsNearlyZero(Amount))
	{
		return;
	}

	DetailsScroll->SetScrollOffset(FMath::Max(0.f, DetailsScroll->GetScrollOffset() + Amount));
}

void UFableItemInspectWidget::NativeTick(const FGeometry& InGeometry, float InDeltaTime)
{
	Super::NativeTick(InGeometry, InDeltaTime);
	if (!bOpen)
	{
		return;
	}

	AnalogScrollCooldown = FMath::Max(0.f, AnalogScrollCooldown - InDeltaTime);
	if (FMath::Abs(RightStickY) >= 0.28f && AnalogScrollCooldown <= 0.f)
	{
		ScrollBy(RightStickY * 48.f);
		AnalogScrollCooldown = 0.08f;
	}
}

FReply UFableItemInspectWidget::NativeOnPreviewKeyDown(const FGeometry& InGeometry, const FKeyEvent& InKeyEvent)
{
	if (!bOpen)
	{
		return Super::NativeOnPreviewKeyDown(InGeometry, InKeyEvent);
	}

	const FKey Key = InKeyEvent.GetKey();
	if (Key == EKeys::Escape || Key == EKeys::Gamepad_FaceButton_Right)
	{
		if (!InKeyEvent.IsRepeat())
		{
			Close();
		}
		return FReply::Handled();
	}
	if (Key == EKeys::Gamepad_DPad_Up || Key == EKeys::Up)
	{
		ScrollBy(-52.f);
		return FReply::Handled();
	}
	if (Key == EKeys::Gamepad_DPad_Down || Key == EKeys::Down)
	{
		ScrollBy(52.f);
		return FReply::Handled();
	}

	// The modal owns focus while open so unrelated gamepad input cannot reach the
	// inventory or world behind it.
	return FReply::Handled();
}

FReply UFableItemInspectWidget::NativeOnAnalogValueChanged(const FGeometry& InGeometry, const FAnalogInputEvent& InAnalogInputEvent)
{
	if (!bOpen)
	{
		return Super::NativeOnAnalogValueChanged(InGeometry, InAnalogInputEvent);
	}

	if (InAnalogInputEvent.GetKey() == EKeys::Gamepad_RightY)
	{
		RightStickY = -InAnalogInputEvent.GetAnalogValue();
	}
	return FReply::Handled();
}

void UFableItemInspectWidget::RebuildContent()
{
	if (WidgetTree == nullptr)
	{
		return;
	}

	if (RootCanvas == nullptr)
	{
		RootCanvas = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("ItemInspectRootCanvas"));
		WidgetTree->RootWidget = RootCanvas;
	}
	RootCanvas->ClearChildren();
	RootCanvas->SetVisibility(bOpen ? ESlateVisibility::Visible : ESlateVisibility::Collapsed);

	UBorder* Scrim = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("ItemInspectScrim"));
	Scrim->SetBrushColor(ScrimColor);
	if (UCanvasPanelSlot* ScrimSlot = RootCanvas->AddChildToCanvas(Scrim))
	{
		ScrimSlot->SetAnchors(FAnchors(0.f, 0.f, 1.f, 1.f));
		ScrimSlot->SetOffsets(FMargin(0.f));
	}

	USizeBox* ModalBounds = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("ItemInspectModalBounds"));
	ModalBounds->SetWidthOverride(720.f);
	ModalBounds->SetHeightOverride(560.f);
	if (UCanvasPanelSlot* ModalSlot = RootCanvas->AddChildToCanvas(ModalBounds))
	{
		ModalSlot->SetAnchors(FAnchors(0.5f, 0.5f));
		ModalSlot->SetAlignment(FVector2D(0.5f, 0.5f));
		ModalSlot->SetPosition(FVector2D::ZeroVector);
		ModalSlot->SetSize(FVector2D(720.f, 560.f));
	}

	UBorder* GoldEdge = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("ItemInspectGoldEdge"));
	GoldEdge->SetBrushColor(FableBookStyle::Gold);
	GoldEdge->SetPadding(FMargin(3.f));
	ModalBounds->SetContent(GoldEdge);
	UBorder* Page = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("ItemInspectPage"));
	Page->SetBrushColor(ParchmentPage);
	Page->SetPadding(FMargin(24.f, 20.f, 24.f, 16.f));
	GoldEdge->SetContent(Page);

	UVerticalBox* Content = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("ItemInspectContent"));
	Page->SetContent(Content);

	UTextBlock* TitleText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("ItemInspectTitle"));
	TitleText->SetText(FText::FromString(Title));
	TitleText->SetFont(FableBookStyle::Font(26, true));
	TitleText->SetColorAndOpacity(FSlateColor(FableBookStyle::Ink));
	TitleText->SetJustification(ETextJustify::Center);
	Content->AddChildToVerticalBox(TitleText)->SetPadding(FMargin(0.f, 0.f, 0.f, 10.f));

	UHorizontalBox* Header = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass(), TEXT("ItemInspectHeader"));
	Content->AddChildToVerticalBox(Header)->SetPadding(FMargin(0.f, 0.f, 0.f, 12.f));
	if (Icon != nullptr)
	{
		USizeBox* IconBounds = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass(), TEXT("ItemInspectIconBounds"));
		IconBounds->SetWidthOverride(96.f);
		IconBounds->SetHeightOverride(96.f);
		if (UHorizontalBoxSlot* IconSlot = Header->AddChildToHorizontalBox(IconBounds))
		{
			IconSlot->SetVerticalAlignment(VAlign_Top);
			IconSlot->SetPadding(FMargin(0.f, 0.f, 18.f, 0.f));
		}
		UBorder* IconFrame = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("ItemInspectIconFrame"));
		IconFrame->SetBrushColor(ParchmentShadow);
		IconFrame->SetPadding(FMargin(3.f));
		IconBounds->SetContent(IconFrame);
		IconImage = WidgetTree->ConstructWidget<UImage>(UImage::StaticClass(), TEXT("ItemInspectIcon"));
		IconImage->SetBrushFromTexture(Icon, true);
		IconFrame->SetContent(IconImage);
	}

	UTextBlock* Summary = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("ItemInspectSummary"));
	Summary->SetText(FText::FromString(TEXT("Item details")));
	Summary->SetFont(FableBookStyle::Font(16, false));
	Summary->SetColorAndOpacity(FSlateColor(MutedInk));
	Summary->SetAutoWrapText(true);
	if (UHorizontalBoxSlot* SummarySlot = Header->AddChildToHorizontalBox(Summary))
	{
		SummarySlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		SummarySlot->SetVerticalAlignment(VAlign_Center);
	}

	DetailsScroll = WidgetTree->ConstructWidget<UScrollBox>(UScrollBox::StaticClass(), TEXT("ItemInspectDetailsScroll"));
	DetailsScroll->SetAlwaysShowScrollbar(false);
	DetailsScroll->SetScrollbarThickness(FVector2D(7.f, 7.f));
	if (UVerticalBoxSlot* ScrollSlot = Content->AddChildToVerticalBox(DetailsScroll))
	{
		ScrollSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		ScrollSlot->SetPadding(FMargin(0.f, 0.f, 0.f, 10.f));
	}
	UVerticalBox* DetailRows = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("ItemInspectDetailRows"));
	DetailsScroll->AddChild(DetailRows);
	for (const TPair<FString, FString>& Detail : Details)
	{
		UHorizontalBox* Row = WidgetTree->ConstructWidget<UHorizontalBox>(UHorizontalBox::StaticClass());
		if (UVerticalBoxSlot* RowSlot = DetailRows->AddChildToVerticalBox(Row))
		{
			RowSlot->SetPadding(FMargin(0.f, 0.f, 6.f, 8.f));
		}

		UTextBlock* Label = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		Label->SetText(FText::FromString(Detail.Key));
		Label->SetFont(FableBookStyle::Font(20, true));
		Label->SetColorAndOpacity(FSlateColor(MutedInk));
		Label->SetAutoWrapText(true);
		USizeBox* LabelBounds = WidgetTree->ConstructWidget<USizeBox>(USizeBox::StaticClass());
		LabelBounds->SetWidthOverride(200.f);
		LabelBounds->SetContent(Label);
		if (UHorizontalBoxSlot* LabelSlot = Row->AddChildToHorizontalBox(LabelBounds))
		{
			LabelSlot->SetSize(FSlateChildSize(ESlateSizeRule::Automatic));
			LabelSlot->SetVerticalAlignment(VAlign_Top);
			LabelSlot->SetPadding(FMargin(0.f, 0.f, 14.f, 0.f));
		}

		UTextBlock* Value = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		Value->SetText(FText::FromString(Detail.Value));
		Value->SetFont(FableBookStyle::Font(20, false));
		Value->SetColorAndOpacity(FSlateColor(FableBookStyle::Ink));
		Value->SetAutoWrapText(true);
		if (UHorizontalBoxSlot* ValueSlot = Row->AddChildToHorizontalBox(Value))
		{
			ValueSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
			ValueSlot->SetVerticalAlignment(VAlign_Top);
		}
	}

	CloseButton = WidgetTree->ConstructWidget<UButton>(UButton::StaticClass(), TEXT("ItemInspectCloseButton"));
	FableBookStyle::ApplyButton(CloseButton);
	CloseButton->OnClicked.AddDynamic(this, &UFableItemInspectWidget::HandleCloseClicked);
	UTextBlock* CloseText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("ItemInspectCloseText"));
	CloseText->SetText(FText::FromString(TEXT("Circle / Esc — Close")));
	CloseText->SetFont(FableBookStyle::Font(16, true));
	CloseText->SetColorAndOpacity(FSlateColor(FableBookStyle::Ink));
	CloseText->SetJustification(ETextJustify::Center);
	CloseButton->SetContent(CloseText);
	CloseButton->SetBackgroundColor(FLinearColor(0.9f, 0.8f, 0.6f, 1.f));
	if (UVerticalBoxSlot* CloseSlot = Content->AddChildToVerticalBox(CloseButton))
	{
		CloseSlot->SetHorizontalAlignment(HAlign_Center);
		CloseSlot->SetPadding(FMargin(0.f, 0.f, 0.f, 0.f));
	}
}
