#!/usr/bin/env swift
//
// Block a release when the SDK version in code is not recorded in
// config-sdk-version.json.
//
// The rule: the version declared in LinkrunnerKit.podspec must be the FIRST
// entry of `sdk_versions` in config-sdk-version.json.
//
//   - A change that does not touch the SDK version passes automatically,
//     because the podspec version already sits at the top of the file.
//   - A change that bumps the real SDK version fails until a matching entry is
//     added, newest-first, to config-sdk-version.json.
//
// Run from the repo root:  swift Scripts/check-sdk-version.swift
// Exits 0 on success, 1 on failure. Foundation only, no dependencies.

import Foundation

let configName = "config-sdk-version.json"

// type -> pattern whose first group is the version. Anchored to the line that
// declares *this package's* version, so a dependency pin elsewhere in the file
// cannot be mistaken for it.
let patterns: [String: String] = [
    "package_json": #"^\s*"version"\s*:\s*"([^"]+)""#,
    "pubspec_yaml": #"^version:\s*(\S+)\s*$"#,
    "podspec": #"^\s*s\.version\s*=\s*['"]([^'"]+)['"]"#,
    "gradle_version_name": #"^\s*versionName\s*["']([^"']+)["']"#,
    "cordova_plugin_xml": #"^\s*<plugin[^>]*?\sversion\s*=\s*"([^"]+)""#,
]

var errors: [String] = []
var warnings: [String] = []

func firstMatch(_ pattern: String, _ text: String, dotAll: Bool = false) -> String? {
    var opts: NSRegularExpression.Options = []
    if dotAll { opts.insert(.dotMatchesLineSeparators) }
    guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let m = re.firstMatch(in: text, options: [], range: range), m.numberOfRanges > 1,
          let r = Range(m.range(at: 1), in: text) else { return nil }
    return String(text[r]).trimmingCharacters(in: .whitespaces)
}

