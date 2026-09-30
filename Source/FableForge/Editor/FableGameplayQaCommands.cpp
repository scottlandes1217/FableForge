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
#include "Components/BoxComponent.h"
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
#include "Interaction/FFDoorInteractable.h"
#include "Interaction/FFItemInteractable.h"
#include "RPG/UI/FableChestWidget.h"
#include "RPG/Gameplay/FableSpellRuntime.h"
#include "RPG/Gameplay/FableSpellVisualActor.h"
#include "RPG/UI/FableTimeWheelWidget.h"
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
	if (Args.Num() == 1 && Args[0] == TEXT("teleportvalidation") && PC && PC->GetPawn())
	{
		APawn* Pawn = PC->GetPawn();
		const FTransform Before = Pawn->GetActorTransform();
		const FVector Surface(100000.f, 100000.f, 100000.f);
		Pawn->SetActorLocation(Surface + FVector(0,0,100), false, nullptr, ETeleportType::TeleportPhysics);
		auto MakeBox = [&](const FVector& Location, const FVector& Extent, const FRotator& Rotation)
		{
			AActor* Actor = World->SpawnActor<AActor>();
			UBoxComponent* Box = NewObject<UBoxComponent>(Actor);
			Actor->SetRootComponent(Box);
			Box->SetBoxExtent(Extent);
			Box->SetCollisionProfileName(TEXT("BlockAll"));
			Box->RegisterComponent();
			Actor->SetActorLocationAndRotation(Location, Rotation);
			return Actor;
		};
		for (float Degrees : {0.f, 20.f, 40.f, 60.f})
		{
			const FRotator Rotation(Degrees,0,0);
			AActor* Floor = MakeBox(Surface - Rotation.RotateVector(FVector(0,0,25)), FVector(1000,1000,25), Rotation);
			FVector Destination;
			const bool bAllowed = FFableSpellRuntime::ResolveSafeTimeStepDestination(World,Pawn,Surface,Destination);
			UE_LOG(LogTemp,Display,TEXT("TELEPORT_VALIDATION slope=%.0f allowed=%d expected=%d"),Degrees,bAllowed,Degrees<45.f);
			if (Degrees == 0.f)
			{
				AActor* Ceiling = MakeBox(Surface+FVector(0,0,120),FVector(100,100,10),FRotator::ZeroRotator);
				UE_LOG(LogTemp,Display,TEXT("TELEPORT_VALIDATION blocked=%d expected=0"),FFableSpellRuntime::ResolveSafeTimeStepDestination(World,Pawn,Surface,Destination));
				Ceiling->Destroy();
				UE_LOG(LogTemp,Display,TEXT("TELEPORT_VALIDATION out_of_range=%d expected=0"),FFableSpellRuntime::ResolveSafeTimeStepDestination(World,Pawn,Surface+FVector(800,0,0),Destination));
			}
			Floor->Destroy();
		}
		FVector Destination;
		UE_LOG(LogTemp,Display,TEXT("TELEPORT_VALIDATION no_surface=%d expected=0"),FFableSpellRuntime::ResolveSafeTimeStepDestination(World,Pawn,Surface,Destination));
		Pawn->SetActorTransform(Before,false,nullptr,ETeleportType::TeleportPhysics);
		return;
	}
	if (Args.Num() == 1 && Args[0] == TEXT("failedload"))
	{
		if (auto* Fable = Cast<AFableForgePlayerController>(PC)) Fable->EnterGameFromCharacterSlot(FGuid::NewGuid(), 0, false);
		return;
	}
	if (Args.Num() > 0 && Args[0].StartsWith(TEXT("stack")))
	{
		auto* Saves = World && World->GetGameInstance() ? World->GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
		if (!Saves) return;
		if (Args[0] == TEXT("stackadd") && Args.Num() == 3)
		{
			UE_LOG(LogTemp,Display,TEXT("STACK_QA add item=%s requested=%s accepted=%d"),*Args[1],*Args[2],Saves->AddActiveInventoryItem(Args[1],FCString::Atoi(*Args[2])));
		}
		else if (Args[0] == TEXT("stackfixture"))
		{
			for (const auto& Entry : Saves->GetCharacters()) if (Entry.CharacterId == Saves->GetActiveCharacterId())
			{
				auto& Profile = const_cast<FFableCharacterProfile&>(Entry); Profile.HealthPercent = .25f; Profile.ManaPercent = .25f;
			}
			Saves->AddActiveInventoryItem(TEXT("health_potion"), 4);
			Saves->AddActiveInventoryItem(TEXT("mana_potion"), 3);
		}
		else if (Args[0] == TEXT("stacklegacy"))
		{
			TArray<FString> Bag, Equipment; Saves->TryGetActiveInventory(Bag,Equipment);
			for (FString& Item : Bag) Item.Reset();
			Bag[0]=TEXT("iron_sword"); Bag[1]=TEXT("iron_sword");
			Bag[2]=TEXT("health_potion"); Bag[3]=TEXT("health_potion");
			Bag[4]=TEXT("mana_potion"); Bag[5]=TEXT("mana_potion");
			Saves->SetActiveInventory(Bag,Equipment,TArray<int32>());
		}
		else if (Args[0] == TEXT("stackfull"))
		{
			TArray<FString> Bag, Equipment; TArray<int32> Counts;
			Saves->TryGetActiveInventory(Bag,Equipment); Saves->TryGetActiveInventoryQuantities(Counts);
			for (int32 I=0; I<Bag.Num(); ++I) if (Bag[I].IsEmpty()) { Bag[I]=TEXT("iron_sword"); Counts[I]=1; }
			Saves->SetActiveInventory(Bag,Equipment,Counts);
		}
		else if (Args[0] == TEXT("stackroundtrip"))
		{
			TArray<FString> Before, Equipment, After, LoadedEquipment; TArray<int32> Counts, LoadedCounts;
			Saves->TryGetActiveInventory(Before,Equipment); Saves->TryGetActiveInventoryQuantities(Counts);
			const FGuid Id = Saves->GetActiveCharacterId();
			const bool bSaved = Saves->SaveCharacterToSlot(Id,4,World->GetMapName());
			if (bSaved) Saves->AddActiveInventoryItem(TEXT("health_potion"),2);
			const bool bLoaded = bSaved && Saves->LoadCharacterFromSlot(Id,4) != nullptr;
			Saves->TryGetActiveInventory(After,LoadedEquipment); Saves->TryGetActiveInventoryQuantities(LoadedCounts);
			UE_LOG(LogTemp,Display,TEXT("STACK_QA roundtrip saved=%d loaded=%d exact=%d"),bSaved,bLoaded,Before==After && Counts==LoadedCounts && Equipment==LoadedEquipment);
		}
		return;
	}
	if (Args.Num() == 2 && Args[0] == TEXT("focuslook") && PC && PC->GetPawn())
	{
		AActor* Target = nullptr;
		for (TActorIterator<AActor> It(World); It; ++It)
			if ((Args[1] == TEXT("chest") && It->IsA<AFFChestInteractable>()) || (Args[1] == TEXT("door") && It->IsA<AFFDoorInteractable>())
				|| (Args[1] == TEXT("drop") && It->IsA<AFFItemInteractable>() && It->GetName().StartsWith(TEXT("FFItemInteractable_")))) { Target = *It; break; }
		if (!Target) { UE_LOG(LogTemp, Warning, TEXT("FOCUS_QA no target %s"), *Args[1]); return; }
		FVector Center, Extent; Target->GetActorBounds(true, Center, Extent);
		ACameraActor* Camera = World->SpawnActor<ACameraActor>();
		Camera->Tags.Add(TEXT("FocusQA"));
		FVector CameraLocation = Center + FVector(300.f, 0.f, 80.f);
		for (const FVector Offset : {FVector(300,0,80), FVector(-300,0,80), FVector(0,300,80), FVector(0,-300,80)})
		{
			FHitResult VisibleHit; FCollisionQueryParams Params; Params.AddIgnoredActor(PC->GetPawn());
			World->LineTraceSingleByChannel(VisibleHit, Center+Offset, Center, ECC_Visibility, Params);
			if (VisibleHit.GetActor() == Target) { CameraLocation = Center+Offset; break; }
		}
		Camera->SetActorLocation(CameraLocation); Camera->SetActorRotation((Center-CameraLocation).Rotation());
		PC->GetPawn()->SetActorLocation(IFFInteractable::Execute_GetInteractionLocation(Target) + FVector(0.f, 100.f, 100.f));
		PC->SetViewTarget(Camera);
		UE_LOG(LogTemp, Display, TEXT("FOCUS_QA target=%s center=%s"), *Target->GetName(), *Center.ToString());
		return;
	}
	if (Args.Num() == 1 && Args[0] == TEXT("focusfar") && PC && PC->GetPawn())
	{
		PC->GetPawn()->SetActorLocation(PC->GetPawn()->GetActorLocation() + FVector(5000.f, 0.f, 0.f)); return;
	}
	if (Args.Num() == 1 && Args[0] == TEXT("focusinspect") && PC)
	{
		int32 W,H; PC->GetViewportSize(W,H); FVector Origin, Direction;
		PC->DeprojectScreenPositionToWorld(W*.5f,H*.5f,Origin,Direction);
		FHitResult Hit; FCollisionQueryParams Params; Params.AddIgnoredActor(PC->GetPawn());
		World->LineTraceSingleByChannel(Hit,Origin,Origin+Direction*2500.f,ECC_Visibility,Params);
		UE_LOG(LogTemp, Display, TEXT("FOCUS_QA hit=%s"), *GetNameSafe(Hit.GetActor()));
		if (Hit.GetActor())
			for (UActorComponent* Component : Hit.GetActor()->GetComponents())
				if (auto* Mesh = Cast<UPrimitiveComponent>(Component)) UE_LOG(LogTemp, Display, TEXT("FOCUS_QA highlight=%d"), Mesh->bRenderCustomDepth);
		return;
	}
	if (Args.Num() == 3 && (Args[0] == TEXT("journalclick") || Args[0] == TEXT("journalpointer")) && PC)
	{
		for (TObjectIterator<UFableWheelAssignmentWidget> It; It; ++It)
		{
			if (It->GetWorld() != World || !It->IsOpen()) continue;
			const FGeometry Geometry = It->GetCachedGeometry();
			const FVector2D Point = Geometry.LocalToAbsolute(Geometry.GetLocalSize() * .5f + FVector2D(FCString::Atof(*Args[1]), FCString::Atof(*Args[2])));
			const TSet<FKey> Buttons{EKeys::LeftMouseButton};
			const FPointerEvent Pointer(0, Point, Point, Buttons, EKeys::LeftMouseButton, 0.f, FModifierKeysState());
			// Exercise the runtime pointer handler with the live widget geometry.
			const bool bHandled = (Args[0] == TEXT("journalclick") ? It->NativeOnMouseButtonDown(Geometry, Pointer) : It->NativeOnMouseMove(Geometry, Pointer)).IsEventHandled();
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
	if (Args.Num() == 2 && Args[0] == TEXT("stick") && PC)
	{
		// Physical controller convention at Slate: right-positive X, UP-positive Y.
		const FVector2D Stick = Args[1] == TEXT("up") ? FVector2D(0,1)
			: Args[1] == TEXT("down") ? FVector2D(0,-1)
			: Args[1] == TEXT("right") ? FVector2D(1,0)
			: Args[1] == TEXT("left") ? FVector2D(-1,0) : FVector2D::ZeroVector;
		FSlateApplication::Get().ProcessAnalogInputEvent(FAnalogInputEvent(EKeys::Gamepad_RightX, FModifierKeysState(), 0, false, 0, 0, Stick.X));
		FSlateApplication::Get().ProcessAnalogInputEvent(FAnalogInputEvent(EKeys::Gamepad_RightY, FModifierKeysState(), 0, false, 0, 0, Stick.Y));
		UE_LOG(LogTemp,Display,TEXT("PHYSICAL_STICK direction=%s x=%.2f y=%.2f"),*Args[1],Stick.X,Stick.Y);
		return;
	}
	if (Args.Num() == 2 && Args[0] == TEXT("gesturecapture") && PC)
	{
		const bool bCircle = Args[1] == TEXT("tornado");
		const FKey ElementKey = Args[1] == TEXT("water") ? EKeys::Gamepad_DPad_Left
			: Args[1] == TEXT("earth") ? EKeys::Gamepad_DPad_Down
			: Args[1] == TEXT("air") ? EKeys::Gamepad_DPad_Up : EKeys::Gamepad_DPad_Right;
		FSlateApplication::Get().ProcessKeyDownEvent(FKeyEvent(ElementKey, FModifierKeysState(), 0, false, 0, 0));
		FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([ElementKey,bCircle,Start=FPlatformTime::Seconds(),LastStep=-1,bShot=false](float) mutable
		{
			const double Elapsed = FPlatformTime::Seconds()-Start;
			const int32 Step = FMath::FloorToInt(Elapsed/.065);
			const int32 LastStrokeStep = bCircle ? 17 : 3;
			if (Step != LastStep)
			{
				LastStep = Step;
				FVector2D Stick = FVector2D::ZeroVector;
				if (Step >= 2 && Step <= LastStrokeStep)
				{
					const float Angle = bCircle ? (Step-2)*TWO_PI/15.f : 0.f;
					Stick = FVector2D(FMath::Cos(Angle), FMath::Sin(Angle));
				}
				FSlateApplication::Get().ProcessAnalogInputEvent(FAnalogInputEvent(EKeys::Gamepad_RightX,FModifierKeysState(),0,false,0,0,Stick.X));
				FSlateApplication::Get().ProcessAnalogInputEvent(FAnalogInputEvent(EKeys::Gamepad_RightY,FModifierKeysState(),0,false,0,0,Stick.Y));
			}
			if (!bShot && Elapsed > (LastStrokeStep+1)*.065+.15)
			{
				bShot = true;
				FScreenshotRequest::RequestScreenshot(TEXT("/tmp/FableForge-gesture-verified.png"),true,false);
			}
			if (Elapsed > (LastStrokeStep+1)*.065+.6)
			{
				FSlateApplication::Get().ProcessKeyUpEvent(FKeyEvent(ElementKey,FModifierKeysState(),0,false,0,0));
				return false;
			}
			return true;
		}),0.f);
		return;
	}
	if (Args.Num() == 1 && Args[0] == TEXT("quickwheel") && PC)
	{
		if (auto* Forge = Cast<AFableForgePlayerController>(PC)) Forge->OpenQuickWheelForQa();
		return;
	}
	if (Args.Num() == 2 && Args[0] == TEXT("skillrequest") && PC)
	{
		if (auto* Forge = Cast<AFableForgePlayerController>(PC))
			UE_LOG(LogTemp,Display,TEXT("SKILL_QA request=%s accepted=%d"), *Args[1], Forge->RequestSkillPayload(TEXT("skill:")+Args[1]));
		return;
	}
	if (Args.Num() == 1 && Args[0] == TEXT("consumablefixture"))
	{
		if (auto* Saves = World->GetGameInstance()->GetSubsystem<UFableSaveSubsystem>())
		{
			// Isolated QA profile only; seed depleted resources without exposing a shipping cheat API.
			for (const auto& Entry : Saves->GetCharacters())
				if (Entry.CharacterId == Saves->GetActiveCharacterId())
				{
					auto& Profile = const_cast<FFableCharacterProfile&>(Entry);
					Profile.HealthPercent=.5f; Profile.ManaPercent=.5f;
					TArray<FString> Bag=Profile.InventorySlots,Equipment=Profile.EquippedItems;
					Bag[2]=TEXT("health_potion"); Bag[3]=TEXT("berries"); Bag[4]=TEXT("mana_potion");
					Saves->SetActiveInventory(Bag,Equipment); break;
				}
		}
		return;
	}
	if (Args.Num() == 1 && Args[0] == TEXT("wheelgeometry"))
	{
		for (TObjectIterator<UFableTimeWheelWidget> It; It; ++It)
			if (It->GetWorld()==World && It->IsOpen() && It->WidgetTree)
				It->WidgetTree->ForEachWidget([](UWidget* Widget)
				{
					if (auto* Text = Cast<UTextBlock>(Widget))
						UE_LOG(LogTemp,Display,TEXT("WHEEL_GEOMETRY text=%s pos=%s size=%s"),*Text->GetText().ToString().Replace(TEXT("\n"),TEXT(" ")),
							*Text->GetCachedGeometry().GetAbsolutePosition().ToString(),*Text->GetCachedGeometry().GetLocalSize().ToString());
				});
		return;
	}
	if (Args.Num() == 1 && Args[0] == TEXT("journalstate") && PC)
	{
		int32 VisualCount = 0;
		for (TActorIterator<AFableSpellVisualActor> It(World); It; ++It) ++VisualCount;
		UE_LOG(LogTemp,Display,TEXT("SPELL_VISUAL_COUNT active=%d"),VisualCount);
		if (ACharacter* Character = Cast<ACharacter>(PC->GetPawn()))
			UE_LOG(LogTemp,Display,TEXT("JUMP_STATE pressed=%d count=%d z=%.3f vz=%.3f"),
				Character->bPressedJump, Character->JumpCurrentCount, Character->GetActorLocation().Z, Character->GetVelocity().Z);
		TArray<FString> Bag, Equipment;
		TArray<FFableQuickWheelPageData> Pages;
		if (auto* Saves = World->GetGameInstance()->GetSubsystem<UFableSaveSubsystem>())
		{
			Saves->TryGetActiveInventory(Bag, Equipment);
			TArray<int32> Counts; Saves->TryGetActiveInventoryQuantities(Counts);
			TArray<FString> CountStrings; for (int32 Count : Counts) CountStrings.Add(FString::FromInt(Count));
			UE_LOG(LogTemp,Display,TEXT("STACK_QA counts=%s"),*FString::Join(CountStrings,TEXT("|")));
			Saves->TryGetActiveQuickWheelPages(Pages);
			FFableCharacterProfile Profile; Saves->TryGetActiveCharacterProfile(Profile);
			UE_LOG(LogTemp,Display,TEXT("COSMIC_LOADOUT L3=%s"), *Saves->GetActiveCosmicSkillId());
			UE_LOG(LogTemp,Display,TEXT("JOURNAL_RESOURCES health=%.2f mana=%.2f"),Profile.HealthPercent,Profile.ManaPercent);
			if (auto* Forge = Cast<AFableForgePlayerController>(PC))
			{
				UE_LOG(LogTemp,Display,TEXT("COSMIC_QA energy=%.2f max=%.2f"),Forge->GetCosmicEnergy(),Forge->GetMaxCosmicEnergy());
				UE_LOG(LogTemp,Display,TEXT("STICK_STATE x=%.3f y=%.3f location=%s"),PC->GetInputAnalogKeyState(EKeys::Gamepad_RightX),PC->GetInputAnalogKeyState(EKeys::Gamepad_RightY),*PC->GetPawn()->GetActorLocation().ToString());
				UE_LOG(LogTemp,Display,TEXT("FACING_STATE pawn=%s camera=%s velocity=%s leftX=%.2f leftY=%.2f"),
					*PC->GetPawn()->GetActorRotation().ToString(), *PC->GetControlRotation().ToString(), *PC->GetPawn()->GetVelocity().ToString(),
					PC->GetInputAnalogKeyState(EKeys::Gamepad_LeftX), PC->GetInputAnalogKeyState(EKeys::Gamepad_LeftY));
				UE_LOG(LogTemp,Display,TEXT("TARGET_STATE paused=%d targeting=%d cursor=%s worldtime=%.4f pawn=%s camera=%s"), World->IsPaused(), Forge->IsTargetingForQa(), *Forge->GetTargetCursorForQa().ToString(), World->GetTimeSeconds(), *GetNameSafe(PC->GetPawn()), *PC->GetControlRotation().ToString());
			}
			UE_LOG(LogTemp, Display, TEXT("JOURNAL_STATE bag=%s equipment=%s time=%.2f move_blocked=%d look_blocked=%d"),
				*FString::Join(Bag, TEXT("|")), *FString::Join(Equipment, TEXT("|")), World->GetWorldSettings()->TimeDilation, PC->IsMoveInputIgnored(), PC->IsLookInputIgnored());
			for (int32 I = 0; I < Pages.Num(); ++I)
			{
				TArray<FString> Payloads;
				for (const auto& Slot : Pages[I].Slots) Payloads.Add(Slot.EntryId);
				UE_LOG(LogTemp, Display, TEXT("JOURNAL_WHEEL page=%d slots=%s"), I, *FString::Join(Payloads, TEXT("|")));
			}
		}
		for (TObjectIterator<UFableTimeWheelWidget> It; It; ++It)
			if (It->GetWorld() == World && It->IsOpen()) UE_LOG(LogTemp, Display, TEXT("JOURNAL_SELECTED socket=%d"), It->GetSelectedSlot());
		return;
	}
	if (Args.Num() == 2 && (Args[0] == TEXT("journalkey") || Args[0] == TEXT("journalkeydown") || Args[0] == TEXT("journalkeyup")) && PC)
	{
		const FKey Key(*Args[1]);
		const FKeyEvent Event(Key, FModifierKeysState(), 0, false, 0, 0);
		const bool bHandled = Args[0] != TEXT("journalkeyup") && FSlateApplication::Get().ProcessKeyDownEvent(Event);
		if (Args[0] != TEXT("journalkeydown")) FSlateApplication::Get().ProcessKeyUpEvent(Event);
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
