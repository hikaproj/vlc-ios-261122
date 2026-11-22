//
//  UltimateWaveformFTS5Database.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  SQLite3 FTS5 Full-Text Search Database for Video Subtitles, Section Memos, and Tags.
//

import Foundation
import SQLite3

public struct AnnotationResult: Identifiable, Sendable {
    public let id: Int64
    public let mediaId: String
    public let startTime: Double
    public let endTime: Double
    public let title: String
    public let content: String
    public let tags: String
    
    public init(id: Int64, mediaId: String, startTime: Double, endTime: Double, title: String, content: String, tags: String) {
        self.id = id
        self.mediaId = mediaId
        self.startTime = startTime
        self.endTime = endTime
        self.title = title
        self.content = content
        self.tags = tags
    }
}

public final class UltimateWaveformFTS5Database: @unchecked Sendable {
    
    public static let shared = UltimateWaveformFTS5Database()
    
    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "org.videolan.vlc.ultimate.fts5.db", qos: .userInitiated)
    
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
        let dbDirectory = appSupport.appendingPathComponent("VLCUltimateEngine", isDirectory: true)
        try? FileManager.default.createDirectory(at: dbDirectory, withIntermediateDirectories: true)
        
        let dbURL = dbDirectory.appendingPathComponent("annotations_fts5.sqlite")
        
        if sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            return
        }
        
        // Create FTS5 Virtual Table for Subtitles & Section Memos with unicode61 tokenizer
        let createTableSQL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS MediaAnnotations USING fts5(
            media_id,
            start_time,
            end_time,
            title,
            content,
            tags,
            tokenize = 'unicode61 remove_diacritics 2'
        );
        """
        
        sqlite3_exec(db, createTableSQL, nil, nil, nil)
    }
    
    // MARK: - Insert Annotation / Subtitle Cue
    
    public func insertAnnotation(
        mediaId: String,
        startTime: Double,
        endTime: Double,
        title: String,
        content: String,
        tags: String
    ) {
        dbQueue.sync {
            let sql = "INSERT INTO MediaAnnotations(media_id, start_time, end_time, title, content, tags) VALUES (?, ?, ?, ?, ?, ?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_text(stmt, 1, (mediaId as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 2, startTime)
            sqlite3_bind_double(stmt, 3, endTime)
            sqlite3_bind_text(stmt, 4, (title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (content as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 6, (tags as NSString).utf8String, -1, nil)
            
            sqlite3_step(stmt)
        }
    }
    
    // MARK: - Full-Text Search Query
    
    public func searchAnnotations(query: String, mediaId: String? = nil) -> [AnnotationResult] {
        return dbQueue.sync {
            var results: [AnnotationResult] = []
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            
            // FTS5 MATCH query with rank ordering
            let sql: String
            if let mId = mediaId {
                sql = "SELECT rowid, media_id, start_time, end_time, title, content, tags FROM MediaAnnotations WHERE media_id = ? AND MediaAnnotations MATCH ? ORDER BY rank LIMIT 100;"
            } else {
                sql = "SELECT rowid, media_id, start_time, end_time, title, content, tags FROM MediaAnnotations WHERE MediaAnnotations MATCH ? ORDER BY rank LIMIT 100;"
            }
            
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            
            if let mId = mediaId {
                sqlite3_bind_text(stmt, 1, (mId as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (query as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_text(stmt, 1, (query as NSString).utf8String, -1, nil)
            }
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                let rowid = sqlite3_column_int64(stmt, 0)
                let mId = String(cString: sqlite3_column_text(stmt, 1))
                let start = sqlite3_column_double(stmt, 2)
                let end = sqlite3_column_double(stmt, 3)
                let title = String(cString: sqlite3_column_text(stmt, 4))
                let content = String(cString: sqlite3_column_text(stmt, 5))
                let tags = String(cString: sqlite3_column_text(stmt, 6))
                
                results.append(AnnotationResult(
                    id: rowid,
                    mediaId: mId,
                    startTime: start,
                    endTime: end,
                    title: title,
                    content: content,
                    tags: tags
                ))
            }
            return results
        }
    }
    
    // MARK: - Retrieve All Annotations for Current Media
    
    public func getAnnotations(for mediaId: String) -> [AnnotationResult] {
        return dbQueue.sync {
            var results: [AnnotationResult] = []
            let sql = "SELECT rowid, media_id, start_time, end_time, title, content, tags FROM MediaAnnotations WHERE media_id = ? ORDER BY start_time ASC;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_text(stmt, 1, (mediaId as NSString).utf8String, -1, nil)
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                let rowid = sqlite3_column_int64(stmt, 0)
                let mId = String(cString: sqlite3_column_text(stmt, 1))
                let start = sqlite3_column_double(stmt, 2)
                let end = sqlite3_column_double(stmt, 3)
                let title = String(cString: sqlite3_column_text(stmt, 4))
                let content = String(cString: sqlite3_column_text(stmt, 5))
                let tags = String(cString: sqlite3_column_text(stmt, 6))
                
                results.append(AnnotationResult(
                    id: rowid,
                    mediaId: mId,
                    startTime: start,
                    endTime: end,
                    title: title,
                    content: content,
                    tags: tags
                ))
            }
            return results
        }
    }
}
