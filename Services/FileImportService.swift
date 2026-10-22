import Foundation

struct FileImportPlan {
    let passwordPrompt: String?
    let read: (String?) throws -> ParsedLink
}

enum FileImportError: Error, LocalizedError {
    case unsupported
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "GlassOTP can't read this file. Supported: GlassOTP backups, 2FAS, Aegis, Authenticator Pro, Bitwarden (.json or .csv), Steam Desktop Authenticator and text files with otpauth:// links."
        case .tooLarge:
            return "This file is too large to be an authenticator export."
        }
    }
}

enum FileImportService {
    static let fileTypes = ["glassotp", "maFile", "mafile", "json", "2fas", "authpro", "bin", "csv", "txt"]
    static let backupPrompt = "Enter password"
    static let steamPrompt = "Enter the Steam Desktop Authenticator encryption passkey"
    static let twoFASPrompt = "Enter the 2FAS backup password"
    static let aegisPrompt = "Enter the Aegis vault password"
    static let authenticatorProPrompt = "Enter the Authenticator Pro backup password"

    private static let maxFileSize = 10 * 1024 * 1024

    static func plan(for url: URL) throws -> FileImportPlan {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return try folderPlan(url)
        }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxFileSize else { throw FileImportError.tooLarge }
        let data = try Data(contentsOf: url)

        if (try? JSONDecoder().decode(BackupContainer.self, from: data)) != nil {
            return FileImportPlan(passwordPrompt: backupPrompt) { password in
                ParsedLink(tokens: try BackupService.import(data: data, password: password ?? ""), unsupported: 0)
            }
        }
        if SteamImport.isMaFile(data) {
            return FileImportPlan(passwordPrompt: nil) { _ in
                ParsedLink(tokens: [try SteamImport.token(fromMaFile: data)], unsupported: 0)
            }
        }
        if let json = ExternalImport.jsonObject(data), let plan = jsonPlan(json) {
            return plan
        }
        if AuthenticatorProImport.isEncryptedBackup(data) {
            return FileImportPlan(passwordPrompt: authenticatorProPrompt) { password in
                try AuthenticatorProImport.readEncrypted(data, password: password)
            }
        }
        if url.pathExtension.lowercased() == SteamImport.fileExtension, SteamImport.looksEncrypted(data) {
            throw SteamImportError.encryptedNeedsFolder
        }
        if let text = String(data: data, encoding: .utf8) {
            if BitwardenImport.matchesCSV(text) {
                return FileImportPlan(passwordPrompt: nil) { _ in try BitwardenImport.readCSV(text) }
            }
            if !LinkListImport.links(in: text).isEmpty {
                return FileImportPlan(passwordPrompt: nil) { _ in try LinkListImport.read(text) }
            }
        }
        throw FileImportError.unsupported
    }

    private static func jsonPlan(_ json: [String: Any]) -> FileImportPlan? {
        if TwoFASImport.matches(json) {
            return FileImportPlan(passwordPrompt: TwoFASImport.isEncrypted(json) ? twoFASPrompt : nil) { password in
                try TwoFASImport.read(json, password: password)
            }
        }
        if AegisImport.matches(json) {
            return FileImportPlan(passwordPrompt: AegisImport.isEncrypted(json) ? aegisPrompt : nil) { password in
                try AegisImport.read(json, password: password)
            }
        }
        if AuthenticatorProImport.matches(json) {
            return FileImportPlan(passwordPrompt: nil) { _ in try AuthenticatorProImport.read(json) }
        }
        if BitwardenImport.matches(json) {
            return FileImportPlan(passwordPrompt: nil) { _ in try BitwardenImport.read(json) }
        }
        return nil
    }

    private static func folderPlan(_ folder: URL) throws -> FileImportPlan {
        guard SteamImport.hasAccounts(in: folder) else { throw FileImportError.unsupported }
        let encrypted = SteamImport.manifest(in: folder)?.isEncrypted ?? false
        return FileImportPlan(passwordPrompt: encrypted ? steamPrompt : nil) { passkey in
            try SteamImport.readFolder(folder, passkey: passkey)
        }
    }
}
