#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
#include "HAL/IConsoleManager.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "GameFramework/Character.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/SpringArmComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/StaticMeshComponent.h"
#include "RPG/Save/FableSaveSubsystem.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/StaticMesh.h"
#include "UObject/UObjectIterator.h"
#include "Blueprint/WidgetTree.h"
#include "Components/Viewport.h"
#include "Components/TextBlock.h"
#include "RPG/UI/FablePartyHudWidget.h"
#include "RPG/UI/FableInventorySlotWidget.h"
#include "RPG/UI/FableWheelAssignmentWidget.h"
#include "EngineUtils.h"
#include "Camera/CameraActor.h"
#include "Camera/CameraComponent.h"
#include "UnrealClient.h"
#include "TimerManager.h"
#include "Containers/Ticker.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "Engine/Engine.h"
#include "FableForgePlayerController.h"
#include "Interaction/FFChestInteractable.h"
#include "Framework/Application/SlateApplication.h"
#include "Input/Events.h"
#include "GameFramework/PlayerInput.h"
#include "GameFramework/WorldSettings.h"

// Opt-in file queue in an isolated test profile. No desktop input or focus is used.
static FAutoConsoleCommandWithWorldAndArgs QaQueue(
 TEXT("FableForge.QaQueue"), TEXT("Poll QA.txt in an isolated UserDir for backend QA commands."),
 FConsoleCommandWithWorldAndArgsDelegate::CreateLambda([](const TArray<FString>&, UWorld* World)
 {
  FString Dir;
  if (!World || !FParse::Value(FCommandLine::Get(), TEXT("UserDir="), Dir) || !Dir.StartsWith(TEXT("/tmp/FableForge"))) return;
  static bool Started=false;
  if (Started) return;
  Started=true;
  TWeakObjectPtr<UWorld> WeakWorld(World);
  FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([WeakWorld, Dir, Last=FString()](float) mutable
  {
   if (!WeakWorld.IsValid()) return false;
   FString Contents;
   if (!FFileHelper::LoadFileToString(Contents, *(Dir/TEXT("QA.txt"))) || Contents==Last) return true;
   Last=Contents;
   TArray<FString> Lines; Contents.ParseIntoArrayLines(Lines);
   for (FString Line:Lines)
   {
    Line.TrimStartAndEndInline();
    if (Line.StartsWith(TEXT("FableForge.Creator")) || Line.StartsWith(TEXT("FableForge.GameplayQA ")))
     GEngine->Exec(WeakWorld.Get(), *Line);
   }
   UE_LOG(LogTemp,Display,TEXT("QA_QUEUE processed command file"));
   return true;
  }), .25f);
 }));

