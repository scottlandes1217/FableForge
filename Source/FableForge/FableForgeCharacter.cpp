// Copyright Epic Games, Inc. All Rights Reserved.

#include "FableForgeCharacter.h"
#include "RPG/Animation/FableWeaponPoseMeshComponent.h"
#include "Engine/LocalPlayer.h"
#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/SpringArmComponent.h"
#include "GameFramework/Controller.h"
#include "GameFramework/PlayerController.h"
#include "EnhancedInputComponent.h"
#include "EnhancedInputSubsystems.h"
#include "InputCoreTypes.h"
#include "InputActionValue.h"
#include "FableForgePlayerController.h"
#include "FableForge.h"
#include "Components/StaticMeshComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Engine/StaticMesh.h"
#include "Engine/DataTable.h"
#include "Engine/GameInstance.h"
#include "Animation/Skeleton.h"
#include "RPG/Data/FableItemDefinitionTableRow.h"
#include "RPG/Save/FableSaveSubsystem.h"
#include "RPG/UI/FableAppearanceAssets.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#endif

namespace
{
	const TCHAR* WeaponsDataTablePath = TEXT("/Game/Data/DT_Weapons.DT_Weapons");
	const TCHAR* ArmorDataTablePath = TEXT("/Game/Data/DT_Armor.DT_Armor");

	bool CanUseLeaderPoseForModularArmor(const USkeletalMesh* CharacterMesh, const USkeletalMesh* ArmorMesh)
	{
		if (CharacterMesh == nullptr || ArmorMesh == nullptr)
		{
			return false;
		}

		const FReferenceSkeleton& CharacterRef = CharacterMesh->GetRefSkeleton();
		const FReferenceSkeleton& ArmorRef = ArmorMesh->GetRefSkeleton();
		if (CharacterRef.GetNum() == 0 || ArmorRef.GetNum() == 0)
		{
			return false;
		}

		// Leader pose works when armor bones are a compatible subset of the character hierarchy.
		for (int32 ArmorBoneIndex = 0; ArmorBoneIndex < ArmorRef.GetNum(); ++ArmorBoneIndex)
		{
			const FName ArmorBoneName = ArmorRef.GetBoneName(ArmorBoneIndex);
			const int32 CharacterBoneIndex = CharacterRef.FindBoneIndex(ArmorBoneName);
			if (CharacterBoneIndex == INDEX_NONE)
			{
				return false;
			}

			const int32 ArmorParentIndex = ArmorRef.GetParentIndex(ArmorBoneIndex);
			if (ArmorParentIndex == INDEX_NONE)
			{
				continue;
			}

			const int32 CharacterParentIndex = CharacterRef.GetParentIndex(CharacterBoneIndex);
			if (CharacterParentIndex == INDEX_NONE)
			{
				return false;
			}

			const FName ArmorParentName = ArmorRef.GetBoneName(ArmorParentIndex);
			const FName CharacterParentName = CharacterRef.GetBoneName(CharacterParentIndex);
			if (ArmorParentName != CharacterParentName)
			{
				return false;
			}
		}

		return true;
	}
}

AFableForgeCharacter::AFableForgeCharacter(const FObjectInitializer& ObjectInitializer)
 : Super(ObjectInitializer.SetDefaultSubobjectClass<UFableWeaponPoseMeshComponent>(ACharacter::MeshComponentName))
{
	PrimaryActorTick.bCanEverTick = true;
	EquipmentVisualComponents.SetNum(UFableSaveSubsystem::EquipmentSlotsPerCharacter);

	// Set size for collision capsule
	GetCapsuleComponent()->InitCapsuleSize(42.f, 96.0f);
		
	// Don't rotate when the controller rotates. Let that just affect the camera.
	bUseControllerRotationPitch = false;
	bUseControllerRotationYaw = false;
	bUseControllerRotationRoll = false;

	// Configure character movement
	GetCharacterMovement()->bOrientRotationToMovement = true;
	GetCharacterMovement()->RotationRate = FRotator(0.0f, 500.0f, 0.0f);

	// Note: For faster iteration times these variables, and many more, can be tweaked in the Character Blueprint
	// instead of recompiling to adjust them
	GetCharacterMovement()->JumpZVelocity = 500.f;
	GetCharacterMovement()->AirControl = 0.35f;
	GetCharacterMovement()->MaxWalkSpeed = 500.f;
	// Keeps animation state machines that rely on acceleration working during click-to-move path following.
	if (FNavMovementProperties* NavMovementProperties = GetCharacterMovement()->GetNavMovementProperties())
	{
		NavMovementProperties->bUseAccelerationForPaths = true;
	}
	GetCharacterMovement()->MinAnalogWalkSpeed = 20.f;
	GetCharacterMovement()->BrakingDecelerationWalking = 2000.f;
	GetCharacterMovement()->BrakingDecelerationFalling = 1500.0f;

	// Create a camera boom (pulls in towards the player if there is a collision)
	CameraBoom = CreateDefaultSubobject<USpringArmComponent>(TEXT("CameraBoom"));
	CameraBoom->SetupAttachment(RootComponent);
	CameraBoom->TargetArmLength = IdleCameraArmLength;
	CameraBoom->SocketOffset = IdleCameraSocketOffset;
	CameraBoom->bUsePawnControlRotation = true;
	CameraBoom->bEnableCameraLag = true;
	CameraBoom->bEnableCameraRotationLag = false;
	CameraBoom->CameraLagSpeed = 10.0f;
	CameraBoom->bUseCameraLagSubstepping = true;
	CameraBoom->CameraLagMaxDistance = 60.0f;
	CameraBoom->CameraRotationLagSpeed = 0.0f;

	// Create a follow camera
	FollowCamera = CreateDefaultSubobject<UCameraComponent>(TEXT("FollowCamera"));
	FollowCamera->SetupAttachment(CameraBoom, USpringArmComponent::SocketName);
	FollowCamera->bUsePawnControlRotation = false;
	FollowCamera->SetRelativeRotation(FRotator(CameraPitchOffsetDegrees, 0.0f, 0.0f));

	// Note: The skeletal mesh and anim blueprint references on the Mesh component (inherited from Character) 
	// are set in the derived blueprint asset named ThirdPersonCharacter (to avoid direct content references in C++)
}

