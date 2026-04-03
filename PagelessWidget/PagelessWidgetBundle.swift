//
//  PagelessWidgetBundle.swift
//  PagelessWidget
//
//  Created by andreibalu on 03.04.2026.
//

import WidgetKit
import SwiftUI

@main
struct PagelessWidgetBundle: WidgetBundle {
    var body: some Widget {
        PagelessWidget()
        PagelessWidgetControl()
        PagelessWidgetLiveActivity()
    }
}
