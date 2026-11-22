/*****************************************************************************
 * AppIntent.swift
 *****************************************************************************
 * Copyright (c) 2024 VideoLAN. All rights reserved.
 * $Id$
 *
 * Authors: Diogo Simao Marques <dogo@videolabs.io>
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

import WidgetKit

#if canImport(AppIntents)
import AppIntents

@available(iOS 17.0, *)
struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Configuration"
    static var description = IntentDescription("This is an example widget.")

    @Parameter(title: "Displayed title", default: "Last played")
    var configurableTitle: String

    init() {
        self.configurableTitle = "Last played"
    }

    init(configurableTitle: String) {
        self.configurableTitle = configurableTitle
    }
}
#endif
