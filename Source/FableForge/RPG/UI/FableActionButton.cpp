#include "RPG/UI/FableActionButton.h"

UFableActionButton::UFableActionButton()
{
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
