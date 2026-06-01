import SwiftUI
import WhatCableCore
import WidgetKit

// MARK: - Main entry view for static widget (small + medium + large)

struct CableWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: CableWidgetEntry

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.ports.isEmpty {
            switch family {
            case .systemSmall:
                SmallWidgetView(port: resolveSmallPort(snapshot))
            case .systemMedium:
                MediumWidgetView(ports: resolveFilteredPorts(snapshot))
            case .systemLarge:
                LargeWidgetView(ports: resolveFilteredPorts(snapshot))
            default:
                MediumWidgetView(ports: resolveFilteredPorts(snapshot))
            }
        } else {
            EmptyStateView()
        }
    }

    private func resolveSmallPort(_ snapshot: WidgetSnapshot) -> WidgetSnapshot.PortEntry {
        if let pinned = entry.configuration.selectedPort,
            let match = snapshot.ports.first(where: { String($0.id) == pinned.id })
        {
            return match
        }
        return mostInteresting(snapshot.ports)
    }

    private func resolveFilteredPorts(_ snapshot: WidgetSnapshot) -> [WidgetSnapshot.PortEntry] {
        if let selected = entry.configuration.selectedPorts, !selected.isEmpty {
            let ids = Set(selected.map(\.id))
            let filtered = snapshot.ports.filter { ids.contains(String($0.id)) }
            if !filtered.isEmpty { return filtered }
        }

        let nonEmpty = snapshot.ports.filter { $0.status != .empty }
        return nonEmpty.isEmpty ? snapshot.ports : nonEmpty
    }
}

// MARK: - Small: single most interesting port

struct SmallWidgetView: View {
    let port: WidgetSnapshot.PortEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: port.iconName)
                    .font(.title2)
                    .foregroundStyle(port.status.color)
                Spacer()
                if port.deviceCount > 0 {
                    DeviceCountBadge(count: port.deviceCount)
                }
            }

            if let watts = port.chargerWatts {
                Text("\(watts)W")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(port.status.color)
                Text(port.headline)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
            } else {
                Text(port.headline)
                    .font(.headline)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if port.recentPower.count >= 2 {
                PowerSparkline(samples: port.recentPower, color: port.status.color)
                    .frame(height: 20)
            }
        }
    }
}

// MARK: - Medium: single-port full-width or multi-port columns

struct MediumWidgetView: View {
    let ports: [WidgetSnapshot.PortEntry]

    var body: some View {
        if ports.count == 1, let port = ports.first {
            MediumSinglePortView(port: port)
        } else {
            MediumMultiPortView(ports: ports)
        }
    }
}

struct MediumSinglePortView: View {
    let port: WidgetSnapshot.PortEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: port.iconName)
                        .font(.title2)
                        .foregroundStyle(port.status.color)
                    if let watts = port.chargerWatts {
                        Text("\(watts)W")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(port.status.color)
                    }
                    if port.deviceCount > 0 {
                        DeviceCountBadge(count: port.deviceCount)
                    }
                }
                Text(port.headline)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(port.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if port.recentPower.count >= 2 {
                PowerSparkline(samples: port.recentPower, color: port.status.color)
                    .frame(width: 80, height: 40)
            }
        }
    }
}

struct MediumMultiPortView: View {
    let ports: [WidgetSnapshot.PortEntry]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(ports.prefix(4).enumerated()), id: \.element.id) { index, port in
                if index > 0 {
                    Divider().padding(.vertical, 4)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Image(systemName: port.iconName)
                        .font(.title3)
                        .foregroundStyle(port.status.color)
                    if let watts = port.chargerWatts {
                        Text("\(watts)W")
                            .font(.system(.callout, design: .rounded, weight: .bold))
                            .foregroundStyle(port.status.color)
                    }
                    Text(port.headline)
                        .font(.caption2)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if port.deviceCount > 0 {
                        DeviceCountBadge(count: port.deviceCount, compact: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
        }
    }
}

// MARK: - Large: all ports with detail

struct LargeWidgetView: View {
    let ports: [WidgetSnapshot.PortEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "cable.connector.horizontal")
                    .foregroundStyle(.secondary)
                Text("WhatCable")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 8)

            ForEach(Array(ports.prefix(6).enumerated()), id: \.element.id) { index, port in
                if index > 0 {
                    Divider().padding(.vertical, 4)
                }
                LargePortRow(port: port)
            }
            Spacer(minLength: 0)
        }
    }
}

