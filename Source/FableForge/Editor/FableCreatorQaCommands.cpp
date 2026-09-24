#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
#include "HAL/IConsoleManager.h"
#include "Input/Events.h"
#include "InputCoreTypes.h"
#include "UObject/UObjectIterator.h"
#include "Blueprint/WidgetTree.h"
#include "Components/PanelWidget.h"
#include "Components/Slider.h"
#include "Components/Viewport.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/StaticMesh.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "RPG/UI/FableMainMenuWidget.h"
#include "RPG/UI/FableActionButton.h"

namespace FableCreatorQa
{
static UFableMainMenuWidget* FindMenu()
{
 UFableMainMenuWidget* Found=nullptr;
 for(TObjectIterator<UFableMainMenuWidget> It;It;++It)
 {
  UFableMainMenuWidget* Menu=*It;
  if(!IsValid(Menu) || Menu->IsTemplate() || !Menu->IsInViewport() || !Menu->IsVisible() || !Menu->WidgetTree) continue;
  if(Found) { UE_LOG(LogTemp,Warning,TEXT("CREATOR_QA: multiple visible menus; refusing ambiguous action")); return nullptr; }
  Found=Menu;
 }
 if(!Found) UE_LOG(LogTemp,Warning,TEXT("CREATOR_QA: no visible menu"));
 return Found;
}
static bool IsInteractable(UWidget* Widget)
{
 for(UWidget* Current=Widget;Current;Current=Current->GetParent())
 {
  if(!Current->IsVisible() || !Current->GetIsEnabled()) return false;
 }
 return true;
}
}

static FAutoConsoleCommand CreatorAction(
 TEXT("FableForge.CreatorAction"),TEXT("Editor QA: activate an existing visible creator ActionId."),
 FConsoleCommandWithArgsDelegate::CreateLambda([](const TArray<FString>& Args)
 {
  if(Args.Num()!=1) { UE_LOG(LogTemp,Warning,TEXT("Usage: FableForge.CreatorAction <ActionId>")); return; }
  UFableMainMenuWidget* Menu=FableCreatorQa::FindMenu();if(!Menu) return;
  TArray<UWidget*> Widgets;Menu->WidgetTree->GetAllWidgets(Widgets);
  const FName Action(*Args[0]);
  for(UWidget* Widget:Widgets)
  {
   UFableActionButton* Button=Cast<UFableActionButton>(Widget);
   if(Button && Button->ActionId==Action && FableCreatorQa::IsInteractable(Button))
   {
    UE_LOG(LogTemp,Display,TEXT("CREATOR_QA_ACTION %s"),*Action.ToString());
    Button->OnActionClicked.Broadcast(Action);return;
   }
  }
  UE_LOG(LogTemp,Warning,TEXT("CREATOR_QA: visible enabled action not found: %s"),*Args[0]);
 }));

static FAutoConsoleCommand CreatorStability(
 TEXT("FableForge.CreatorStability"),TEXT("Editor QA: verify a visible action retains its viewport, world and camera."),
 FConsoleCommandWithArgsDelegate::CreateLambda([](const TArray<FString>& Args)
 {
  if(Args.Num()!=1) return;
  UFableMainMenuWidget* Menu=FableCreatorQa::FindMenu(); if(!Menu) return;
  TArray<UWidget*> Before; Menu->WidgetTree->GetAllWidgets(Before);
  UViewport* View=nullptr; UFableActionButton* Action=nullptr;
  for(UWidget* Widget:Before)
  {
   if(UViewport* Candidate=Cast<UViewport>(Widget)) View=Candidate;
   if(UFableActionButton* Button=Cast<UFableActionButton>(Widget))
    if(Button->ActionId==FName(*Args[0]) && FableCreatorQa::IsInteractable(Button)) Action=Button;
  }
  if(!View || !Action) { UE_LOG(LogTemp,Error,TEXT("CREATOR_STABILITY missing viewport/action")); return; }
  UWorld* World=View->GetViewportWorld(); const FVector Location=View->GetViewLocation(); const FRotator Rotation=View->GetViewRotation();
  Action->OnActionClicked.Broadcast(Action->ActionId);
  TArray<UWidget*> After; Menu->WidgetTree->GetAllWidgets(After);
  const bool Stable=After.Contains(View) && View->GetViewportWorld()==World && View->GetViewLocation().Equals(Location,.001f) && View->GetViewRotation().Equals(Rotation,.001f);
  if(Stable) { UE_LOG(LogTemp,Display,TEXT("CREATOR_STABILITY PASS action=%s viewport=%s world=%s button_retained=%d"),*Args[0],*View->GetName(),*GetNameSafe(World),After.Contains(Action)); }
  else { UE_LOG(LogTemp,Error,TEXT("CREATOR_STABILITY FAIL action=%s"),*Args[0]); }
 }));