static FAutoConsoleCommandWithWorldAndArgs GameplayQa(
 TEXT("FableForge.GameplayQA"), TEXT("Isolated QA only: inspect, equip <slot> <item>, unequip <slot>, jump, camera <yaw> <pitch> <distance>."),
 FConsoleCommandWithWorldAndArgsDelegate::CreateLambda([](const TArray<FString>& Args, UWorld* World)
 {
  FString UserDir;
  if (!FParse::Value(FCommandLine::Get(), TEXT("UserDir="), UserDir) || !UserDir.StartsWith(TEXT("/tmp/FableForge")))
  { UE_LOG(LogTemp, Warning, TEXT("GAMEPLAY_QA refused: requires isolated /tmp/FableForge UserDir")); return; }
  APlayerController* PC = World ? World->GetFirstPlayerController() : nullptr;
	if (Args.Num() == 3 && Args[0] == TEXT("journalclick") && PC)
	{
		for (TObjectIterator<UFableWheelAssignmentWidget> It; It; ++It)
		{
			if (It->GetWorld() != World || !It->IsOpen()) continue;
			const FGeometry Geometry = It->GetCachedGeometry();
			const FVector2D Point = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * .5f + FVector2D(FCString::Atof(*Args[1]), FCString::Atof(*Args[2])));
			const TSet<FKey> Buttons{EKeys::LeftMouseButton};
			const FPointerEvent Pointer(0, Point, Point, Buttons, EKeys::LeftMouseButton, 0.f, FModifierKeysState());
			// Exercise the runtime pointer handler with the live widget geometry.
			const bool bHandled = It->NativeOnMouseButtonDown(Geometry, Pointer).IsEventHandled();
			UE_LOG(LogTemp, Display, TEXT("JOURNAL_CLICK x=%s y=%s handled=%d still_open=%d"), *Args[1], *Args[2], bHandled, It->IsOpen());
			break;
		}
		return;
	}
	if (Args.Num() == 3 && Args[0] == TEXT("journalanalog") && PC)
	{
		const FAnalogInputEvent Event(FKey(*Args[1]), FModifierKeysState(), 0, false, 0, 0, FCString::Atof(*Args[2]));
		const bool bHandled = FSlateApplication::Get().ProcessAnalogInputEvent(Event);
		UE_LOG(LogTemp, Display, TEXT("JOURNAL_ANALOG key=%s value=%s handled=%d"), *Args[1], *Args[2], bHandled);
		return;
	}
	if (Args.Num() == 1 && Args[0] == TEXT("journalstate") && PC)
	{
		TArray<FString> Bag, Equipment;
		TArray<FFableQuickWheelPageData> Pages;
		if (auto* Saves = World->GetGameInstance()->GetSubsystem<UFableSaveSubsystem>())
		{
			Saves->TryGetActiveInventory(Bag, Equipment);
			Saves->TryGetActiveQuickWheelPages(Pages);
			UE_LOG(LogTemp, Display, TEXT("JOURNAL_STATE bag=%s equipment=%s time=%.2f move_blocked=%d look_blocked=%d"),
				*FString::Join(Bag, TEXT("|")), *FString::Join(Equipment, TEXT("|")), World->GetWorldSettings()->TimeDilation, PC->IsMoveInputIgnored(), PC->IsLookInputIgnored());
			for (int32 I = 0; I < Pages.Num(); ++I)
			{
				TArray<FString> Payloads;
				for (const auto& Slot : Pages[I].Slots) Payloads.Add(Slot.EntryId);
				UE_LOG(LogTemp, Display, TEXT("JOURNAL_WHEEL page=%d slots=%s"), I, *FString::Join(Payloads, TEXT("|")));
			}
		}
		return;
	}
	if (Args.Num() == 2 && Args[0] == TEXT("journalkey") && PC)
	{
		const FKey Key(*Args[1]);
		const FKeyEvent Event(Key, FModifierKeysState(), 0, false, 0, 0);
		const bool bHandled = FSlateApplication::Get().ProcessKeyDownEvent(Event);
		FSlateApplication::Get().ProcessKeyUpEvent(Event);
		UE_LOG(LogTemp, Display, TEXT("JOURNAL_KEY key=%s handled=%d"), *Args[1], bHandled);
		return;
	}
	if (Args.Num() == 3 && Args[0] == TEXT("journaldrop"))
	{
		for (TObjectIterator<UFableInventorySlotWidget> It; It; ++It)
		{
			if (It->GetWorld() == World && It->GetSlotId() == FName(*Args[2]))
			{
				It->OnItemDrop.Broadcast(FName(*Args[1]), FName(*Args[2]), FString(), FString());
				break;
			}
		}
		TArray<FString> Bag, Equipment;
		if (auto* Saves = World->GetGameInstance()->GetSubsystem<UFableSaveSubsystem>(); Saves && Saves->TryGetActiveInventory(Bag, Equipment))
			UE_LOG(LogTemp, Display, TEXT("JOURNAL_DROP from=%s to=%s bag=%s equipment=%s"), *Args[1], *Args[2], *FString::Join(Bag, TEXT("|")), *FString::Join(Equipment, TEXT("|")));
		return;
	}
	if (Args.Num() > 0 && Args[0] == TEXT("journalscreenshot"))
	{
		FScreenshotRequest::RequestScreenshot(TEXT("/tmp/FableForge-journal-verified.png"), true, false);
		return;
	}
  if (Args.Num() > 0 && (Args[0] == TEXT("wheelcapture") || Args[0] == TEXT("quickwheelcapture") || Args[0] == TEXT("inventorycapture") || Args[0] == TEXT("skillscapture") || Args[0] == TEXT("inventorywheelcapture")))
  {
   if (AFableForgePlayerController* Fable = Cast<AFableForgePlayerController>(PC))
   {
    if (UFableSaveSubsystem* Saves = World->GetGameInstance()->GetSubsystem<UFableSaveSubsystem>())
    {
     const FGuid QaCharacterId = Saves->CreateCharacter(TEXT("Wheel QA"), TEXT("human"), EFableGender::Male);
     Fable->EnterGameFromCharacterSlot(QaCharacterId, 0, true);
     if (Args[0] == TEXT("quickwheelcapture")) Fable->OpenQuickWheelForQa();
     else if (Args[0] == TEXT("inventorycapture")) Fable->ToggleCharacterMenu();
     else if (Args[0] == TEXT("skillscapture")) { Fable->OpenSkillsForQa(); }
     else if (Args[0] == TEXT("inventorywheelcapture")) { Fable->ToggleCharacterMenu(); Fable->OpenWheelAssignment(); }
     else Fable->OpenWheelAssignment();
    }
   }
   return;
  }
  ACharacter* Character = PC ? Cast<ACharacter>(PC->GetPawn()) : nullptr;
  if (!Character || Args.IsEmpty()) return;
   if (Args[0]==TEXT("inputsmoke"))
   {
    if (auto* Fable=Cast<AFableForgePlayerController>(PC)) Fable->RunControllerInputSmokeTest();
   }
   else if (Args[0]==TEXT("restore")) { PC->SetViewTarget(Character); }
  else if (Args[0]==TEXT("inventory")) { if (auto* Fable=Cast<AFableForgePlayerController>(PC)) Fable->ToggleCharacterMenu(); }
  else if (Args[0]==TEXT("chest"))
  {
   if (auto* Fable=Cast<AFableForgePlayerController>(PC))
    for (TActorIterator<AFFChestInteractable> It(World);It;++It) { Fable->OpenChest(*It); break; }
  }
  else if (Args[0]==TEXT("closechest")) { if (auto* Fable=Cast<AFableForgePlayerController>(PC)) Fable->CloseChest(); }
  else if (Args[0]==TEXT("armorcycle"))
  {
   TWeakObjectPtr<UWorld> WeakWorld(World);
   auto ChangeChest=[WeakWorld](bool Equipped)
   {
    if (!WeakWorld.IsValid() || !WeakWorld->GetGameInstance()) return;
    UFableSaveSubsystem* Saves=WeakWorld->GetGameInstance()->GetSubsystem<UFableSaveSubsystem>();
    TArray<FString> Bag, Equipment;
    if (Saves && Saves->TryGetActiveInventory(Bag,Equipment))
    {
     Equipment.SetNum(UFableSaveSubsystem::EquipmentSlotsPerCharacter);
     Equipment[3]=Equipped ? TEXT("peasant_chest") : TEXT("");
     Saves->SetActiveInventory(Bag,Equipment);
    }
   };
   FTimerHandle A,B,C,D;
   World->GetTimerManager().SetTimer(A,FTimerDelegate::CreateLambda([ChangeChest](){ ChangeChest(false); }),3.f,false);
   World->GetTimerManager().SetTimer(B,FTimerDelegate::CreateLambda([](){ FScreenshotRequest::RequestScreenshot(TEXT("PortraitUnequippedQA"),true,true); }),4.f,false);
   World->GetTimerManager().SetTimer(C,FTimerDelegate::CreateLambda([ChangeChest](){ ChangeChest(true); }),5.f,false);
   World->GetTimerManager().SetTimer(D,FTimerDelegate::CreateLambda([](){ FScreenshotRequest::RequestScreenshot(TEXT("PortraitEquippedQA"),true,true); }),6.f,false);
  }
  else if (Args[0]==TEXT("jumpcapture"))
  {
   TWeakObjectPtr<ACharacter> WeakCharacter(Character);
   FTimerHandle JumpTimer, ShotTimer;
   World->GetTimerManager().SetTimer(JumpTimer,FTimerDelegate::CreateLambda([WeakCharacter](){ if (WeakCharacter.IsValid()) WeakCharacter->Jump(); }),1.5f,false);
   World->GetTimerManager().SetTimer(ShotTimer,FTimerDelegate::CreateLambda([](){ FScreenshotRequest::RequestScreenshot(TEXT("JumpQA"),true,true); }),1.85f,false);
  }
  else if (Args[0]==TEXT("capture"))
  {
   FTimerHandle Timer;
   World->GetTimerManager().SetTimer(Timer,FTimerDelegate::CreateLambda([](){ FScreenshotRequest::RequestScreenshot(TEXT("GameplayQA"),true,true); }),2.f,false);
  }
  else if (Args[0]==TEXT("equip") || Args[0]==TEXT("unequip"))
  {
   int32 Slot=INDEX_NONE;
   if (Args.Num()<2 || !LexTryParseString(Slot,*Args[1]) || Slot<0 || Slot>=UFableSaveSubsystem::EquipmentSlotsPerCharacter) return;
   if (Args[0]==TEXT("equip") && Args.Num()!=3) return;
   UFableSaveSubsystem* Saves=World->GetGameInstance()->GetSubsystem<UFableSaveSubsystem>();
   TArray<FString> Bag, Equipment;
   if (Saves && Saves->TryGetActiveInventory(Bag,Equipment))
   {
    Equipment.SetNum(UFableSaveSubsystem::EquipmentSlotsPerCharacter);
    Equipment[Slot]=Args[0]==TEXT("equip") ? Args[2] : FString();
    Saves->SetActiveInventory(Bag,Equipment);
    UE_LOG(LogTemp,Display,TEXT("GAMEPLAY_QA equipment slot=%d item=%s"),Slot,*Equipment[Slot]);
   }
  }
  else if (Args[0]==TEXT("jump")) Character->Jump();
  else if (Args[0]==TEXT("bodyvisible") && Args.Num()==2)
  {
   Character->GetMesh()->SetVisibility(Args[1]!=TEXT("0"),false);
  }
  else if (Args[0]==TEXT("detail") && Args.Num()==4)
  {
   float Height,Distance,Yaw;
   if (LexTryParseString(Height,*Args[1]) && LexTryParseString(Distance,*Args[2]) && LexTryParseString(Yaw,*Args[3]))
   {
    const FVector Focus=Character->GetMesh()->GetComponentLocation()+FVector(0,0,Height*Character->GetActorScale3D().Z);
    const FVector Position=Focus+FRotator(0,Yaw,0).Vector()*FMath::Clamp(Distance,30.f,600.f);
    ACameraActor* Camera=World->SpawnActor<ACameraActor>(Position,(Focus-Position).Rotation());
    if (Camera)
    {
     Camera->GetCameraComponent()->SetFieldOfView(40.f); PC->SetViewTarget(Camera);
     TWeakObjectPtr<APlayerController> WeakPC(PC);
     TWeakObjectPtr<ACameraActor> WeakCamera(Camera);
     FTimerHandle RestoreTimer;
     World->GetTimerManager().SetTimer(RestoreTimer, FTimerDelegate::CreateLambda([WeakPC,WeakCamera]()
     {
      if (WeakPC.IsValid() && WeakPC->GetViewTarget()==WeakCamera.Get()) WeakPC->SetViewTarget(WeakPC->GetPawn());
      if (WeakCamera.IsValid()) WeakCamera->Destroy();
     }), 6.f, false);
    }
   }
  }
  else if (Args[0]==TEXT("camera") && Args.Num()==4)
  {
   float Yaw,Pitch,Distance;
   if (LexTryParseString(Yaw,*Args[1]) && LexTryParseString(Pitch,*Args[2]) && LexTryParseString(Distance,*Args[3]))
   {
    PC->SetViewTarget(Character);
    PC->SetControlRotation(FRotator(Pitch,Yaw,0));
    if (USpringArmComponent* Arm=Character->FindComponentByClass<USpringArmComponent>()) Arm->TargetArmLength=FMath::Clamp(Distance,50.f,600.f);
   }
  }
  else if (Args[0]==TEXT("portrait"))
  {
   for (TObjectIterator<UFablePartyHudWidget> It; It; ++It)
   {
    if (!IsValid(*It) || It->IsTemplate() || It->GetWorld()!=World || !It->WidgetTree) continue;
    TArray<UWidget*> Widgets; It->WidgetTree->GetAllWidgets(Widgets);
    for (UWidget* Widget : Widgets)
    {
     if (UViewport* View=Cast<UViewport>(Widget))
     {
      UE_LOG(LogTemp,Display,TEXT("GAMEPLAY_QA portrait viewport=%s world=%s location=%s"),*View->GetName(),*GetNameSafe(View->GetViewportWorld()),*View->GetViewLocation().ToString());
      if (UWorld* PreviewWorld=View->GetViewportWorld())
       for (TActorIterator<AActor> Actor(PreviewWorld); Actor; ++Actor)
       {
        TArray<USkeletalMeshComponent*> Meshes; Actor->GetComponents(Meshes);
        for (USkeletalMeshComponent* Mesh : Meshes)
         UE_LOG(LogTemp,Display,TEXT("GAMEPLAY_QA portrait mesh=%s leader=%s"),*GetNameSafe(Mesh->GetSkeletalMeshAsset()),*GetNameSafe(Mesh->LeaderPoseComponent.Get()));
       }
     }
    }
   }
  }
  else if (Args[0]==TEXT("inspect"))
  {
   USkeletalMeshComponent* Body=Character->GetMesh();
   UE_LOG(LogTemp,Display,TEXT("GAMEPLAY_QA body=%s component=%s anim=%s yaw=%.2f"),*GetNameSafe(Body->GetSkeletalMeshAsset()),*Body->GetClass()->GetName(),*GetNameSafe(Body->GetAnimInstance()),Character->GetActorRotation().Yaw);
   for (USceneComponent* Child:Body->GetAttachChildren())
   {
    UObject* Asset=nullptr;
    if (USkeletalMeshComponent* Skinned=Cast<USkeletalMeshComponent>(Child)) Asset=Skinned->GetSkeletalMeshAsset();
    if (UStaticMeshComponent* Rigid=Cast<UStaticMeshComponent>(Child)) Asset=Rigid->GetStaticMesh();
    if (Asset) UE_LOG(LogTemp,Display,TEXT("GAMEPLAY_QA attachment=%s socket=%s visible=%d"),*Asset->GetPathName(),*Child->GetAttachSocketName().ToString(),Child->IsVisible());
   }
  }
 }));
#endif