void AFableForgeCharacter::BeginPlay()
{
	Super::BeginPlay();

	if (CameraBoom != nullptr)
	{
		CameraBoom->TargetArmLength = IdleCameraArmLength;
		CameraBoom->SocketOffset = IdleCameraSocketOffset;
	}

	if (FollowCamera != nullptr)
	{
		// Keep the character camera active even when the pawn is spawned before possession.
		// The player controller will still be free to replace the view target explicitly.
		FollowCamera->Activate(true);
		FollowCamera->SetRelativeRotation(FRotator(CameraPitchOffsetDegrees, 0.0f, 0.0f));
	}

	if (UGameInstance* GameInstance = GetGameInstance())
	{
		if (UFableSaveSubsystem* SaveSubsystem = GameInstance->GetSubsystem<UFableSaveSubsystem>())
		{
			SaveSubsystem->OnActiveInventoryChanged().RemoveAll(this);
			SaveSubsystem->OnActiveInventoryChanged().AddUObject(this, &AFableForgeCharacter::HandleActiveInventoryChanged);
		}
	}

	RefreshEquipmentVisualsFromSave();
}

void AFableForgeCharacter::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	if (UGameInstance* GameInstance = GetGameInstance())
	{
		if (UFableSaveSubsystem* SaveSubsystem = GameInstance->GetSubsystem<UFableSaveSubsystem>())
		{
			SaveSubsystem->OnActiveInventoryChanged().RemoveAll(this);
		}
	}

	for (int32 SlotIndex = 0; SlotIndex < EquipmentVisualComponents.Num(); ++SlotIndex)
	{
		ClearEquipmentVisual(SlotIndex);
	}

	Super::EndPlay(EndPlayReason);
}

void AFableForgeCharacter::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);

	UpdateShoulderCamera(DeltaSeconds);
}

void AFableForgeCharacter::SetupPlayerInputComponent(UInputComponent* PlayerInputComponent)
{
	// Set up action bindings
	if (UEnhancedInputComponent* EnhancedInputComponent = Cast<UEnhancedInputComponent>(PlayerInputComponent)) {
		
		// Jumping
		EnhancedInputComponent->BindAction(JumpAction, ETriggerEvent::Started, this, &ACharacter::Jump);
		EnhancedInputComponent->BindAction(JumpAction, ETriggerEvent::Completed, this, &ACharacter::StopJumping);

		// Moving
		EnhancedInputComponent->BindAction(MoveAction, ETriggerEvent::Triggered, this, &AFableForgeCharacter::Move);
		EnhancedInputComponent->BindAction(MouseLookAction, ETriggerEvent::Triggered, this, &AFableForgeCharacter::MouseLook);

		// Looking
		EnhancedInputComponent->BindAction(LookAction, ETriggerEvent::Triggered, this, &AFableForgeCharacter::Look);
	}
	else
	{
		UE_LOG(LogFableForge, Error, TEXT("'%s' Failed to find an Enhanced Input component! This template is built to use the Enhanced Input system. If you intend to use the legacy system, then you will need to update this C++ file."), *GetNameSafe(this));
	}
}

void AFableForgeCharacter::Move(const FInputActionValue& Value)
{
	if (const AFableForgePlayerController* ForgePlayerController = Cast<AFableForgePlayerController>(GetController()))
		if (ForgePlayerController->IsWheelInputCaptured()) return;

	// input is a Vector2D
	FVector2D MovementVector = Value.Get<FVector2D>();

	// Forward/back movement input should interrupt click-to-move interaction paths.
	if (FMath::Abs(MovementVector.Y) > KINDA_SMALL_NUMBER)
	{
		if (AFableForgePlayerController* ForgePlayerController = Cast<AFableForgePlayerController>(GetController()))
		{
			ForgePlayerController->NotifyManualMoveInput();
		}
	}

	if (MovementVector.SizeSquared() > FMath::Square(MovementFollowThreshold))
	{
		if (UWorld* World = GetWorld())
		{
			LastMoveInputTime = World->GetTimeSeconds();
		}
	}

	// route the input
	DoMove(MovementVector.X, MovementVector.Y);
}

void AFableForgeCharacter::Look(const FInputActionValue& Value)
{
	// input is a Vector2D
	FVector2D LookAxisVector = Value.Get<FVector2D>();
	if (AFableForgePlayerController* ForgePlayerController = Cast<AFableForgePlayerController>(GetController()))
	{
		if (ForgePlayerController->IsWheelInputCaptured())
		{
			ForgePlayerController->RouteRightStickToWheel(LookAxisVector);
			return;
		}
	}

	if (LookAxisVector.SizeSquared() > KINDA_SMALL_NUMBER)
	{
		if (UWorld* World = GetWorld())
		{
			LastManualLookTime = World->GetTimeSeconds();
		}
	}

	// route the input
	DoLook(LookAxisVector.X, LookAxisVector.Y);
}

void AFableForgeCharacter::MouseLook(const FInputActionValue& Value)
{
	if (!bRequireMouseButtonForMouseLook)
	{
		Look(Value);
		return;
	}

	const APlayerController* PlayerController = Cast<APlayerController>(GetController());
	if (PlayerController == nullptr)
	{
		return;
	}

	const bool bLeftMouseHeld = bUseLeftMouseButtonForLook && PlayerController->IsInputKeyDown(EKeys::LeftMouseButton);
	const bool bRightMouseHeld = bUseRightMouseButtonForLook && PlayerController->IsInputKeyDown(EKeys::RightMouseButton);

	if (!bLeftMouseHeld && !bRightMouseHeld)
	{
		return;
	}

	Look(Value);
}