static FAutoConsoleCommand CreatorSlider(
 TEXT("FableForge.CreatorSlider"),TEXT("Editor QA: change an existing visible named creator slider through its normal callback."),
 FConsoleCommandWithArgsDelegate::CreateLambda([](const TArray<FString>& Args)
 {
  float Value=0.f;
  if(Args.Num()!=2 || !LexTryParseString(Value,*Args[1]) || !FMath::IsFinite(Value))
  { UE_LOG(LogTemp,Warning,TEXT("Usage: FableForge.CreatorSlider <WidgetName> <finite value>"));return; }
  UFableMainMenuWidget* Menu=FableCreatorQa::FindMenu();if(!Menu) return;
  TArray<UWidget*> Widgets;Menu->WidgetTree->GetAllWidgets(Widgets);
  for(UWidget* Widget:Widgets)
  {
   USlider* Slider=Cast<USlider>(Widget);
   if(Slider && (Slider->GetFName()==FName(*Args[0]) || Slider->GetName().StartsWith(Args[0]+TEXT("_"))) && FableCreatorQa::IsInteractable(Slider) && !Slider->IsLocked())
   {
    Value=FMath::Clamp(Value,Slider->GetMinValue(),Slider->GetMaxValue());
    Slider->SetValue(Value);
    UE_LOG(LogTemp,Display,TEXT("CREATOR_QA_SLIDER %s=%.4f"),*Args[0],Value);
    Slider->OnValueChanged.Broadcast(Value);return;
   }
  }
  UE_LOG(LogTemp,Warning,TEXT("CREATOR_QA: visible enabled slider not found: %s"),*Args[0]);
 }));

static FAutoConsoleCommand CreatorInspect(
 TEXT("FableForge.CreatorInspect"),TEXT("Editor QA: log current creator controls, preview mesh, morphs, colors and attached hair."),
 FConsoleCommandDelegate::CreateLambda([]()
 {
  UFableMainMenuWidget* Menu=FableCreatorQa::FindMenu();if(!Menu) return;
  TArray<UWidget*> Widgets;Menu->WidgetTree->GetAllWidgets(Widgets);
  for(UWidget* Widget:Widgets)
  {
   if(USlider* Slider=Cast<USlider>(Widget))
    UE_LOG(LogTemp,Display,TEXT("CREATOR_QA_SLIDER_GEOMETRY name=%s visible=%d visibility=%d size=%s absolute=%s"),*Slider->GetName(),Slider->IsVisible(),static_cast<int32>(Slider->GetVisibility()),*Slider->GetCachedGeometry().GetLocalSize().ToString(),*Slider->GetCachedGeometry().GetAbsolutePosition().ToString());
   if(UViewport* Viewport=Cast<UViewport>(Widget))
    UE_LOG(LogTemp,Display,TEXT("CREATOR_QA_VIEWPORT name=%s visible=%d visibility=%d world=%s size=%s absolute=%s"),*Viewport->GetName(),Viewport->IsVisible(),static_cast<int32>(Viewport->GetVisibility()),*GetNameSafe(Viewport->GetViewportWorld()),*Viewport->GetCachedGeometry().GetLocalSize().ToString(),*Viewport->GetCachedGeometry().GetAbsolutePosition().ToString());
   if(!Widget->IsVisible() && !Cast<UViewport>(Widget)) continue;
   if(UFableActionButton* Button=Cast<UFableActionButton>(Widget))
    UE_LOG(LogTemp,Display,TEXT("CREATOR_QA_CONTROL action=%s enabled=%d"),*Button->ActionId.ToString(),FableCreatorQa::IsInteractable(Button));
   if(USlider* Slider=Cast<USlider>(Widget))
    UE_LOG(LogTemp,Display,TEXT("CREATOR_QA_CONTROL slider=%s value=%.4f range=[%.3f,%.3f]"),*Slider->GetName(),Slider->GetValue(),Slider->GetMinValue(),Slider->GetMaxValue());
   UViewport* Viewport=Cast<UViewport>(Widget);if(!Viewport || !Viewport->GetViewportWorld()) continue;
   UWorld* World=Viewport->GetViewportWorld();
   UE_LOG(LogTemp,Display,TEXT("CREATOR_QA_CAMERA location=%s rotation=%s"),*Viewport->GetViewLocation().ToString(),*Viewport->GetViewRotation().ToString());
   for(TObjectIterator<USkeletalMeshComponent> It;It;++It)
   {
    USkeletalMeshComponent* Mesh=*It;
    if(!IsValid(Mesh) || Mesh->IsTemplate() || Mesh->GetWorld()!=World || !Mesh->IsRegistered() || !Mesh->IsVisible()) continue;
    UE_LOG(LogTemp,Display,TEXT("CREATOR_QA_MESH %s scale=%s"),*GetPathNameSafe(Mesh->GetSkeletalMeshAsset()),*Mesh->GetRelativeScale3D().ToString());
    for(const auto& Morph:Mesh->GetMorphTargetCurves())
     UE_LOG(LogTemp,Display,TEXT("CREATOR_QA_MORPH %s=%.4f"),*Morph.Key.ToString(),Morph.Value);
    for(int32 Slot=0;Slot<Mesh->GetNumMaterials();++Slot)
    {
     UMaterialInstanceDynamic* Material=Cast<UMaterialInstanceDynamic>(Mesh->GetMaterial(Slot));
     if(!Material) continue;
     for(FName Parameter:{FName(TEXT("SkinTint")),FName(TEXT("EyeTint")),FName(TEXT("HairTint"))})
      UE_LOG(LogTemp,Display,TEXT("CREATOR_QA_COLOR slot=%d %s=%s"),Slot,*Parameter.ToString(),*Material->K2_GetVectorParameterValue(Parameter).ToString());
    }
   }
   for(TObjectIterator<UStaticMeshComponent> It;It;++It)
   {
    UStaticMeshComponent* Mesh=*It;
    if(!IsValid(Mesh) || Mesh->IsTemplate() || Mesh->GetWorld()!=World || !Mesh->IsRegistered() || !Mesh->IsVisible() || !Mesh->GetStaticMesh()) continue;
    UE_LOG(LogTemp,Display,TEXT("CREATOR_QA_STYLE %s socket=%s relative=%s"),*Mesh->GetStaticMesh()->GetPathName(),*Mesh->GetAttachSocketName().ToString(),*Mesh->GetRelativeTransform().ToString());
   }
  }
 }));
