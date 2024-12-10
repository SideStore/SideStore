//
//  ALTAppPermissions.m
//  AltStore
//
//  Created by Riley Testut on 7/23/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

#import "ALTAppPermissions.h"

ALTAppPermissionType const ALTAppPermissionTypeUnknown = @"unknown";
ALTAppPermissionType const ALTAppPermissionTypeEntitlement = @"entitlement";
ALTAppPermissionType const ALTAppPermissionTypePrivacy = @"privacy";
ALTAppPermissionType const ALTAppPermissionTypeBackgroundMode = @"background";

ALTAppPrivacyPermission const ALTAppPrivacyPermissionAppleMusic = @"AppleMusic";
ALTAppPrivacyPermission const ALTAppPrivacyPermissionBluetooth = @"BluetoothAlways";
ALTAppPrivacyPermission const ALTAppPrivacyPermissionCalendars = @"Calendars";
ALTAppPrivacyPermission const ALTAppPrivacyPermissionCamera = @"Camera";
ALTAppPrivacyPermission const ALTAppPrivacyPermissionFaceID = @"FaceID";
ALTAppPrivacyPermission const ALTAppPrivacyPermissionLocalNetwork = @"LocalNetwork";
ALTAppPrivacyPermission const ALTAppPrivacyPermissionMicrophone = @"Microphone";
ALTAppPrivacyPermission const ALTAppPrivacyPermissionPhotos = @"PhotoLibrary";