void AFableForgeCharacter::UpdateShoulderCamera(float DeltaSeconds)
{
	// Controller ownership can briefly report false while a saved character is being
	// possessed. The camera still belongs to this pawn, so only require the controller
	// and boom that are needed for the follow/recenter calculation.
	if (CameraBoom == nullptr || Controller == nullptr)
	{
		return;
	}

	// Do not recenter the camera behind the character while moving. That feedback
	// loop fights camera-relative stick movement and can spin the player after a jump.
	const bool bShouldFollow = false;
	float TargetArmLength = bFirstPersonView ? FirstPersonCameraArmLength : IdleCameraArmLength;
	if (bAdjustArmLengthWithMovement)
	{
		TargetArmLength = bShouldFollow ? MovingCameraArmLength : IdleCameraArmLength;
	}
	FVector TargetSocketOffset = bFirstPersonView ? FirstPersonCameraSocketOffset : IdleCameraSocketOffset;
	if (bAdjustSocketOffsetWithMovement)
	{
		TargetSocketOffset = bShouldFollow ? MovingCameraSocketOffset : IdleCameraSocketOffset;
	}

	CameraBoom->TargetArmLength = FMath::FInterpTo(CameraBoom->TargetArmLength, TargetArmLength, DeltaSeconds, CameraFollowInterpSpeed);
	CameraBoom->SocketOffset = FMath::VInterpTo(CameraBoom->SocketOffset, TargetSocketOffset, DeltaSeconds, CameraOffsetInterpSpeed);

	if (bShouldFollow && !bWasAutoFollowActive)
	{
		const FRotator CurrentControlRotation = Controller->GetControlRotation();
		const float YawDeltaDegrees = FMath::Abs(FMath::FindDeltaAngleDegrees(CurrentControlRotation.Yaw, GetActorRotation().Yaw));
		bCameraRecentering = YawDeltaDegrees > CameraRecenterMinYawDelta;
	}
	else if (!bShouldFollow)
	{
		bCameraRecentering = false;
	}

	if (bShouldFollow)
	{
		const FRotator CurrentControlRotation = Controller->GetControlRotation();
		FRotator TargetControlRotation = CurrentControlRotation;
		TargetControlRotation.Yaw = GetActorRotation().Yaw;
		TargetControlRotation.Roll = 0.0f;

		if (bCameraRecentering)
		{
			const FRotator RecenteredRotation = FMath::RInterpTo(CurrentControlRotation, TargetControlRotation, DeltaSeconds, CameraYawFollowInterpSpeed);
			Controller->SetControlRotation(RecenteredRotation);

			const float YawDeltaDegrees = FMath::Abs(FMath::FindDeltaAngleDegrees(RecenteredRotation.Yaw, TargetControlRotation.Yaw));
			if (YawDeltaDegrees <= 1.5f)
			{
				bCameraRecentering = false;
			}
		}
		else
		{
			Controller->SetControlRotation(TargetControlRotation);
		}
	}

	bWasAutoFollowActive = bShouldFollow;
}

void AFableForgeCharacter::ToggleFirstPersonView()
{
	bFirstPersonView = !bFirstPersonView;
	UE_LOG(LogFableForge, Log, TEXT("Camera view changed: %s"), bFirstPersonView ? TEXT("First Person") : TEXT("Shoulder"));
}

bool AFableForgeCharacter::IsMovementActive() const
{
	const UWorld* World = GetWorld();
	if (World == nullptr)
	{
		return false;
	}

	const bool bRecentlyMoved = (World->GetTimeSeconds() - LastMoveInputTime) <= 0.15f;
	const float HorizontalSpeed = GetVelocity().Size2D();

	return bRecentlyMoved || HorizontalSpeed > VelocityFollowThreshold;
}

bool AFableForgeCharacter::IsManualLookActive() const
{
	const UWorld* World = GetWorld();
	if (World == nullptr)
	{
		return false;
	}

	return (World->GetTimeSeconds() - LastManualLookTime) <= CameraAutoFollowDelay;
}

void AFableForgeCharacter::DoMove(float Right, float Forward)
{
	if (GetController() != nullptr)
	{
		// Standard third-person controller movement: both axes are relative to the
		// camera yaw, while the right stick remains dedicated to camera look.
		const FRotator YawRotation(0.0f, GetController()->GetControlRotation().Yaw, 0.0f);
		const FVector ForwardDirection = FRotationMatrix(YawRotation).GetUnitAxis(EAxis::X);
		const FVector RightDirection = FRotationMatrix(YawRotation).GetUnitAxis(EAxis::Y);
		AddMovementInput(ForwardDirection, Forward);
		AddMovementInput(RightDirection, Right);
	}
}

void AFableForgeCharacter::DoLook(float Yaw, float Pitch)
{
	if (GetController() != nullptr)
	{
		// add yaw and pitch input to controller
		AddControllerYawInput(Yaw);
		AddControllerPitchInput(Pitch);
	}
}

void AFableForgeCharacter::DoJumpStart()
{
	// signal the character to jump
	Jump();
}

void AFableForgeCharacter::DoJumpEnd()
{
	// signal the character to stop jumping
	StopJumping();
}

void AFableForgeCharacter::RefreshEquipmentVisualsFromSave()
{
	// An explicit refresh also supports runtime character mesh or asset changes.
	bEquipmentVisualsInitialized = false;
	if (UGameInstance* GameInstance = GetGameInstance())
	{
		if (UFableSaveSubsystem* SaveSubsystem = GameInstance->GetSubsystem<UFableSaveSubsystem>())
		{
			FFableCharacterProfile Profile;
			if (SaveSubsystem->TryGetActiveCharacterProfile(Profile))
			{
				ApplyAppearanceFromProfile(Profile);
				return;
			}
		}
	}

	ApplyEquipmentVisuals(TArray<FString>());
}

