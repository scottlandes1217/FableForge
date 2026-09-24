#include "RPG/UI/FableActionButton.h"
#include "Brushes/SlateRoundedBoxBrush.h"

UFableActionButton::UFableActionButton()
{
	// Neutral fills let each screen tint its controls without the engine's blue gradient.
	FButtonStyle Style = GetStyle();
	Style.SetNormal(FSlateRoundedBoxBrush(FLinearColor::White, 4.0f, FLinearColor(0.45f, 0.39f, 0.26f, 0.65f), 1.0f));
	Style.SetHovered(FSlateRoundedBoxBrush(FLinearColor(1.35f, 1.35f, 1.35f), 4.0f, FLinearColor(0.90f, 0.70f, 0.35f), 1.5f));
	Style.SetPressed(FSlateRoundedBoxBrush(FLinearColor(0.72f, 0.72f, 0.72f), 4.0f, FLinearColor(0.95f, 0.77f, 0.43f), 1.5f));
	Style.SetDisabled(FSlateRoundedBoxBrush(FLinearColor(0.45f, 0.45f, 0.45f), 4.0f, FLinearColor(0.25f, 0.25f, 0.23f), 1.0f));
	Style.SetNormalPadding(FMargin(12.0f, 7.0f));
	Style.SetPressedPadding(FMargin(12.0f, 8.0f, 12.0f, 6.0f));
	SetStyle(Style);
}

void UFableActionButton::InitializeAction(FName InActionId)
{
	ActionId = InActionId;
	OnClicked.Clear();
	OnClicked.AddDynamic(this, &UFableActionButton::HandleInternalClicked);
	bIsBoundToClick = true;
}

void UFableActionButton::HandleInternalClicked()
{
	OnActionClicked.Broadcast(ActionId);
}
