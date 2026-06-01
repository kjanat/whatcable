import Dispatch
import Foundation
import WhatCableCore
import WhatCableLinuxBackend

#if canImport(Glibc)
import Glibc
#endif

// whatcable-gui — the Linux graphical front-end.
//
// macOS ships a SwiftUI/AppKit menu bar app; Linux has no equivalent native
// toolkit in this package's dependency set, so the GUI is a local browser
// dashboard. This binary starts a loopback-only web server that renders the
// same per-port cards the menu bar popover shows (via WhatCableCore's
// PortSummary), then opens the page in the user's default browser.

/// Prints the command-line usage and available options for the `whatcable-gui` tool.
///
/// The printed help text includes the application version and tagline, a short
/// description of the tool, usage syntax, and the supported CLI options.
func printHelp() {
    print(
        """
        whatcable-gui \(AppInfo.version) -- \(AppInfo.tagline)

        Opens a live USB-C cable dashboard in your browser, backed by a local
        web server (127.0.0.1 only). The same data is available from the
        `whatcable` CLI.

        Usage: whatcable-gui [options]

        Options:
          --port N       Listen on port N (default 8787)
          --no-open      Don't launch a browser; just print the URL
          --version      Print version and exit
          -h, --help     Show this help and exit
        """)
}

let args = Array(CommandLine.arguments.dropFirst())
if args.contains("-h") || args.contains("--help") {
    printHelp()
    exit(0)
}
if args.contains("--version") {
    print(AppInfo.version)
    exit(0)
}

var port: UInt16 = 8787
if let i = args.firstIndex(of: "--port"), i + 1 < args.count, let p = UInt16(args[i + 1]) {
    port = p
}
let autoOpen = !args.contains("--no-open")

let provider = makeDefaultSnapshotProvider()

/// Obtains the latest cable snapshot from the default provider, blocking the current thread until the provider completes.
/// - Returns: A `Result<CableSnapshot, Error>` containing the snapshot on success, or the provider error on failure.
func blockingSnapshot() -> Result<CableSnapshot, Error> {
    let sem = DispatchSemaphore(value: 0)
    var result: Result<CableSnapshot, Error> = .failure(LinuxBackendError.typeCClassUnavailable)
    Task {
        do { result = .success(try await provider.snapshot()) } catch { result = .failure(error) }
        sem.signal()
    }
    sem.wait()
    return result
}

// Preflight: surface the actual backend error (not a hardcoded one) clearly
// instead of serving a permanently empty page.
if case .failure(let error) = blockingSnapshot() {
    FileHandle.standardError.write(Data("whatcable-gui: \(error)\n".utf8))
    exit(1)
}

let server = HTTPServer(port: port) { request in
    let snapshot: CableSnapshot
    switch blockingSnapshot() {
    case .success(let value):
        snapshot = value
    case .failure(let error):
        return HTTPServer.Response(
            status: "503 Service Unavailable",
            contentType: "text/plain; charset=utf-8",
            body: "WhatCable: could not read a snapshot: \(error)"
        )
    }
    switch request.path {
    case "/snapshot.json":
        return .json(HTMLRenderer.json(snapshot))
    case "/", "/index.html":
        return .html(HTMLRenderer.page(snapshot))
    default:
        return .notFound()
    }
}

do {
    try server.start()
} catch {
    FileHandle.standardError.write(Data("whatcable-gui: \(error)\n".utf8))
    exit(1)
}

let url = "http://127.0.0.1:\(port)/"
print("WhatCable GUI running at \(url)")
print("Press Ctrl+C to stop.")

if autoOpen {
    openInBrowser(url)
}

server.serveForever()

/// Tries to open the specified URL in a desktop web browser using common Linux launchers.
/// Attempts `xdg-open`, then `gio open`, then `sensible-browser`, and returns after the first successful attempt. Child process output is suppressed and launcher failures are ignored; if all attempts fail the function returns without reporting an error.
/// - Parameter url: The URL to open (for example, `http://127.0.0.1:8787/`).
func openInBrowser(_ url: String) {
    for launcher in ["xdg-open", "gio", "sensible-browser"] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = launcher == "gio" ? ["gio", "open", url] : [launcher, url]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return
        } catch {
            continue
        }
    }
}