void AFableForgeCharacter::ApplyAppearanceFromProfile(const FFableCharacterProfile& Profile)
{
	bAppearanceFemale = Profile.Gender == EFableGender::Female;
	const TCHAR* BodyPath = bAppearanceFemale ? TEXT("/Game/Characters/PlayableCharacter/Meshes/femalecharacter_v2.femalecharacter_v2") : TEXT("/Game/Characters/PlayableCharacter/Meshes/basecharacter_v2.basecharacter_v2");
	if (USkeletalMesh* Body = LoadObject<USkeletalMesh>(nullptr, BodyPath))
	{
		if (GetMesh() && GetMesh()->GetSkeletalMeshAsset() != Body)
		{
			GetMesh()->SetSkeletalMesh(Body);
			// Discard blueprint material overrides so the authored v2 skin materials are used.
			GetMesh()->EmptyOverrideMaterials();
		}
	}
	AppliedBodyMorphs = Profile.BodyMorphs;
	if (bAppearanceFemale) { AppliedBodyMorphs.Remove(TEXT("FemaleBody")); }
	if (!bAppearanceFemale && !AppliedBodyMorphs.Contains(TEXT("FemaleBody")))
	{
		AppliedBodyMorphs.Add(TEXT("FemaleBody"), Profile.Gender == EFableGender::Female ? 1.f : 0.f);
	}
	if (GetMesh())
	{
		const FName Parameters[] = { TEXT("HairTint"),TEXT("EyeTint"),TEXT("SkinTint") };
		const FLinearColor Colors[] = { Profile.HairColor,Profile.EyeColor,Profile.SkinColor };
		for (int32 Index=0; Index<3; ++Index)
		{
			if (UMaterialInstanceDynamic* Material=GetMesh()->CreateAndSetMaterialInstanceDynamic(Index))
			{
				Material->SetVectorParameterValue(Parameters[Index],Colors[Index]);
			}
		}
	}
	if (!AppearanceHair)
	{
		AppearanceHair=NewObject<UStaticMeshComponent>(this,TEXT("AppearanceHair"));
		AppearanceHair->RegisterComponent();
	}
	if (!AppearanceBeard)
	{
		AppearanceBeard=NewObject<UStaticMeshComponent>(this,TEXT("AppearanceBeard"));
		AppearanceBeard->RegisterComponent();
	}
	FableAppearanceAssets::ConfigureStyle(AppearanceHair,GetMesh(),Profile.HairStyle,false,Profile.HairColor,Profile.BodyMorphs.FindRef(TEXT("HeadSize")));
	FableAppearanceAssets::ConfigureStyle(AppearanceBeard,GetMesh(),Profile.BeardStyle,true,Profile.HairColor,Profile.BodyMorphs.FindRef(TEXT("HeadSize")));
	const float Height = FMath::IsFinite(Profile.HeightScale) ? FMath::Clamp(Profile.HeightScale, 0.7f, 1.2f) : 1.0f;
	SetActorScale3D(FVector(Height));
	ApplyEquipmentVisuals(Profile.EquippedItems);
}

void AFableForgeCharacter::ApplyAppearanceMorphs()
{
	auto ApplyToMesh = [this](USkeletalMeshComponent* Component)
	{
		if (!Component) { return; }
		Component->ClearMorphTargets();
		for (const TPair<FName, float>& Morph : AppliedBodyMorphs)
		{
			const bool PositiveOnly = Morph.Key == TEXT("FemaleBody") || Morph.Key == TEXT("BodyFat") || Morph.Key == TEXT("Muscle") || Morph.Key == TEXT("Bust");
			const float Weight = FMath::IsFinite(Morph.Value) ? FMath::Clamp(Morph.Value, PositiveOnly ? 0.f : -1.f, 1.f) : 0.f;
			Component->SetMorphTarget(Morph.Key, Weight);
		}
	};
	ApplyToMesh(GetMesh());
	for (USceneComponent* Component : EquipmentVisualComponents)
	{
		if (USkeletalMeshComponent* Armor = Cast<USkeletalMeshComponent>(Component))
		{
			if (Armor->GetAttachSocketName().IsNone()) { ApplyToMesh(Armor); }
		}
	}
}

void AFableForgeCharacter::HandleActiveInventoryChanged(const TArray<FString>& InInventorySlots, const TArray<FString>& InEquippedSlots)
{
	(void)InInventorySlots;
	ApplyEquipmentVisuals(InEquippedSlots);
}

void AFableForgeCharacter::ApplyEquipmentVisuals(const TArray<FString>& InEquippedSlots)
{
 if(UFableWeaponPoseMeshComponent* WeaponMesh=Cast<UFableWeaponPoseMeshComponent>(GetMesh()))
  WeaponMesh->SetSwordEquipped(InEquippedSlots.IsValidIndex(0) && InEquippedSlots[0]==TEXT("iron_sword"));
	const int32 SlotCount = UFableSaveSubsystem::EquipmentSlotsPerCharacter;
	if (EquipmentVisualComponents.Num() != SlotCount)
	{
		EquipmentVisualComponents.SetNum(SlotCount);
	}

	const USkeletalMesh* CharacterMesh = GetMesh() ? GetMesh()->GetSkeletalMeshAsset() : nullptr;
	const bool bRebuildAll = !bEquipmentVisualsInitialized || AppliedCharacterMesh.Get() != CharacterMesh;
	AppliedEquipmentItemIds.SetNum(SlotCount);
	bool bEquipmentChanged = bRebuildAll;
	for (int32 SlotIndex = 0; SlotIndex < SlotCount; ++SlotIndex)
	{
		const FString ItemId = InEquippedSlots.IsValidIndex(SlotIndex) ? InEquippedSlots[SlotIndex] : FString();
		if (!bRebuildAll && AppliedEquipmentItemIds[SlotIndex] == ItemId)
		{
			continue;
		}

		ClearEquipmentVisual(SlotIndex);
		if (!ItemId.IsEmpty())
		{
			CreateEquipmentVisualForSlot(SlotIndex, ItemId);
		}
		AppliedEquipmentItemIds[SlotIndex] = ItemId;
		bEquipmentChanged = true;
	}

	AppliedCharacterMesh = GetMesh() ? GetMesh()->GetSkeletalMeshAsset() : nullptr;
	bEquipmentVisualsInitialized = true;
	ApplyAppearanceMorphs();
	if (bEquipmentChanged)
	{
		UpdateBodyMaterialVisibility(InEquippedSlots);
	}
}

