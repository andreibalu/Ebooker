//
//  PagelessWidgetBundle.swift
//  PagelessWidget
//

import SwiftUI
import WidgetKit

@main
struct PagelessWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        LibraryWidget()
        PagelessLiveActivityView()
    }
}
