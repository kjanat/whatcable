import SwiftUI
import WhatCableCore
import WidgetKit

// MARK: - Widget definition

struct PowerMonitorWidget: Widget {
    let kind = "uk.whatcable.whatcable.power-monitor"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PowerTimelineProvider()) { entry in
            PowerMonitorEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(
            Text(String(localized: "Power Monitor", bundle: _coreLocalizedBundle))
        )
        .description(
            Text(
                String(localized: "Battery and charging at a glance.", bundle: _coreLocalizedBundle)
            )
        )
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Entry view dispatcher

struct PowerMonitorEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: PowerMonitorEntry

    var body: some View {
        if let snapshot = entry.snapshot, snapshot.powerState != nil {
            switch family {
            case .systemSmall:
                PowerSmallView(snapshot: snapshot)
            case .systemMedium:
                PowerMediumView(snapshot: snapshot)
            case .systemLarge:
                PowerLargeView(snapshot: snapshot)
            default:
                PowerMediumView(snapshot: snapshot)
            }
        } else {
            PowerEmptyStateView()
        }
    }
}

// MARK: - Small: battery % and charge status

struct PowerSmallView: View {
    let snapshot: WidgetSnapshot

    private var power: WidgetSnapshot.PowerState { snapshot.powerState! }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: batteryIcon)
                    .font(.title2)
                    .foregroundStyle(statusColor)
                Spacer()
                if let watts = power.adapterWatts {
                    Text("\(watts)W")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }

            if power.isDesktopMac {
                Text(String(localized: "Power connected", bundle: _coreLocalizedBundle))
                    .font(.headline)
            } else if let pct = power.batteryPercent {
                Text("\(pct)%")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(batteryColor(pct))
            }

            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if power.recentSystemPower.count >= 2 {
                PowerSparkline(samples: power.recentSystemPower, color: .yellow)
                    .frame(height: 18)
            }
        }
    }

    private var batteryIcon: String {
        if power.isDesktopMac { return "desktopcomputer" }
        if power.isCharging { return "battery.100.bolt" }
        guard let pct = power.batteryPercent else { return "battery.100" }
        if pct <= 25 { return "battery.25" }
        if pct <= 50 { return "battery.50" }
        if pct <= 75 { return "battery.75" }
        return "battery.100"
    }

    private var statusLabel: String {
        if power.isDesktopMac {
            return power.adapterDescription ?? ""
        }
        if power.fullyCharged {
            return String(localized: "Battery full", bundle: _coreLocalizedBundle)
        }
        if power.isCharging {
            return String(localized: "Charging", bundle: _coreLocalizedBundle)
        }
        return String(localized: "On battery", bundle: _coreLocalizedBundle)
    }

    private var statusColor: Color {
        if power.fullyCharged { return .green }
        if power.isCharging { return .yellow }
        return .secondary
    }

    private func batteryColor(_ pct: Int) -> Color {
        if pct <= 20 { return .red }
        if pct <= 50 { return .orange }
        return .primary
    }
}

// MARK: - Medium: battery + charger info side by side

struct PowerMediumView: View {
    let snapshot: WidgetSnapshot

