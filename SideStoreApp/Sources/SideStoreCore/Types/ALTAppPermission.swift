//
//  ALTAppPermission.swift
//  SideStore
//
//  Created by Joseph Mattiello on 2/28/23.
//  Copyright © 2923 Joseph Mattiello. All rights reserved.
//

import Foundation

@objc
public enum ALTAppPermissionType: Int, CaseIterable {
    case photos
    case camera
    case location
    case contacts
    case reminders
    case appleMusic = 6
    case microphone
    case speechRecognition
    case backgroundAudio
    case backgroundFetch
    case bluetooth
    case network
    case calendars
    case touchID
    case faceID
    case siri
    case motion
	case null

	public init(rawValue: String) {
		switch rawValue {
		case "photos": self = .photos
		case "camera": self = .camera
		case "location": self = .location
		case "contacts": self = .contacts
		case "reminders": self = .reminders
		case "appleMusic", "music": self = .appleMusic
		case "microphone": self = .microphone
		case "speechRecognition", "speech-recognition": self = .speechRecognition
		case "backgroundAudio", "background-audio": self = .backgroundAudio
		case "backgroundFetch", "background-fetch": self =  .backgroundFetch
		case "bluetooth": self = .bluetooth
		case "network": self = .network
		case "calendars": self = .calendars
		case "touchID", "touchid": self = .touchID
		case "faceID", "faceid": self = .faceID
		case "siri": self = .siri
		case "motion": self = .motion
		default: self = .null
		}
	}

    public var stringValue: String {
        switch self {
        case .photos:
            return "photos"
        case .camera:
            return "camera"
        case .location:
            return "location"
        case .contacts:
            return "contacts"
        case .reminders:
            return "reminders"
        case .appleMusic:
            return "music"
        case .microphone:
            return "microphone"
        case .speechRecognition:
            return "speech-recognition"
        case .backgroundAudio:
            return "background-audio"
        case .backgroundFetch:
            return "background-fetch"
        case .bluetooth:
            return "bluetooth"
        case .network:
            return "network"
        case .calendars:
            return "calendars"
        case .touchID:
            return "touchid"
        case .faceID:
            return "faceid"
        case .siri:
            return "siri"
        case .motion:
            return "motion"
		case .null:
			return ""
		}
    }
}

@objc
public final class ALTAppPermissionTypeTransformer: ValueTransformer {
	public override func transformedValue(_ value: Any?) -> Any? {
		guard let enumValue = value as? ALTAppPermissionType else { return "" }
		return enumValue.rawValue
	}

	public override func reverseTransformedValue(_ value: Any?) -> Any? {
		guard let rawValue = value as? String else { return ALTAppPermissionType.null }
		return ALTAppPermissionType(rawValue: rawValue)
	}
}