struct LargePortRow: View {
    let port: WidgetSnapshot.PortEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: port.iconName)
                .font(.title3)
                .foregroundStyle(port.status.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(port.headline)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    if let watts = port.chargerWatts {
                        Text("\(watts)W")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(port.status.color)
                            .layoutPriority(1)
                    }
                }
                Text(port.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            if port.recentPower.count >= 2 {
                PowerSparkline(samples: port.recentPower, color: port.status.color)
                    .frame(width: 50, height: 20)
            }
            if port.deviceCount > 0 {
                DeviceCountBadge(count: port.deviceCount, compact: true)
            }
        }
    }
}

// MARK: - Device count badge

struct DeviceCountBadge: View {
    let count: Int
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: count == 1 ? "laptopcomputer" : "square.stack.3d.up")
                .font(compact ? .caption2 : .caption)
            Text("\(count)")
                .font(compact ? .caption2 : .caption)
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Power sparkline

struct PowerSparkline: View {
    let samples: [Double]
    var color: Color = .yellow

    var body: some View {
        GeometryReader { geo in
            let path = sparklinePath(in: geo.size)
            ZStack {
                path.stroke(color, lineWidth: 1.4)
                path.fill(color.opacity(0.15))
            }
        }
    }

    private func sparklinePath(in size: CGSize) -> Path {
        var path = Path()
        guard samples.count >= 2, size.width > 0, size.height > 0 else { return path }
        let minV = samples.min() ?? 0
        let maxV = samples.max() ?? 1
        let range = max(maxV - minV, 0.5)
        let stepX = size.width / CGFloat(samples.count - 1)
        let points: [CGPoint] = samples.enumerated().map { idx, value in
            let normalized = (value - minV) / range
            let y = size.height - CGFloat(normalized) * size.height
            return CGPoint(x: CGFloat(idx) * stepX, y: y)
        }
        path.move(to: CGPoint(x: 0, y: size.height))
        path.addLine(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cable.connector.horizontal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(String(localized: "No cable data", bundle: _coreLocalizedBundle))
                .font(.headline)
            Text(
                String(
                    localized: "Open WhatCable to start monitoring.", bundle: _coreLocalizedBundle)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Status color mapping

extension WidgetSnapshot.Status {
    var color: Color {
        switch self {
        case .empty: return .secondary
        case .charging: return .yellow
        case .batteryFull: return .green
        case .dataDevice: return .blue
        case .thunderboltCable: return .purple
        case .displayCable: return .teal
        case .unknown: return .orange
        }
    }
}

// MARK: - Most interesting port selection

func mostInteresting(_ ports: [WidgetSnapshot.PortEntry]) -> WidgetSnapshot.PortEntry {
    ports.sorted { a, b in
        let aRank = a.status.interestRank
        let bRank = b.status.interestRank
        if aRank != bRank { return aRank > bRank }
        return a.id < b.id
    }.first
        ?? WidgetSnapshot.PortEntry(
            id: 0,
            portName: "USB-C",
            status: .empty,
            headline: "Nothing connected",
            subtitle: "Plug a cable in to see what it can do.",
            topBullet: nil,
            iconName: "powerplug",
            deviceCount: 0
        )
}

extension WidgetSnapshot.Status {
    fileprivate var interestRank: Int {
        switch self {
        case .thunderboltCable: return 5
        case .displayCable: return 4
        case .dataDevice: return 3
        case .charging: return 2
        case .batteryFull: return 2
        case .unknown: return 1
        case .empty: return 0
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    CableStatusWidget()
} timeline: {
    CableWidgetEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    CableStatusWidget()
} timeline: {
    CableWidgetEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    CableStatusWidget()
} timeline: {
    CableWidgetEntry.placeholder
}

#Preview("Empty", as: .systemMedium) {
    CableStatusWidget()
} timeline: {
    CableWidgetEntry(date: Date(), snapshot: nil, configuration: CableWidgetIntent())
}