void AFableForgeCharacter::ClearEquipmentVisual(int32 SlotIndex)
{
	if (!EquipmentVisualComponents.IsValidIndex(SlotIndex))
	{
		return;
	}

	if (USceneComponent* ExistingComponent = EquipmentVisualComponents[SlotIndex].Get())
	{
		ExistingComponent->DestroyComponent();
		EquipmentVisualComponents[SlotIndex] = nullptr;
	}
}

void AFableForgeCharacter::SetBodyMaterialSlotsVisible(const TArray<int32>& MaterialSlots, bool bVisible)
{
	if (GetMesh() == nullptr || GetMesh()->GetSkinnedAsset() == nullptr)
	{
		return;
	}

	const int32 MaterialCount = GetMesh()->GetSkinnedAsset()->GetMaterials().Num();
	const int32 LODCount = FMath::Max(1, GetMesh()->GetSkinnedAsset()->GetLODNum());
	for (const int32 MaterialSlot : MaterialSlots)
	{
		if (MaterialSlot < 0 || MaterialSlot >= MaterialCount)
		{
			continue;
		}

		for (int32 LODIndex = 0; LODIndex < LODCount; ++LODIndex)
		{
			// These settings are material IDs, not section IDs; bypass LOD section remapping.
			GetMesh()->ShowMaterialSection(MaterialSlot, INDEX_NONE, bVisible, LODIndex);
		}
	}
}

void AFableForgeCharacter::UpdateBodyMaterialVisibility(const TArray<FString>& InEquippedSlots)
{
	if (!bHideBodyMaterialsUnderModularArmor || GetMesh() == nullptr || GetMesh()->GetSkinnedAsset() == nullptr)
	{
		return;
	}

	const int32 LODCount = FMath::Max(1, GetMesh()->GetSkinnedAsset()->GetLODNum());
	for (int32 LODIndex = 0; LODIndex < LODCount; ++LODIndex)
	{
		GetMesh()->ShowAllMaterialSections(LODIndex);
	}

	auto IsModularArmorComponentActive = [&](const int32 SlotIndex) -> bool
	{
		if (!InEquippedSlots.IsValidIndex(SlotIndex) || InEquippedSlots[SlotIndex].IsEmpty())
		{
			return false;
		}

		if (!EquipmentVisualComponents.IsValidIndex(SlotIndex))
		{
			return false;
		}

		const USkeletalMeshComponent* SlotComponent = Cast<USkeletalMeshComponent>(EquipmentVisualComponents[SlotIndex].Get());
		return SlotComponent != nullptr && SlotComponent->GetAttachSocketName().IsNone();
	};

	const bool bHideChest = IsModularArmorComponentActive(3);
	const bool bHideHands = IsModularArmorComponentActive(4);
	const bool bHideLegs = IsModularArmorComponentActive(5);
	const bool bHideFeet = IsModularArmorComponentActive(6);

	if (bHideChest)
	{
		SetBodyMaterialSlotsVisible(ChestArmorHiddenBodyMaterialSlots, false);
	}
	if (bHideHands)
	{
		SetBodyMaterialSlotsVisible(HandsArmorHiddenBodyMaterialSlots, false);
	}
	if (bHideLegs)
	{
		SetBodyMaterialSlotsVisible(LegsArmorHiddenBodyMaterialSlots, false);
	}
	if (bHideFeet)
	{
		SetBodyMaterialSlotsVisible(FeetArmorHiddenBodyMaterialSlots, false);
	}

	const bool bAnyBodyArmorActive = bHideChest || bHideHands || bHideLegs || bHideFeet;
	const bool bHasBodyMaskConfig =
		ChestArmorHiddenBodyMaterialSlots.Num() > 0 ||
		HandsArmorHiddenBodyMaterialSlots.Num() > 0 ||
		LegsArmorHiddenBodyMaterialSlots.Num() > 0 ||
		FeetArmorHiddenBodyMaterialSlots.Num() > 0;
	if (bAnyBodyArmorActive && !bHasBodyMaskConfig)
	{
		UE_LOG(
			LogFableForge,
			Warning,
			TEXT("Modular armor is active but no body mask material slots are configured on '%s'. Set Chest/Hands/Legs/Feet hidden material slots in the character defaults to prevent clipping."),
			*GetName());
	}
}