func readVersion(_ file: String, _ kind: String) -> String? {
    guard let pattern = patterns[kind] else {
        errors.append("Unknown version_source type \"\(kind)\" in \(configName).")
        return nil
    }
    guard let text = try? String(contentsOfFile: file, encoding: .utf8) else {
        errors.append("Version manifest \"\(file)\" (from \(configName)) does not exist.")
        return nil
    }
    if kind == "cordova_plugin_xml" {
        return firstMatch(#"<plugin\b[^>]*?\sversion\s*=\s*"([^"]+)""#, text, dotAll: true)
    }
    for line in text.components(separatedBy: .newlines) {
        if let v = firstMatch(pattern, line) { return v }
    }
    return nil
}

/// Sortable key. A prerelease (1.2.0-beta.1) sorts below its release.
func vkey(_ v: String) -> [Int] {
    var nums: [Int] = []
    var current = ""
    for ch in v {
        if ch.isNumber { current.append(ch) }
        else if !current.isEmpty { nums.append(Int(current) ?? 0); current = "" }
    }
    if !current.isEmpty { nums.append(Int(current) ?? 0) }
    nums = Array(nums.prefix(3))
    while nums.count < 3 { nums.append(0) }
    nums.append(v.contains("-") || v.contains("+") ? 0 : 1)
    return nums
}

func isDescending(_ a: String, _ b: String) -> Bool {
    let ka = vkey(a), kb = vkey(b)
    for i in 0..<ka.count where ka[i] != kb[i] { return ka[i] > kb[i] }
    return false
}

func run() -> Int32 {
    let fm = FileManager.default
    guard fm.fileExists(atPath: configName),
          let raw = try? Data(contentsOf: URL(fileURLWithPath: configName)) else {
        print("\(configName) not found in \(fm.currentDirectoryPath).")
        print("Every Linkrunner SDK repo must carry \(configName) at its root.")
        return 1
    }

    guard let obj = try? JSONSerialization.jsonObject(with: raw),
          let cfg = obj as? [String: Any] else {
        print("\(configName) is not valid JSON.")
        return 1
    }

    guard let entries = cfg["sdk_versions"] as? [[String: Any]], !entries.isEmpty else {
        print("\(configName) has no non-empty 'sdk_versions' array.")
        return 1
    }

    guard let src = cfg["version_source"] as? [String: Any],
          let manifest = src["file"] as? String,
          let kind = src["type"] as? String else {
        print("\(configName) is missing the 'version_source' block.")
        print("Expected e.g. \"version_source\": {\"file\": \"LinkrunnerKit.podspec\", \"type\": \"podspec\"}")
        return 1
    }

    let codeVersion = readVersion(manifest, kind)
    if codeVersion == nil && errors.isEmpty {
        errors.append("Could not find a version declaration in \"\(manifest)\".")
    }

    // --- structural checks -------------------------------------------------
    let versions = entries.map { $0["version"] as? String }
    if versions.contains(where: { $0 == nil || $0!.isEmpty }) {
        errors.append("Every entry in \(configName) needs a non-empty 'version'.")
    }
    let present = versions.compactMap { $0 }

    let dupes = Set(present.filter { v in present.filter { $0 == v }.count > 1 }).sorted()
    if !dupes.isEmpty {
        errors.append("\(configName) lists duplicate versions: \(dupes.joined(separator: ", "))")
    }

    let ordered = present.sorted { isDescending($0, $1) }
    if present != ordered {
        errors.append("\(configName) must be ordered newest-first. Expected to start with "
            + "\"\(ordered.first ?? "")\" but found \"\(versions.first.flatMap { $0 } ?? "")\".")
    }

    let top = entries[0]
    let topVersion = top["version"] as? String ?? ""
    if (top["pushed_date"] as? String)?.isEmpty ?? true {
        warnings.append("Latest entry \"\(topVersion)\" has no 'pushed_date'.")
    }
    if (top["description"] as? String)?.isEmpty ?? true {
        warnings.append("Latest entry \"\(topVersion)\" has no 'description'.")
    }

    // --- the core rule -----------------------------------------------------
    if let cv = codeVersion, errors.isEmpty, cv != topVersion {
        if present.contains(cv) {
            errors.append("\(manifest) declares \"\(cv)\", which IS listed in \(configName) "
                + "but not at the top (top is \"\(topVersion)\").\n"
                + "    The newest release must be the first entry of 'sdk_versions'.")
        } else {
            errors.append("\(manifest) declares version \"\(cv)\", but that version is missing "
                + "from \(configName) (top entry is \"\(topVersion)\").\n"
                + "    You bumped the SDK version without recording it. Add this as the FIRST "
                + "entry of 'sdk_versions':\n\n"
                + "      {\n"
                + "        \"version\": \"\(cv)\",\n"
                + "        \"pushed_date\": \"YYYY-MM-DD\",\n"
                + "        \"description\": \"What changed in this release.\"\n"
                + "      }\n")
        }
    }

    // --- mirrors that must not drift ---------------------------------------
    for m in (cfg["version_mirrors"] as? [[String: Any]]) ?? [] {
        guard let mp = m["file"] as? String, let mk = m["type"] as? String,
              FileManager.default.fileExists(atPath: mp) else { continue }
        if let mver = readVersion(mp, mk), let cv = codeVersion, mver != cv {
            errors.append("\(mp) declares \"\(mver)\" but \(manifest) declares \"\(cv)\". "
                + "These must stay in sync.")
        }
    }

    // --- report ------------------------------------------------------------
    let sdk = cfg["sdk"] as? String ?? "SDK"
    for w in warnings { print("warning: \(w)") }
    if !errors.isEmpty {
        print("\nSDK version check failed for \(sdk).\n")
        for e in errors { print("  x \(e)") }
        print("\n  Manifest : \(manifest)")
        print("  Config   : \(configName) (\(entries.count) versions, latest \"\(topVersion)\")")
        return 1
    }

    print("SDK version check passed for \(sdk). \(manifest) declares "
        + "\"\(codeVersion ?? "")\" and it is the latest entry in \(configName) "
        + "(\(entries.count) versions recorded).")
    return 0
}

exit(run())