static FAutoConsoleCommand CreatorPointer(
 TEXT("FableForge.CreatorPointer"),TEXT("Editor QA: CreatorPointer drag <horizontal screen pixels> or wheel <wheel delta>; invokes native creator pointer callbacks."),
 FConsoleCommandWithArgsDelegate::CreateLambda([](const TArray<FString>& Args)
 {
  float Amount=0.f;
  if(Args.Num()!=2 || (Args[0]!=TEXT("drag") && Args[0]!=TEXT("pan") && Args[0]!=TEXT("wheel")) || !LexTryParseString(Amount,*Args[1]) || !FMath::IsFinite(Amount))
  { UE_LOG(LogTemp,Warning,TEXT("Usage: FableForge.CreatorPointer <drag|pan|wheel> <finite amount>"));return; }
  UFableMainMenuWidget* Menu=FableCreatorQa::FindMenu();if(!Menu) return;
  TArray<UWidget*> Widgets;Menu->WidgetTree->GetAllWidgets(Widgets);
  UViewport* Viewport=nullptr;
  for(UWidget* Widget:Widgets)
  {
   UViewport* Candidate=Cast<UViewport>(Widget);
   if(Candidate && Candidate->IsVisible()) { Viewport=Candidate;break; }
  }
  if(!Viewport) { UE_LOG(LogTemp,Warning,TEXT("CREATOR_QA_POINTER: no visible viewport in current widget tree"));return; }
  const FGeometry ViewGeometry=Viewport->GetCachedGeometry();
  const FGeometry MenuGeometry=Menu->GetCachedGeometry();
  const FVector2D Size=ViewGeometry.GetLocalSize();
  if(Size.X<=1 || Size.Y<=1 || MenuGeometry.GetLocalSize().X<=1 || MenuGeometry.GetLocalSize().Y<=1)
  { UE_LOG(LogTemp,Warning,TEXT("CREATOR_QA_POINTER: invalid cached geometry viewport=%s menu=%s"),*Size.ToString(),*MenuGeometry.GetLocalSize().ToString());return; }
  const FVector2D Center=ViewGeometry.LocalToAbsolute(Size*.5);
  TSet<FKey> Pressed;
  const FModifierKeysState Modifiers;
  if(Args[0]==TEXT("wheel"))
  {
   const FPointerEvent Event(0,Center,Center,Pressed,EKeys::Invalid,Amount,Modifiers);
   const FReply Reply=Menu->NativeOnMouseWheel(MenuGeometry,Event);
   UE_LOG(LogTemp,Display,TEXT("CREATOR_QA_POINTER wheel=%.3f center=%s handled=%d"),Amount,*Center.ToString(),Reply.IsEventHandled());
   return;
  }
  Pressed.Add(EKeys::LeftMouseButton);
  const FVector2D End=Center+(Args[0]==TEXT("pan") ? FVector2D(0,Amount) : FVector2D(Amount,0));
  const FPointerEvent Down(0,Center,Center,Pressed,EKeys::LeftMouseButton,0,Modifiers);
  const FReply DownReply=Menu->NativeOnMouseButtonDown(MenuGeometry,Down);
  const FPointerEvent Move(0,End,Center,Pressed,EKeys::Invalid,0,Modifiers);
  const FReply MoveReply=Menu->NativeOnMouseMove(MenuGeometry,Move);
  TSet<FKey> Released;
  const FPointerEvent Up(0,End,End,Released,EKeys::LeftMouseButton,0,Modifiers);
  const FReply UpReply=Menu->NativeOnMouseButtonUp(MenuGeometry,Up);
  UE_LOG(LogTemp,Display,TEXT("CREATOR_QA_POINTER %s=%.3f center=%s down=%d move=%d up=%d"),*Args[0],Amount,*Center.ToString(),DownReply.IsEventHandled(),MoveReply.IsEventHandled(),UpReply.IsEventHandled());
 }));
#endif
