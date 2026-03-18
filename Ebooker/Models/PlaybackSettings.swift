//
//  PlaybackSettings.swift
//  Ebooker
//

import Foundation

enum LibrarySortOption: String, CaseIterable, Identifiable {
    case recent
    case title
    case author
    case duration
    case dateAdded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            "Recently Played"
        case .title:
            "Title"
        case .author:
            "Author"
        case .duration:
            "Duration"
        case .dateAdded:
            "Date Added"
        }
    }
}

enum ResumeBacktrackOption: Double, CaseIterable, Identifiable {
    case exact = 0
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case oneMinute = 60

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .exact:
            "Resume exactly"
        case .fifteenSeconds:
            "Resume 15 seconds earlier"
        case .thirtySeconds:
            "Resume 30 seconds earlier"
        case .oneMinute:
            "Resume 1 minute earlier"
        }
    }
}

enum SkipIntervalOption: Double, CaseIterable, Identifiable {
    case fifteen = 15
    case thirty = 30
    case fortyFive = 45

    var id: Double { rawValue }

    var title: String {
        "\(Int(rawValue)) seconds"
    }
}

enum MomentBacktrackOption: Double, CaseIterable, Identifiable {
    case exact = 0
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case oneMinute = 60
    case twoMinutes = 120

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .exact:
            "Save at current position"
        case .fifteenSeconds:
            "15 seconds earlier"
        case .thirtySeconds:
            "30 seconds earlier"
        case .oneMinute:
            "1 minute earlier"
        case .twoMinutes:
            "2 minutes earlier"
        }
    }
}

enum SleepTimerOption: Double, CaseIterable, Identifiable {
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case sixtyMinutes = 3600

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .fiveMinutes:
            "5 minutes"
        case .fifteenMinutes:
            "15 minutes"
        case .thirtyMinutes:
            "30 minutes"
        case .sixtyMinutes:
            "60 minutes"
        }
    }
}
