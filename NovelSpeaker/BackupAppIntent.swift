//
//  BackupAppIntent.swift
//  NovelSpeaker
//
//  ショートカット/Siri からことせかいのバックアップを生成する App Intent。
//  保存先や世代管理はショートカット側で行い、この Intent は生成した ZIP を返す。
//

import AppIntents
import Foundation
import UniformTypeIdentifiers

@available(iOS 17.0, *)
struct CreateNovelSpeakerBackupIntent: AppIntent {
    static var title = LocalizedStringResource("BackupAppIntent_CreateBackup_Title")
    static var description = IntentDescription(LocalizedStringResource("BackupAppIntent_CreateBackup_Description"))

    /// true の場合はダウンロード済みの小説本文もバックアップに含める。
    /// 定期実行では、ショートカット側でこの値を選択して保存する。
    @Parameter(title: LocalizedStringResource("BackupAppIntent_CreateBackup_IncludeStoryContent"), default: true)
    var withAllStoryContent: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let backupURL = try await createBackup()

        // CreateBackupData は一時ディレクトリに ZIP を生成する。
        // Intent の完了後も「ファイルに保存」等の後続アクションから読めるよう、
        // IntentFile の自動削除は行わない。
        let backupType = UTType("com.limuraproducts.novelspeaker.backupdataziputi") ?? .zip
        var file = IntentFile(
            fileURL: backupURL,
            filename: backupURL.lastPathComponent,
            type: backupType
        )
        file.removedOnCompletion = false

        return .result(value: file)
    }

    private func createBackup() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let backupURL = NovelSpeakerUtility.CreateBackupData(
                    withAllStoryContent: withAllStoryContent,
                    progress: nil
                ) else {
                    continuation.resume(throwing: CreateNovelSpeakerBackupError.creationFailed)
                    return
                }

                continuation.resume(returning: backupURL)
            }
        }
    }
}

private enum CreateNovelSpeakerBackupError: LocalizedError {
    case creationFailed

    var errorDescription: String? {
        switch self {
        case .creationFailed:
            return String(localized: "BackupAppIntent_CreateBackup_Failed")
        }
    }
}

@available(iOS 17.0, *)
struct NovelSpeakerAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateNovelSpeakerBackupIntent(),
            phrases: [
                "\(.applicationName)でバックアップを作成",
                "Create a backup in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("BackupAppIntent_CreateBackup_ShortTitle"),
            systemImageName: "archivebox"
        )
    }
}
