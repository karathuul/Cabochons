//
//  MateriaWidgetBundle.swift
//  MateriaWidget
//
//  Created by Karl Brandenberger on 8/29/26.
//

import WidgetKit
import SwiftUI

@main
struct MateriaWidgetBundle: WidgetBundle {
    var body: some Widget {
        MateriaWidget()
        MateriaWidgetControl()
        MateriaWidgetLiveActivity()
    }
}
