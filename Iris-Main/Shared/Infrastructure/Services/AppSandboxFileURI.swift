import Foundation

/// Canonicalizes and resolves file paths under the app sandbox so stored paths survive container changes.
enum AppSandboxFileURI {
    /// App container root (`…/Application/<UUID>`).
    static func appHomeDirectoryURL(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .deletingLastPathComponent()
    }

    /// Prefer `Documents/…` or `Library/…` relative to the app home; otherwise keep the absolute path.
    static func canonicalStoredPath(forFileAt url: URL, fileManager: FileManager = .default) -> String {
        let home = appHomeDirectoryURL(fileManager: fileManager)
        let path = url.standardizedFileURL.path
        let homePath = home.path
        guard path.hasPrefix(homePath + "/") else { return path }
        return String(path.dropFirst(homePath.count + 1))
    }

    /// `true` for filesystem-backed media (not Photos `localIdentifier`).
    static func isLikelySandboxFile(_ storedURI: String) -> Bool {
        if storedURI.hasPrefix("/") { return true }
        return storedURI.hasPrefix("Documents/") || storedURI.hasPrefix("Library/")
    }

    /// Resolves a stored filesystem URI to a file URL if the file exists in the current sandbox.
    static func resolveFileURL(storedURI: String, fileManager: FileManager = .default) -> URL? {
        let fm = fileManager

        if storedURI.hasPrefix("/") {
            if fm.fileExists(atPath: storedURI) {
                return URL(fileURLWithPath: storedURI)
            }
            if let relative = relativeAppPathSuffix(fromAbsolutePath: storedURI) {
                let candidate = appendingRelativePath(relative, to: appHomeDirectoryURL(fileManager: fm))
                if fm.fileExists(atPath: candidate.path) { return candidate }
            }
            return nil
        }

        if storedURI.hasPrefix("Documents/") || storedURI.hasPrefix("Library/") {
            let candidate = appendingRelativePath(storedURI, to: appHomeDirectoryURL(fileManager: fm))
            if fm.fileExists(atPath: candidate.path) { return candidate }
            return nil
        }

        return nil
    }

    /// DB lookup keys for the same on-disk file (legacy absolute vs canonical relative).
    static func lookupCandidateStoredURIs(forStoredURI stored: String, fileManager: FileManager = .default) -> [String] {
        var out: [String] = []
        func append(_ s: String) {
            guard !s.isEmpty, !out.contains(s) else { return }
            out.append(s)
        }

        append(stored)

        if stored.hasPrefix("/") {
            if let rel = relativeAppPathSuffix(fromAbsolutePath: stored) {
                append(rel)
            }
        } else if stored.hasPrefix("Documents/") || stored.hasPrefix("Library/") {
            let url = appendingRelativePath(stored, to: appHomeDirectoryURL(fileManager: fileManager))
            append(url.path)
        }

        return out
    }

    /// Candidates for a file URL about to be linked (dedupe against legacy rows).
    static func lookupCandidateStoredURIs(forFileAt url: URL, fileManager: FileManager = .default) -> [String] {
        let abs = url.standardizedFileURL.path
        let canonical = canonicalStoredPath(forFileAt: url, fileManager: fileManager)
        var out: [String] = []
        for s in [abs, canonical] {
            for c in lookupCandidateStoredURIs(forStoredURI: s, fileManager: fileManager) {
                if !out.contains(c) { out.append(c) }
            }
        }
        return out
    }

    // MARK: - Private

    private static func relativeAppPathSuffix(fromAbsolutePath path: String) -> String? {
        let comps = (path as NSString).pathComponents
        if let idx = comps.firstIndex(of: "Documents") {
            return comps[idx...].joined(separator: "/")
        }
        if let idx = comps.firstIndex(of: "Library") {
            return comps[idx...].joined(separator: "/")
        }
        return nil
    }

    private static func appendingRelativePath(_ relative: String, to home: URL) -> URL {
        var url = home
        for part in relative.split(separator: "/") where !part.isEmpty {
            url = url.appendingPathComponent(String(part), isDirectory: false)
        }
        return url
    }
}
