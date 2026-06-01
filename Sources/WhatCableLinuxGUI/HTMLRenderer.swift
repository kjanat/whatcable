import Foundation
import WhatCableCore

/// Renders a `CableSnapshot` into a self-contained HTML page. There is no
/// AppKit/WidgetKit on Linux, so the "GUI" is a local browser dashboard: the
/// same per-port `PortSummary` cards the menu bar app shows, styled with
/// inline CSS and auto-refreshed by the page itself. All data comes from
/// WhatCableCore, so the Linux GUI and CLI always agree.
enum HTMLRenderer {
    /// Render a complete HTML dashboard page for the provided CableSnapshot.
    ///
    /// The generated document includes per-port cards (or an empty-state message if no ports),
    /// an auto-refresh meta tag set to `refreshSeconds`, a footer timestamp, and a link to `/snapshot.json`.
    /// - Parameters:
    ///   - snapshot: The CableSnapshot whose data populates the dashboard content.
    ///   - refreshSeconds: Number of seconds for the page auto-refresh meta tag.
    /// - Returns: A string containing the full HTML document for the live dashboard.
    static func page(_ snapshot: CableSnapshot, refreshSeconds: Int = 2) -> String {
        let cards = snapshot.ports.map { card(for: $0, snapshot: snapshot) }.joined(separator: "\n")
        let body =
            snapshot.ports.isEmpty
            ? #"<div class="empty">No USB-C ports found at <code>/sys/class/typec</code>.</div>"#
            : cards

        return """
            <!DOCTYPE html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="refresh" content="\(refreshSeconds)">
            <title>WhatCable</title>
            <style>\(css)</style>
            </head>
            <body>
            <header>
              <h1>WhatCable</h1>
              <div class="sub">What can this USB-C cable actually do? · live view</div>
            </header>
            <main>
            \(body)
            </main>
            <footer>
              <span>Updated \(timestamp()) · auto-refresh \(refreshSeconds)s</span>
              <a href="/snapshot.json">JSON</a>
            </footer>
            </body>
            </html>
            """
    }

    /// Produce a JSON string that matches the CLI snapshot output for the provided `CableSnapshot`.
    /// - Returns: A JSON string representing the provided snapshot in the CLI format; returns `"{}"` if rendering fails.
    static func json(_ snapshot: CableSnapshot) -> String {
        (try? JSONFormatter.render(
            ports: snapshot.ports,
            sources: snapshot.powerSources,
            identities: snapshot.identities,
            showRaw: false,
            adapter: snapshot.adapter,
            thunderboltSwitches: snapshot.thunderboltSwitches,
            isDesktopMac: snapshot.isDesktopMac,
            batteryFullyCharged: snapshot.batteryFullyCharged,
            federatedIdentities: snapshot.federatedIdentities,
            usb3Transports: snapshot.usb3Transports,
            trmTransports: snapshot.trmTransports,
            cioCapabilities: snapshot.cioCapabilities,
            usbDevices: snapshot.usbDevices,
            displayPorts: snapshot.displayPorts
        )) ?? "{}"
    }

    /// Render an HTML card for a single USB‑C port from the given snapshot.
    /// - Parameters:
    ///   - port: The port to render.
    ///   - snapshot: The snapshot providing context (power sources, identities, devices, adapters, etc.) used to populate the card.
    /// - Returns: An HTML `<section>` as a `String` representing the port card, with text content HTML‑escaped and ready for inclusion in the dashboard page.
    private static func card(for port: AppleHPMInterface, snapshot: CableSnapshot) -> String {
        let summary = PortSummary(
            port: port,
            sources: snapshot.powerSources,
            identities: snapshot.identities,
            devices: snapshot.usbDevices,
            thunderboltSwitches: snapshot.thunderboltSwitches,
            federatedIdentities: snapshot.federatedIdentities,
            usb3Transports: snapshot.usb3Transports,
            adapter: snapshot.adapter
        )
        let bullets = summary.bullets
            .map { "<li>\(escape($0))</li>" }
            .joined()
        let title = escape(port.portDescription ?? port.serviceName)
        let bulletBlock = bullets.isEmpty ? "" : "<ul>\(bullets)</ul>"
        return """
            <section class="card \(statusClass(summary.status))">
              <div class="port">\(title)</div>
              <div class="headline">\(escape(summary.headline))</div>
              <div class="subtitle">\(escape(summary.subtitle))</div>
              \(bulletBlock)
            </section>
            """
    }

    /// Map a `PortSummary.Status` value to the corresponding CSS class name used for port cards.
    /// - Parameter status: The port status to convert into a CSS class suffix.
    /// - Returns: The CSS class string that represents `status` (for example, `"s-charging"` for charging).
    private static func statusClass(_ status: PortSummary.Status) -> String {
        switch status {
        case .empty: return "s-empty"
        case .charging: return "s-charging"
        case .batteryFull: return "s-full"
        case .dataDevice: return "s-data"
        case .thunderboltCable: return "s-tb"
        case .displayCable: return "s-display"
        case .unknown: return "s-unknown"
        }
    }

    /// Formats the current local time using the `HH:mm:ss` pattern.
    /// - Returns: A string containing the current local time formatted as `HH:mm:ss`.
    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    /// Escape characters in a string for safe interpolation into HTML.
    /// - Parameters:
    ///   - s: The input text to escape.
    /// - Returns: The input string with `&`, `<`, `>`, and `"` replaced by their HTML entity equivalents (`&amp;`, `&lt;`, `&gt;`, `&quot;`).
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let css = """
        :root { color-scheme: light dark; }
        * { box-sizing: border-box; }
        body { font: 15px/1.5 -apple-system, system-ui, "Segoe UI", Roboto, sans-serif;
               margin: 0; background: #f5f5f7; color: #1d1d1f; }
        @media (prefers-color-scheme: dark) { body { background: #1c1c1e; color: #f5f5f7; } }
        header { padding: 24px 28px 8px; }
        h1 { margin: 0; font-size: 22px; }
        .sub { color: #8a8a8e; font-size: 13px; }
        main { display: grid; gap: 14px; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
               padding: 16px 28px 28px; }
        .card { background: rgba(127,127,127,.08); border: 1px solid rgba(127,127,127,.18);
                border-radius: 12px; padding: 16px 18px; }
        .card { border-left: 4px solid #8a8a8e; }
        .s-charging { border-left-color: #34c759; }
        .s-full     { border-left-color: #34c759; }
        .s-data     { border-left-color: #0a84ff; }
        .s-tb       { border-left-color: #5e5ce6; }
        .s-display  { border-left-color: #bf5af2; }
        .s-empty    { border-left-color: #c7c7cc; opacity: .7; }
        .port { font-size: 12px; text-transform: uppercase; letter-spacing: .04em; color: #8a8a8e; }
        .headline { font-size: 17px; font-weight: 600; margin: 2px 0 4px; }
        .subtitle { color: #8a8a8e; font-size: 13px; }
        ul { margin: 10px 0 0; padding-left: 18px; }
        li { margin: 2px 0; }
        .empty { padding: 28px; color: #8a8a8e; }
        footer { display: flex; justify-content: space-between; padding: 8px 28px 24px;
                 color: #8a8a8e; font-size: 12px; }
        footer a { color: #0a84ff; text-decoration: none; }
        code { background: rgba(127,127,127,.15); padding: 1px 5px; border-radius: 4px; }
        """
}