void AFableForgeCharacter::CreateEquipmentVisualForSlot(int32 SlotIndex, const FString& ItemId)
{
	if (GetMesh() == nullptr)
	{
		return;
	}

	FString AssetPath;
	if (!ResolveEquipmentMeshPath(ItemId, SlotIndex, AssetPath))
	{
		return;
	}

	if (bAppearanceFemale && ItemId == TEXT("peasant_chest"))
	{
		AssetPath = TEXT("/Game/Items/Armor/FittedTunic/female_tunic_v2.female_tunic_v2");
	}

	if (bAppearanceFemale && (ItemId == TEXT("peasant_legs") || ItemId == TEXT("peasant_feet")))
	{
		const FString FemaleAsset = TEXT("female_") + ItemId + TEXT("_v2");
		AssetPath = TEXT("/Game/Items/Armor/FittedLowerArmor/") + FemaleAsset + TEXT(".") + FemaleAsset;
	}

	const FName AttachSocket = GetEquipmentAttachSocket(SlotIndex);
	FTransform RelativeTransform = GetEquipmentSlotRelativeTransform(SlotIndex, ItemId);
	const bool bUsingHandGripSocket = (AttachSocket == TEXT("HandGrip_R")) || (AttachSocket == TEXT("HandGrip_L"));

	if (SlotIndex == 0 || SlotIndex == 1)
	{
		UE_LOG(
			LogFableForge,
			Warning,
			TEXT("EquipmentVisual slot=%d item='%s' charSocket='%s' initialRelLoc=(%.2f,%.2f,%.2f)"),
			SlotIndex,
			*ItemId,
			*AttachSocket.ToString(),
			RelativeTransform.GetLocation().X,
			RelativeTransform.GetLocation().Y,
			RelativeTransform.GetLocation().Z);
	}

	// If a dedicated grip socket exists on the character, let that socket drive placement.
	// The older hand offsets are primarily for fallback bone attachments (hand_r/hand_l).
	if ((SlotIndex == 0 || SlotIndex == 1) && bUsingHandGripSocket && !ItemId.Contains(TEXT("staff"), ESearchCase::IgnoreCase))
	{
		RelativeTransform = FTransform::Identity;
	}

	auto TryApplyWeaponGripSocketAlignment = [&](USceneComponent* VisualComponent, FTransform& InOutRelativeTransform) -> bool
	{
		if (VisualComponent == nullptr || (SlotIndex != 0 && SlotIndex != 1))
		{
			return false;
		}

		const TArray<FName> CandidateGripSockets = (SlotIndex == 0)
			? TArray<FName>{ TEXT("HandGrip"), TEXT("Grip"), TEXT("GripSocket"), TEXT("WeaponGrip"), TEXT("HandGrip_R") }
			: TArray<FName>{ TEXT("HandGrip"), TEXT("Grip"), TEXT("GripSocket"), TEXT("WeaponGrip"), TEXT("HandGrip_L") };

		for (const FName GripSocketName : CandidateGripSockets)
		{
			if (!VisualComponent->DoesSocketExist(GripSocketName))
			{
				continue;
			}

			// Align the weapon's own grip socket to the character hand socket by inverting the child socket transform.
			const FTransform WeaponGripSocketTransform = VisualComponent->GetSocketTransform(GripSocketName, RTS_Component);
			InOutRelativeTransform = WeaponGripSocketTransform.Inverse();
			// Preserve the upright blade direction and roll only around the sword's
			// own length so its cutting edge faces outward.
			if (ItemId.Equals(TEXT("iron_sword"), ESearchCase::IgnoreCase))
			{
				InOutRelativeTransform.SetRotation(
					(InOutRelativeTransform.GetRotation() * FQuat(FVector::UpVector, FMath::DegreesToRadians(90.0f))).GetNormalized());
			}
			UE_LOG(
				LogFableForge,
				Warning,
				TEXT("Aligned equipped weapon '%s' using weapon socket '%s' -> character socket '%s' (weapon socket rel loc %.2f,%.2f,%.2f)."),
				*ItemId,
				*GripSocketName.ToString(),
				*AttachSocket.ToString(),
				WeaponGripSocketTransform.GetLocation().X,
				WeaponGripSocketTransform.GetLocation().Y,
				WeaponGripSocketTransform.GetLocation().Z);

			return true;
		}

		UE_LOG(
			LogFableForge,
			Warning,
			TEXT("Equipped weapon '%s' (%s) has no recognized grip socket. Character socket='%s'."),
			*ItemId,
			*GetNameSafe(VisualComponent),
			*AttachSocket.ToString());

		return false;
	};

	// Load once as UObject so a static mesh does not first attempt a failed skeletal mesh load.
	UObject* VisualAsset = LoadObject<UObject>(nullptr, *AssetPath);
	if (USkeletalMesh* SkeletalMesh = Cast<USkeletalMesh>(VisualAsset))
	{
		USkeletalMeshComponent* SkeletalVisual = NewObject<USkeletalMeshComponent>(this);
		if (SkeletalVisual == nullptr)
		{
			return;
		}

		SkeletalVisual->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		SkeletalVisual->SetGenerateOverlapEvents(false);
		SkeletalVisual->SetCanEverAffectNavigation(false);
		SkeletalVisual->bUseAttachParentBound = false;
		SkeletalVisual->SetSkeletalMesh(SkeletalMesh);

		// Body armor must match the character's bone hierarchy to share its pose.
		const bool bIsBodyArmorSlot = (SlotIndex == 3 || SlotIndex == 4 || SlotIndex == 5 || SlotIndex == 6);
		const USkeletalMesh* CharacterSkeletalMesh = (GetMesh() != nullptr) ? GetMesh()->GetSkeletalMeshAsset() : nullptr;
		const USkeleton* CharacterSkeleton = (CharacterSkeletalMesh != nullptr) ? CharacterSkeletalMesh->GetSkeleton() : nullptr;
		const USkeleton* ArmorSkeleton = SkeletalMesh->GetSkeleton();
		const bool bSkeletonsMatchForModularArmor = CanUseLeaderPoseForModularArmor(CharacterSkeletalMesh, SkeletalMesh);
		const bool bUseModularSkinnedArmorAttachment = bIsBodyArmorSlot && bSkeletonsMatchForModularArmor;
		const FName SkeletalAttachSocket = bUseModularSkinnedArmorAttachment ? NAME_None : AttachSocket;
		FTransform SkeletalRelativeTransform = bUseModularSkinnedArmorAttachment ? FTransform::Identity : RelativeTransform;

		if (bIsBodyArmorSlot && !bSkeletonsMatchForModularArmor)
		{
			UE_LOG(
				LogFableForge,
				Warning,
				TEXT("Body armor '%s' has incompatible bones (armor skeleton '%s', character '%s'). Assign a compatible modular mesh for slot %d; keeping the base character visible."),
				*ItemId,
				*GetNameSafe(ArmorSkeleton),
				*GetNameSafe(CharacterSkeleton),
				SlotIndex);
			return;
		}
		else if (bIsBodyArmorSlot && CharacterSkeleton != nullptr && ArmorSkeleton != nullptr && CharacterSkeleton != ArmorSkeleton)
		{
			UE_LOG(
				LogFableForge,
				Warning,
				TEXT("Body armor '%s' uses compatible bones with a different skeleton asset ('%s' vs '%s'); using modular leader-pose attachment for slot %d."),
				*ItemId,
				*GetNameSafe(ArmorSkeleton),
				*GetNameSafe(CharacterSkeleton),
				SlotIndex);
		}

		UE_LOG(
			LogFableForge,
			Warning,
			TEXT("Equipping item '%s' as SkeletalMesh '%s' on socket '%s' (asset path: %s)."),
			*ItemId,
			*GetNameSafe(SkeletalMesh),
			*SkeletalAttachSocket.ToString(),
			*AssetPath);
		SkeletalVisual->SetupAttachment(GetMesh(), SkeletalAttachSocket);
		SkeletalVisual->RegisterComponent();
		TryApplyWeaponGripSocketAlignment(SkeletalVisual, SkeletalRelativeTransform);
		SkeletalVisual->SetRelativeTransform(SkeletalRelativeTransform);
		// Share the body pose without independently evaluating another animation instance.
		if (bUseModularSkinnedArmorAttachment)
		{
			SkeletalVisual->bUseAttachParentBound = true;
			SkeletalVisual->bSyncAttachParentLOD = true;
			SkeletalVisual->SetLeaderPoseComponent(GetMesh(), true, false);
		}
		EquipmentVisualComponents[SlotIndex] = SkeletalVisual;
		return;
	}

	if (UStaticMesh* StaticMesh = Cast<UStaticMesh>(VisualAsset))
	{
		UStaticMeshComponent* StaticVisual = NewObject<UStaticMeshComponent>(this);
		if (StaticVisual == nullptr)
		{
			return;
		}

		StaticVisual->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		StaticVisual->SetGenerateOverlapEvents(false);
		StaticVisual->SetCanEverAffectNavigation(false);
		// Weapons can extend beyond the character bounds, especially long staves.
		StaticVisual->bUseAttachParentBound = false;
		StaticVisual->SetStaticMesh(StaticMesh);
		UE_LOG(
			LogFableForge,
			Warning,
			TEXT("Equipping item '%s' as StaticMesh '%s' on socket '%s' (asset path: %s)."),
			*ItemId,
			*GetNameSafe(StaticMesh),
			*AttachSocket.ToString(),
			*AssetPath);
		StaticVisual->SetupAttachment(GetMesh(), AttachSocket);
		StaticVisual->RegisterComponent();
		TryApplyWeaponGripSocketAlignment(StaticVisual, RelativeTransform);
		StaticVisual->SetRelativeTransform(RelativeTransform);
		EquipmentVisualComponents[SlotIndex] = StaticVisual;
		return;
	}

	UE_LOG(LogFableForge, Warning, TEXT("Equipped item '%s' could not load visual asset '%s'."), *ItemId, *AssetPath);
}