    private var power: WidgetSnapshot.PowerState { snapshot.powerState! }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: power.isDesktopMac ? "desktopcomputer" : "battery.100")
                        .font(.title3)
                        .foregroundStyle(statusColor)
                    if power.isDesktopMac {
                        Text(String(localized: "Power connected", bundle: _coreLocalizedBundle))
                            .font(.headline)
                    } else if let pct = power.batteryPercent {
                        Text("\(pct)%")
                            .font(.system(.title, design: .rounded, weight: .bold))
                    }
                }
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 4) {
                if let watts = power.adapterWatts {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        Text("\(watts)W")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                    }
                }
                if let desc = power.adapterDescription {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let sysW = power.systemPowerInWatts {
                    let formatted = String(format: "%.1f", sysW)
                    let drawFormat = String(localized: "%@W draw", bundle: _coreLocalizedBundle)
                    Text(String(format: drawFormat, formatted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if power.recentSystemPower.count >= 2 {
                    PowerSparkline(samples: power.recentSystemPower, color: .yellow)
                        .frame(height: 18)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
        }
    }

    private var statusLabel: String {
        if power.isDesktopMac {
            return power.adapterDescription ?? ""
        }
        if power.fullyCharged {
            return String(localized: "Battery full", bundle: _coreLocalizedBundle)
        }
        if power.isCharging {
            return String(localized: "Charging", bundle: _coreLocalizedBundle)
        }
        return String(localized: "On battery", bundle: _coreLocalizedBundle)
    }

    private var statusColor: Color {
        if power.fullyCharged { return .green }
        if power.isCharging { return .yellow }
        return .secondary
    }
}

// MARK: - Large: full power dashboard

struct PowerLargeView: View {
    let snapshot: WidgetSnapshot

    private var power: WidgetSnapshot.PowerState { snapshot.powerState! }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.yellow)
                Text(String(localized: "Power Monitor", bundle: _coreLocalizedBundle))
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 8)

            HStack(spacing: 10) {
                Image(systemName: power.isDesktopMac ? "desktopcomputer" : "battery.100")
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    if power.isDesktopMac {
                        Text(String(localized: "Power connected", bundle: _coreLocalizedBundle))
                            .font(.callout)
                            .fontWeight(.semibold)
                    } else if let pct = power.batteryPercent {
                        Text("\(pct)%")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                    }
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let watts = power.adapterWatts {
                Divider().padding(.vertical, 4)
                HStack(spacing: 10) {
                    Image(systemName: "powerplug.portrait.fill")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "\(watts)W charger", bundle: _coreLocalizedBundle))
                            .font(.callout)
                            .fontWeight(.semibold)
                        if let desc = power.adapterDescription {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }

            if power.recentSystemPower.count >= 2 {
                Divider().padding(.vertical, 4)
                HStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        if let sysW = power.systemPowerInWatts {
                            let formatted = String(format: "%.1f", sysW)
                            let systemDrawFormat = String(
                                localized: "%@W system draw", bundle: _coreLocalizedBundle)
                            Text(String(format: systemDrawFormat, formatted))
                                .font(.callout)
                                .fontWeight(.semibold)
                        }
                        PowerSparkline(samples: power.recentSystemPower, color: .orange)
                            .frame(height: 24)
                    }
                    Spacer(minLength: 0)
                }
            }

            if let portWatts = power.perPortWatts, !portWatts.isEmpty {
                Divider().padding(.vertical, 4)
                ForEach(portWatts, id: \.portKey) { portPower in
                    HStack(spacing: 10) {
                        Image(systemName: "cable.connector")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        Text(portPower.portName)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        let portFormatted = String(format: "%.1f", portPower.watts)
                        Text("\(portFormatted)W")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        if portPower.recentSamples.count >= 2 {
                            PowerSparkline(samples: portPower.recentSamples, color: .blue)
                                .frame(width: 40, height: 16)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var statusLabel: String {
        if power.isDesktopMac {
            return power.adapterDescription ?? ""
        }
        if power.fullyCharged {
            return String(localized: "Battery full", bundle: _coreLocalizedBundle)
        }
        if power.isCharging {
            return String(localized: "Charging", bundle: _coreLocalizedBundle)
        }
        return String(localized: "On battery", bundle: _coreLocalizedBundle)
    }

    private var statusColor: Color {
        if power.fullyCharged { return .green }
        if power.isCharging { return .yellow }
        return .secondary
    }
}

// MARK: - Empty state

struct PowerEmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(String(localized: "No power data", bundle: _coreLocalizedBundle))
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

// MARK: - Previews

#Preview("Power Small", as: .systemSmall) {
    PowerMonitorWidget()
} timeline: {
    PowerMonitorEntry.placeholder
}

#Preview("Power Medium", as: .systemMedium) {
    PowerMonitorWidget()
} timeline: {
    PowerMonitorEntry.placeholder
}

#Preview("Power Large", as: .systemLarge) {
    PowerMonitorWidget()
} timeline: {
    PowerMonitorEntry.placeholder
}

#Preview("Power Empty", as: .systemSmall) {
    PowerMonitorWidget()
} timeline: {
    PowerMonitorEntry(date: Date(), snapshot: nil)
}
