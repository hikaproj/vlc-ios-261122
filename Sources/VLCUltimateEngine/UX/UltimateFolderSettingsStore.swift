//
//  UltimateFolderSettingsStore.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Automatic Per-Folder & Per-File Playback Settings Store using SQLite3.
//

import Foundation
import SQLite3
import CryptoKit

public struct FolderPlaybackSettings: Codable, Sendable {
    public var playbackRate: Float
    public var dseeEnabled: Bool
    public var vinylEnabled: Bool
    public var spatialEnabled: Bool
    public var hdrToneMappingEnabled: Bool
    public var anime4kEnabled: Bool
    public var crtEnabled: Bool
    public var subtitleDelayMs: Int
    public var audioDelayMs: Int
    
    public static let `default` = FolderPlaybackSettings(
        playbackRate: 1.0,
        dseeEnabled: true,
        vinylEnabled: false,
        spatialEnabled: false,
        hdrToneMappingEnabled: true,
        anime4kEnabled: true,
        crtEnabled: false,
        subtitleDelayMs: 0,
        audioDelayMs: 0
    )
}

public final class UltimateFolderSettingsStore: @unchecked Sendable {
    
    public static let shared = UltimateFolderSettingsStore()
    
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "org.videolan.vlc.ultimate.folder.settings", qos: .utility)
    
    private init() {
        setupDatabase()
    }
    
    deinit {
        if let database = db {
            sqlite3_close(database)
        }
    }
    
    private func setupDatabase() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("VLCUltimateEngine", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let dbURL = dir.appendingPathComponent("folder_settings.sqlite")
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { return }
        
        let sql = """
        CREATE TABLE IF NOT EXISTS FolderSettings (
            key_hash TEXT PRIMARY KEY,
            settings_json TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }
    
    private func computeHash(for url: URL) -> String {
        let folderPath = url.deletingLastPathComponent().path
        let hash = SHA256.hash(data: folderPath.data(using: .utf8)!)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    public func saveSettings(_ settings: FolderPlaybackSettings, for fileURL: URL) {
        queue.async { [weak self] in
            guard let self = self,
                  let db = self.db,
                  let json = try? JSONEncoder().encode(settings),
                  let jsonStr = String(data: json, encoding: .utf8) else { return }
            
            let key = self.computeHash(for: fileURL)
            let sql = "INSERT OR REPLACE INTO FolderSettings (key_hash, settings_json, updated_at) VALUES (?, ?, ?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (jsonStr as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            
            sqlite3_step(stmt)
        }
    }
    
    public func loadSettings(for fileURL: URL) -> FolderPlaybackSettings {
        return queue.sync {
            guard let db = self.db else { return .default }
            let key = self.computeHash(for: fileURL)
            let sql = "SELECT settings_json FROM FolderSettings WHERE key_hash = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return .default }
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                let jsonStr = String(cString: sqlite3_column_text(stmt, 0))
                if let data = jsonStr.data(using: .utf8),
                   let settings = try? JSONDecoder().decode(FolderPlaybackSettings.self, from: data) {
                    return settings
                }
            }
            return .default
        }
    }
}