FName AFableForgeCharacter::GetEquipmentAttachSocket(int32 SlotIndex) const
{
	auto ResolveExistingSocket = [&](const FName PreferredSocket, const FName FallbackSocket) -> FName
	{
		if (GetMesh() != nullptr && GetMesh()->DoesSocketExist(PreferredSocket))
		{
			return PreferredSocket;
		}

		if (GetMesh() != nullptr && (PreferredSocket == TEXT("HandGrip_R") || PreferredSocket == TEXT("HandGrip_L")))
		{
			UE_LOG(
				LogFableForge,
				Warning,
				TEXT("Character mesh '%s' is missing socket '%s'; falling back to '%s'."),
				*GetNameSafe(GetMesh()->GetSkeletalMeshAsset()),
				*PreferredSocket.ToString(),
				*FallbackSocket.ToString());
		}

		return FallbackSocket;
	};

	switch (SlotIndex)
	{
	case 0: return ResolveExistingSocket(TEXT("HandGrip_R"), TEXT("hand_r"));
	case 1: return ResolveExistingSocket(TEXT("HandGrip_L"), TEXT("hand_l"));
	case 2: return ResolveExistingSocket(TEXT("head_armor_socket"), TEXT("head"));
	case 3: return ResolveExistingSocket(TEXT("chest_armor_socket"), TEXT("spine_03"));
	case 4: return ResolveExistingSocket(TEXT("hands_r_armor_socket"), TEXT("hand_r"));
	case 5: return ResolveExistingSocket(TEXT("legs_armor_socket"), TEXT("pelvis"));
	case 6: return ResolveExistingSocket(TEXT("feet_r_armor_socket"), TEXT("foot_r"));
	case 7: return ResolveExistingSocket(TEXT("back_armor_socket"), TEXT("spine_03"));
	case 8: return ResolveExistingSocket(TEXT("neck_armor_socket"), TEXT("neck_01"));
	case 9: return ResolveExistingSocket(TEXT("ring_r_finger_armor_socket"), TEXT("hand_r"));
	case 10: return ResolveExistingSocket(TEXT("ring_l_finger_armor_socket"), TEXT("hand_l"));
	default: return NAME_None;
	}
}

FTransform AFableForgeCharacter::GetEquipmentSlotRelativeTransform(int32 SlotIndex, const FString& ItemId) const
{
	if (SlotIndex == 0)
	{
		if (ItemId.Contains(TEXT("staff")))
		{
			return FTransform(FRotator(-10.0f, 90.0f, 0.0f), FVector(8.0f, 1.0f, -3.0f), FVector(0.9f));
		}

		return FTransform(FRotator(0.0f, 90.0f, 0.0f), FVector(6.0f, 0.0f, -2.0f), FVector(1.0f));
	}

	switch (SlotIndex)
	{
	case 1: return FTransform(FRotator(0.0f, -90.0f, 0.0f), FVector(0.0f), FVector(1.0f));
	case 2: return FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector(0.22f, 0.22f, 0.18f));
	case 3: return FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector(0.18f, 0.28f, 0.42f));
	case 4: return FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector(0.12f, 0.12f, 0.26f));
	// Give the fitted lower garments a small clearance envelope so the body
	// cannot break through at the glute, ankle, or heel during locomotion.
		case 5: return FTransform(FRotator::ZeroRotator, FVector(0.0f, 0.0f, 1.6f), FVector(0.147f, 0.147f, 0.37f));
	case 6: return FTransform(FRotator::ZeroRotator, FVector(0.0f, 0.0f, -0.6f), FVector(0.192f, 0.128f, 0.086f));
	case 7: return FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector(0.25f, 0.25f, 0.25f));
	case 8: return FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector(0.10f, 0.10f, 0.10f));
	case 9: return FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector(0.05f, 0.05f, 0.05f));
	case 10: return FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector(0.05f, 0.05f, 0.05f));
	default: return FTransform::Identity;
	}
}

