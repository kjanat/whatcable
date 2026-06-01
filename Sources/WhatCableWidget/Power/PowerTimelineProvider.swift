import Foundation
import WhatCableCore
import WidgetKit
import os.log

struct PowerTimelineProvider: TimelineProvider {
    private let staleAfter: TimeInterval = 5 * 60
    private let log = Logger(
        subsystem: "uk.whatcable.whatcable",
        category: "power-widget-timeline"
    )
    typealias Entry = PowerMonitorEntry

    func placeholder(in context: Context) -> PowerMonitorEntry {
        PowerMonitorEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (PowerMonitorEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
        } else {
            completion(currentEntry())
        }
    }

    func getTimeline(
        in context: Context, completion: @escaping (Timeline<PowerMonitorEntry>) -> Void
    ) {
        let entry = currentEntry()
        let timeline = Timeline(
            entries: [entry],
            policy: .after(Date().addingTimeInterval(60))
        )
        completion(timeline)
    }

    private func currentEntry() -> PowerMonitorEntry {
        guard let url = WidgetSnapshot.sharedFileURL else {
            return PowerMonitorEntry(date: Date(), snapshot: nil)
        }
        guard let data = try? Data(contentsOf: url),
            let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else {
            return PowerMonitorEntry(date: Date(), snapshot: nil)
        }
        let age = Date().timeIntervalSince(snapshot.timestamp)
        guard age <= staleAfter else {
            return PowerMonitorEntry(date: Date(), snapshot: nil)
        }
        return PowerMonitorEntry(date: snapshot.timestamp, snapshot: snapshot)
    }
}

struct PowerMonitorEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    static let placeholder = PowerMonitorEntry(
        date: Date(),
        snapshot: WidgetSnapshot(
            ports: [],
            powerState: .init(
                batteryPercent: 78,
                isCharging: true,
                fullyCharged: false,
                isDesktopMac: false,
                adapterWatts: 96,
                adapterDescription: "pd charger"
            )
        )
    )
}
