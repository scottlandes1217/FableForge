// Copyright Epic Games, Inc. All Rights Reserved.

#include "FableForgeCharacter.h"
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
#include "Engine/StaticMesh.h"
#include "Engine/DataTable.h"
#include "Engine/GameInstance.h"
#include "Animation/Skeleton.h"
#include "RPG/Data/FableItemDefinitionTableRow.h"
#include "RPG/Save/FableSaveSubsystem.h"

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

		const USkeleton* CharacterSkeleton = CharacterMesh->GetSkeleton();
		const USkeleton* ArmorSkeleton = ArmorMesh->GetSkeleton();
		if (CharacterSkeleton != nullptr && ArmorSkeleton != nullptr && CharacterSkeleton == ArmorSkeleton)
		{
			return true;
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

AFableForgeCharacter::AFableForgeCharacter()
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
	GetCharacterMovement()->bOrientRotationToMovement = false;
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
	if (CameraBoom == nullptr || Controller == nullptr)
	{
		return;
	}

	const bool bShouldFollow = IsMovementActive() && !IsManualLookActive();
	float TargetArmLength = IdleCameraArmLength;
	if (bAdjustArmLengthWithMovement)
	{
		TargetArmLength = bShouldFollow ? MovingCameraArmLength : IdleCameraArmLength;
	}
	FVector TargetSocketOffset = IdleCameraSocketOffset;
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
		// WoW-style movement: A/D turn character yaw, W/S move along facing direction.
		if (!FMath::IsNearlyZero(Right))
		{
			const float DeltaSeconds = GetWorld() ? GetWorld()->GetDeltaSeconds() : 0.0f;
			AddActorLocalRotation(FRotator(0.0f, Right * KeyboardTurnRate * DeltaSeconds, 0.0f));
		}

		if (!FMath::IsNearlyZero(Forward))
		{
			AddMovementInput(GetActorForwardVector(), Forward);
		}
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
	if (UGameInstance* GameInstance = GetGameInstance())
	{
		if (UFableSaveSubsystem* SaveSubsystem = GameInstance->GetSubsystem<UFableSaveSubsystem>())
		{
			TArray<FString> InventorySlots;
			TArray<FString> EquippedSlots;
			if (SaveSubsystem->TryGetActiveInventory(InventorySlots, EquippedSlots))
			{
				ApplyEquipmentVisuals(EquippedSlots);
				return;
			}
		}
	}

	ApplyEquipmentVisuals(TArray<FString>());
}

void AFableForgeCharacter::HandleActiveInventoryChanged(const TArray<FString>& InInventorySlots, const TArray<FString>& InEquippedSlots)
{
	(void)InInventorySlots;
	ApplyEquipmentVisuals(InEquippedSlots);
}

void AFableForgeCharacter::ApplyEquipmentVisuals(const TArray<FString>& InEquippedSlots)
{
	const int32 SlotCount = UFableSaveSubsystem::EquipmentSlotsPerCharacter;
	if (EquipmentVisualComponents.Num() != SlotCount)
	{
		EquipmentVisualComponents.SetNum(SlotCount);
	}

	for (int32 SlotIndex = 0; SlotIndex < SlotCount; ++SlotIndex)
	{
		ClearEquipmentVisual(SlotIndex);

		const FString ItemId = InEquippedSlots.IsValidIndex(SlotIndex) ? InEquippedSlots[SlotIndex] : FString();
		if (!ItemId.IsEmpty())
		{
			CreateEquipmentVisualForSlot(SlotIndex, ItemId);
		}
	}

	UpdateBodyMaterialVisibility(InEquippedSlots);
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
			GetMesh()->ShowMaterialSection(MaterialSlot, MaterialSlot, bVisible, LODIndex);
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

	if (USkeletalMesh* SkeletalMesh = LoadObject<USkeletalMesh>(nullptr, *AssetPath))
	{
		USkeletalMeshComponent* SkeletalVisual = NewObject<USkeletalMeshComponent>(this);
		if (SkeletalVisual == nullptr)
		{
			return;
		}

		SkeletalVisual->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		SkeletalVisual->SetGenerateOverlapEvents(false);
		SkeletalVisual->SetCanEverAffectNavigation(false);
		SkeletalVisual->bUseAttachParentBound = true;
		SkeletalVisual->BoundsScale = 2.0f;
		SkeletalVisual->SetSkeletalMesh(SkeletalMesh);

		// Chest/legs/feet armor are typically modular skinned pieces and should follow the full body pose
		// only when they share the same skeleton as the character.
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
				TEXT("Body armor '%s' uses skeleton '%s' but character uses '%s'; falling back to socket attachment for slot %d."),
				*ItemId,
				*GetNameSafe(ArmorSkeleton),
				*GetNameSafe(CharacterSkeleton),
				SlotIndex);
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
			// Modular skinned armor should inherit the full pose. Socket props can remain independently attached.
			if (bUseModularSkinnedArmorAttachment)
			{
				SkeletalVisual->bSyncAttachParentLOD = true;
				SkeletalVisual->SetLeaderPoseComponent(GetMesh(), true);
			}
		EquipmentVisualComponents[SlotIndex] = SkeletalVisual;
		return;
	}

	if (UStaticMesh* StaticMesh = LoadObject<UStaticMesh>(nullptr, *AssetPath))
	{
		UStaticMeshComponent* StaticVisual = NewObject<UStaticMeshComponent>(this);
		if (StaticVisual == nullptr)
		{
			return;
		}

		StaticVisual->SetCollisionEnabled(ECollisionEnabled::NoCollision);
		StaticVisual->SetGenerateOverlapEvents(false);
		StaticVisual->SetCanEverAffectNavigation(false);
		StaticVisual->bUseAttachParentBound = true;
		StaticVisual->BoundsScale = 2.0f;
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
	case 5: return FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector(0.14f, 0.14f, 0.35f));
	case 6: return FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector(0.18f, 0.12f, 0.08f));
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

	// Shared character mesh setup: no male/female split. Weapons use imported meshes; armor uses a visible placeholder
	// until dedicated Unreal armor assets are imported and mapped.
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
		TEXT("Armor item '%s' has no mapped world mesh in %s; using placeholder cube visual."),
		*ItemId,
		SourceTablePath);

	OutAssetPath = TEXT("/Engine/BasicShapes/Cube.Cube");
	return true;
}
