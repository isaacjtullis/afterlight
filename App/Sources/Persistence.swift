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