bool AFableForgeCharacter::ResolveEquipmentMeshPath(const FString& ItemId, int32 SlotIndex, FString& OutAssetPath) const
{
	OutAssetPath.Reset();

	if (ItemId.IsEmpty())
	{
		return false;
	}

	const FString LowerId = ItemId.ToLower();

	const TCHAR* SourceTablePath = (SlotIndex == 0) ? WeaponsDataTablePath : ArmorDataTablePath;
	if (UDataTable* ItemTable = LoadObject<UDataTable>(nullptr, SourceTablePath))
	{
		static const FString ContextString(TEXT("AFableForgeCharacter::ResolveEquipmentMeshPath"));
		const FFableItemDefinitionTableRow* ResolvedRow = ItemTable->FindRow<FFableItemDefinitionTableRow>(FName(*ItemId), ContextString, false);
		if (ResolvedRow == nullptr)
		{
			TArray<FFableItemDefinitionTableRow*> AllRows;
			ItemTable->GetAllRows(ContextString, AllRows);
			for (const FFableItemDefinitionTableRow* CandidateRow : AllRows)
			{
				if (CandidateRow != nullptr && CandidateRow->ItemId.Equals(ItemId, ESearchCase::IgnoreCase))
				{
					ResolvedRow = CandidateRow;
					UE_LOG(
						LogFableForge,
						Warning,
						TEXT("Resolved equipped item '%s' by ItemId field instead of row name in %s."),
						*ItemId,
						SourceTablePath);
					break;
				}
			}
		}

		if (ResolvedRow != nullptr)
		{
			if (!ResolvedRow->WorldSkeletalMesh.IsNull())
			{
				OutAssetPath = ResolvedRow->WorldSkeletalMesh.ToSoftObjectPath().ToString();
				if (!OutAssetPath.IsEmpty())
				{
					return true;
				}
			}

			if (!ResolvedRow->WorldStaticMesh.IsNull())
			{
				OutAssetPath = ResolvedRow->WorldStaticMesh.ToSoftObjectPath().ToString();
				if (!OutAssetPath.IsEmpty())
				{
					return true;
				}
			}

			UE_LOG(LogFableForge, Verbose, TEXT("No world mesh set in DataTable row for equipped item '%s' (%s). Using fallback."),
				*ItemId, SourceTablePath);
		}
		else
		{
			UE_LOG(LogFableForge, Warning, TEXT("No DataTable row found for equipped item '%s' in %s (row-name lookup + ItemId fallback failed)."),
				*ItemId, SourceTablePath);
		}
	}

	// Retain imported weapon fallbacks. Unmapped armor has no visual until an artist assigns a mesh.
	if (SlotIndex == 0)
	{
		if (LowerId.Contains(TEXT("dagger")))
		{
			OutAssetPath = TEXT("/Game/External/FreeMeleeWeaps/Static_Meshes/SM_Dagger.SM_Dagger");
			return true;
		}

		OutAssetPath = TEXT("/Game/External/FreeMeleeWeaps/Static_Meshes/SM_Sword.SM_Sword");
		return true;
	}

	UE_LOG(
		LogFableForge,
		Warning,
		TEXT("Armor item '%s' has no mapped world mesh in %s; keeping the base character visible."),
		*ItemId,
		SourceTablePath);

	return false;
}

#if WITH_DEV_AUTOMATION_TESTS
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FFableModularArmorHierarchyTest,
	"FableForge.Character.ModularArmorHierarchy",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FFableModularArmorHierarchyTest::RunTest(const FString& Parameters)
{
	auto MakeMesh = [](const TArray<FMeshBoneInfo>& Bones)
	{
		USkeletalMesh* Mesh = NewObject<USkeletalMesh>();
		FReferenceSkeletonModifier Modifier(Mesh->GetRefSkeleton(), nullptr);
		for (const FMeshBoneInfo& Bone : Bones)
		{
			Modifier.Add(Bone, FTransform::Identity);
		}
		return Mesh;
	};
	const FMeshBoneInfo Root(TEXT("root"), TEXT("root"), INDEX_NONE);
	const FMeshBoneInfo Spine(TEXT("spine"), TEXT("spine"), 0);
	USkeletalMesh* Character = MakeMesh({ Root, Spine, FMeshBoneInfo(TEXT("hand"), TEXT("hand"), 1) });
	USkeletalMesh* CompatibleArmor = MakeMesh({ Root, Spine });
	USkeletalMesh* WrongParent = MakeMesh({ Root, Spine, FMeshBoneInfo(TEXT("hand"), TEXT("hand"), 0) });
	USkeletalMesh* MissingBone = MakeMesh({ Root, FMeshBoneInfo(TEXT("cape"), TEXT("cape"), 0) });
	USkeletalMesh* EmptyMesh = MakeMesh({});

	TestFalse(TEXT("Missing mesh cannot drive modular armor"), CanUseLeaderPoseForModularArmor(nullptr, CompatibleArmor));
	TestFalse(TEXT("Empty skeleton cannot drive modular armor"), CanUseLeaderPoseForModularArmor(Character, EmptyMesh));
	TestTrue(TEXT("A matching hierarchy subset can share the character pose"), CanUseLeaderPoseForModularArmor(Character, CompatibleArmor));
	TestFalse(TEXT("Unmapped armor bones cannot share the character pose"), CanUseLeaderPoseForModularArmor(Character, MissingBone));
	TestFalse(TEXT("Matching bone names with different parents are incompatible"), CanUseLeaderPoseForModularArmor(Character, WrongParent));

	// A shared skeleton asset alone does not guarantee compatible mesh hierarchies.
	USkeleton* SharedSkeleton = NewObject<USkeleton>();
	Character->SetSkeleton(SharedSkeleton);
	WrongParent->SetSkeleton(SharedSkeleton);
	TestFalse(TEXT("Shared skeleton asset does not override a hierarchy mismatch"), CanUseLeaderPoseForModularArmor(Character, WrongParent));
	return true;
}
#endif
