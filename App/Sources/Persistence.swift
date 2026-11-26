import Foundation
import AfterlightCore
import Supabase

/// Reads Supabase settings from Info.plist (filled from Config/Secrets.xcconfig).
enum AppConfig {
    static var supabaseURL: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String, !s.contains("$("),
              let url = URL(string: s), let host = url.host, host.contains(".") else { return nil }
        return url
    }
    static var supabaseKey: String? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String, !s.isEmpty, !s.contains("$(") else { return nil }
        return s
    }
}

/// The on-device save. Always written first; the cloud copy follows.
struct LocalStore {
    var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("afterlight-save.json")
    }
    func load() -> SaveGame? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? Game.decodeSave(d)
    }
    func write(_ data: Data) {
        try? data.write(to: url, options: .atomic)
    }
    func erase() { try? FileManager.default.removeItem(at: url) }
}

/// Snapshots taken at each checkpoint, so the player can go back to any of them (and to the start).
/// Which endings this player has reached. Kept apart from saves, so going back to a checkpoint
/// never loses the record.
struct EndingsStore {
    let key = "afterlight.endings"
    func all() -> [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    func add(_ id: String) { var a = all(); if !a.contains(id) { a.append(id); UserDefaults.standard.set(a, forKey: key) } }
}

struct CheckpointStore {
    struct Entry: Codable, Identifiable {
        var id: String
        var date: Date
        var title: String
        var text: String
        var depth: String
        var pinned: Bool
        var save: Data
    }
    static let keep = 15
    var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("afterlight-checkpoints.json")
    }
    func all() -> [Entry] {
        guard let d = try? Data(contentsOf: url), let e = try? JSONDecoder().decode([Entry].self, from: d) else { return [] }
        return e
    }
    func add(_ e: Entry) {
        var list = all()
        list.insert(e, at: 0)
        // Keep the start pinned; drop the oldest of the rest.
        let pinned = list.filter(\.pinned), rest = list.filter { !$0.pinned }
        list = Array(rest.prefix(Self.keep)) + pinned
        if let d = try? JSONEncoder().encode(list) { try? d.write(to: url, options: .atomic) }
    }
    func erase() { try? FileManager.default.removeItem(at: url) }
}

/// Cloud saves and server-resolved jobs on Supabase. Every call fails soft: the game keeps
/// working offline and catches up later.
actor CloudSync {
    private let client: SupabaseClient?
    private var version = -1
    private var signedIn = false

    init() {
        if let url = AppConfig.supabaseURL, let key = AppConfig.supabaseKey {
            client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        } else {
            client = nil
        }
    }

    var enabled: Bool { client != nil }

    private func ensureSession() async -> Bool {
        guard let client else { return false }
        if signedIn { return true }
        do {
            if (try? await client.auth.session) == nil {
                try await client.auth.signInAnonymously()
            }
            signedIn = true
            return true
        } catch {
            return false
        }
    }

    struct LoadRow: Decodable { let version: Int; let data: String }

    /// The newest cloud save, if any.
    func load() async -> SaveGame? {
        guard await ensureSession(), let client else { return nil }
        do {
            let rows: [LoadRow] = try await client.rpc("load_game").execute().value
            guard let row = rows.first, let d = row.data.data(using: .utf8) else { return nil }
            version = row.version
            return try Game.decodeSave(d)
        } catch {
            return nil
        }
    }

    struct SaveParams: Encodable { let p_data: String; let p_expected_version: Int }

    func save(_ data: Data) async {
        guard await ensureSession(), let client, let json = String(data: data, encoding: .utf8) else { return }
        do {
            let v: Int = try await client.rpc("save_game", params: SaveParams(p_data: json, p_expected_version: version)).execute().value
            version = v
        } catch {
            // Another device saved in between. Last writer wins for now; the local copy is always kept.
            if let v: Int = try? await client.rpc("save_game", params: SaveParams(p_data: json, p_expected_version: -1)).execute().value { version = v }
        }
    }

    struct StartParams: Encodable { let p_id: String; let p_kind: String; let p_title: String; let p_plan: String }

    /// Registers a job; returns the server's start time so the phone clock can't be gamed.
    func startJob(_ plan: JobPlan) async -> Date? {
        guard await ensureSession(), let client else { return nil }
        guard let d = try? JSONEncoder().encode(plan), let json = String(data: d, encoding: .utf8) else { return nil }
        do {
            let epoch: Double = try await client.rpc("start_job", params: StartParams(p_id: plan.id, p_kind: plan.kind.rawValue, p_title: plan.title, p_plan: json)).execute().value
            return Date(timeIntervalSince1970: epoch)
        } catch {
            return nil
        }
    }

    struct ClaimParams: Encodable { let p_id: String }
    struct ClaimResult: Decodable { let completed: Int; let started_epoch: Double; let already_claimed: Bool }

    /// Ends the job on the server and returns how many steps were done. Claiming twice returns the same count.
    func claimJob(id: String) async -> Int? {
        guard await ensureSession(), let client else { return nil }
        do {
            let r: ClaimResult = try await client.rpc("claim_job", params: ClaimParams(p_id: id)).execute().value
            return r.completed
        } catch {
            return nil
        }
    }

    /// Progress so far without ending the job.
    func peekJob(id: String) async -> Int? {
        guard await ensureSession(), let client else { return nil }
        return try? await client.rpc("job_progress", params: ClaimParams(p_id: id)).execute().value
    }
}


/// A copy of the save in the player's iCloud (key-value storage), so progress survives a reinstall
/// and follows them to another device signed in to the same account. Compressed to stay well under the 1 MB limit.
struct ICloudStore {
    private var kv: NSUbiquitousKeyValueStore { .default }
    func save(_ data: Data) {
        guard let z = try? (data as NSData).compressed(using: .lzfse) as Data, z.count < 900_000 else { return }
        kv.set(z, forKey: "save.v1")
        kv.set(Date().timeIntervalSince1970, forKey: "save.at")
        kv.synchronize()
    }
    func load() -> SaveGame? {
        kv.synchronize()
        guard let z = kv.data(forKey: "save.v1"), let d = try? (z as NSData).decompressed(using: .lzfse) as Data else { return nil }
        return try? Game.decodeSave(d)
    }
    func erase() { kv.removeObject(forKey: "save.v1"); kv.synchronize() }
}
