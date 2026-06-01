#if !canImport(Darwin)
import Foundation

// WhatCable's ~180 user-facing strings are written as
// `String(localized: "…", bundle: _coreLocalizedBundle)`, using Foundation's
// `String(localized:bundle:)` to look the text up in a specific `.lproj`
// bundle for live language switching (see `setCoreLocale(_:)`).
//
// The Foundation that ships with the Linux Swift toolchain has neither
// `String(localized:)` nor `String.LocalizationValue`, so those call sites
// don't compile. These shims provide matching initializers that take the
// (already string-interpolated) text directly and return it as-is — i.e. the
// default catalog. Localization/live language switching is therefore a no-op
// on Linux; the CLI and GUI render in English. This keeps every call site
// compiling unchanged rather than rewriting 180 of them behind `#if`.
//
// The first argument is typed `String` (not Foundation's `LocalizationValue`),
// which the literal and interpolated call sites satisfy directly, and which
// avoids any dependency on the missing localization types.
extension String {
    init(localized key: String, bundle _: Bundle?) {
        self = key
    }

    init(localized key: String) {
        self = key
    }
}
#endif
