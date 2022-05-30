# Sidestore

> Sidestore is an alternative app store for non-jailbroken iOS devices that can sideload using a VPN over the internet. 

[![Swift Version](https://img.shields.io/badge/swift-5.0-orange.svg)](https://swift.org/)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](http://makeapullrequest.com)

Sidestore is an iOS application that allows you to sideload other apps (.ipa files) onto your iOS device with just your Apple ID. Sidestore resigns apps with your personal development certificate and sends them to a desktop app called AltServer or use the Sidestore VPN, which installs the resigned apps back to your device using iTunes WiFi sync or using the Sidestore VPN where you can sideload at any place over wifi that supports zerotier that has internet. To prevent apps from expiring, Sidestore just like Altstore will also periodically refresh your apps in the background when on the same WiFi as AltServer or using Sidestore VPN over wifi on any network that includes a internet connection.

The goal of this project is to allow easy and a mostly computerless experience to sideload apps on iOS based devices. This project is meant as a alternative of Altstore where you can do anything altstore can (maybe even more) but over a vpn. You will be able to use sidestore just like if you were using Altstore with benifits.
 (contributions welcome! 🙂).


## Requirements
- Xcode 11
- iOS 12.2+ (Sidestore)
- macOS 10.14.4+ (TBD)
- Swift 5+
- Visual Studio Code

## Project Overview

### Sidestore
Sidestore is a alternative to Altstore and is a sandboxed iOS application like Altstore. The Sidestore app target contains the vast majority of AltStore's functionality, including all the logic for downloading and updating apps through Sidestore.

### Netmuxd
Netmuxd is a program that replaces Usbmuxd to be able to connect over a VPN reliably. It is coded in rust language and is a fully open source program that you can use. 

## Compilation Instructions
AltStore and AltServer are both fairly straightforward to compile and run if you're already an iOS or macOS developer. To compile AltStore and/or AltServer:

1. Clone the repository 
	``` 
	git clone https://github.com/rileytestut/AltStore.git
	```
2. Update submodules: 
	```
	cd AltStore 
	git submodule update --init --recursive
	```
3. Open `AltStore.xcworkspace` and select the AltStore project in the project navigator. On the `Signing & Capabilities` tab, change the team from `Yvette Testut` to your own account.

5. **(Sidestore app only)** Change the value for `ALTDeviceID` in the Info.plist to your device's UDID. Normally, Sidestore embeds the device's UDID in AltStore's Info.plist during installation. When running through Visual Studio you'll need to set the value yourself or else Sidetore won't resign (or even install) apps for the proper device. You can achieve this by changing a few things to be able to build and use Sidestore.

**Steps for making Sidestore run with your own build**
This is all in vscode because Xcode UI is tricky

AltBackup/AltBackup.entitlements
Change the app group to something you can sign like group.com.[Rick].SideStore

AltStore/AltStore.entitlements
Same thing ^^

AltWidget/AltWidgetExtension.entitlements
Same thing ^^

AltWidget/Info.plist
Change ALTAppGroups to your group

AltStore/Info.plist
Change ALTAppGroups to your app group name group.com.[Rick].SideStore
Change ALTDeviceID to your device's UDID. You can fetch it with libimobiledevice if needed.

AltStore/project.pbxproj
Change all the DEVELOPMENT_TEAMs to your dev team ID. It's what AltStore appends to your bundle IDs.
Change all the PRODUCT_BUNDLE_IDENTIFIERs to something you can sign like com.[Rick].SideStore...

Shared/Extensions/Bundle+AltStore.swift
Change the string "group.com.rileytestut.AltStore" to your group you are using.

Build + run app! 🎉

## Licensing

Due to the licensing of some dependencies used by Sidestore, I have no choice but to distribute Sidestore under the **AGPLv3 license** because this is a fork of Altstore. That being said, our goal for Sidestore is for it to be an open source project *anyone* can use without restrictions, so we explicitly give permission for anyone to use, modify, and distribute all *our* original code for this project in any form, with or without attribution, without fear of legal consequences (dependencies remain under their original licenses, however).
