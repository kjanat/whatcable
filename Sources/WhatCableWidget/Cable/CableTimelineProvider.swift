import AppIntents
import Foundation
import WhatCableCore
import WidgetKit
import os.log

struct CableTimelineProvider: AppIntentTimelineProvider {
    private let staleAfter: TimeInterval = 5 * 60
    private let log = Logger(
        subsystem: "uk.whatcable.whatcable",
        category: "widget-timeline"
    )
    typealias Entry = CableWidgetEntry
    typealias Intent = CableWidgetIntent

    func placeholder(in context: Context) -> CableWidgetEntry {
        CableWidgetEntry.placeholder
    }

    func snapshot(for configuration: CableWidgetIntent, in context: Context) async
        -> CableWidgetEntry
    {
        if context.isPreview {
            return .placeholder
        }
        return currentEntry(for: configuration)
    }

    func timeline(for configuration: CableWidgetIntent, in context: Context) async -> Timeline<
        CableWidgetEntry
    > {
        let entry = currentEntry(for: configuration)
        return Timeline(
            entries: [entry],
            policy: .after(Date().addingTimeInterval(60))
        )
    }

    // MARK: - Read from App Group

    private func currentEntry(for configuration: CableWidgetIntent) -> CableWidgetEntry {
        guard let url = WidgetSnapshot.sharedFileURL else {
            log.error(
                "Failed to resolve App Group container URL for \(WidgetSnapshot.appGroupID, privacy: .public)"
            )
            return CableWidgetEntry(date: Date(), snapshot: nil, configuration: configuration)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            log.error(
                "Failed to read widget snapshot: \(error.localizedDescription, privacy: .public)")
            return CableWidgetEntry(date: Date(), snapshot: nil, configuration: configuration)
        }

        let snapshot: WidgetSnapshot
        do {
            snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        } catch {
            log.error(
                "Failed to decode widget snapshot (\(data.count) bytes): \(error.localizedDescription, privacy: .public)"
            )
            return CableWidgetEntry(date: Date(), snapshot: nil, configuration: configuration)
        }

        let age = Date().timeIntervalSince(snapshot.timestamp)
        guard age <= staleAfter else {
            log.error("Widget snapshot is stale (\(Int(age))s old), showing empty state")
            return CableWidgetEntry(date: Date(), snapshot: nil, configuration: configuration)
        }

        return CableWidgetEntry(
            date: snapshot.timestamp, snapshot: snapshot, configuration: configuration)
    }
}

struct CableWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let configuration: CableWidgetIntent

    static let placeholder = CableWidgetEntry(
        date: Date(),
        snapshot: WidgetSnapshot(ports: [
            .init(
                id: 1,
                portName: "USB-C Port 1",
                status: .thunderboltCable,
                headline: "Thunderbolt / USB4",
                subtitle: "Supports high-speed data, video, smart cable.",
                topBullet: "Linked at up to 40 Gb/s x 2",
                iconName: "bolt.horizontal.fill",
                deviceCount: 2
            ),
            .init(
                id: 2,
                portName: "USB-C Port 2",
                status: .charging,
                headline: "Charging - 96W charger",
                subtitle: "Power is flowing. No data connection.",
                topBullet: "Charger advertises up to 96W",
                iconName: "bolt.fill",
                deviceCount: 0
            ),
            .init(
                id: 3,
                portName: "USB-C Port 3",
                status: .empty,
                headline: "Nothing connected",
                subtitle: "Plug a cable in to see what it can do.",
                topBullet: nil,
                iconName: "powerplug",
                deviceCount: 0
            ),
        ]),
        configuration: CableWidgetIntent()
    )
}
