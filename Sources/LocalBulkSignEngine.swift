//
//  LocalBulkSignEngine.swift
//  mSign
//
//  High-throughput, on-device signing coordinator. It deliberately keeps all
//  signing local: no VPS/API is involved. The engine combines bounded batch
//  concurrency, a persistent content-addressed result cache, one shared
//  certificate/profile staging area per batch, and a reusable workspace root.
//

import Foundation
import CryptoKit

nonisolated struct LocalBulkSignJob: Identifiable, Sendable {
    let id: UUID
    let ipaURL: URL
    let options: SignOptions

    init(id: UUID = UUID(), ipaURL: URL, options: SignOptions = .none) {
        self.id = id
        self.ipaURL = ipaURL
        self.options = options
    }
}

nonisolated struct LocalBulkSignResult: Identifiable, Sendable {
    let id: UUID
    let ipaURL: URL
    let result: Result<SignOutcome, Error>
    let duration: TimeInterval
    let cacheHit: Bool

    var succeeded: Bool {
        if case .success = result { return true }
        return false
    }
}

nonisolated struct LocalBulkStatistics: Sendable {
    let total: Int
    let completed: Int
    let cacheHits: Int
    let failures: Int
    let elapsed: TimeInterval
}

private struct CachedSignArtifact: Codable, Sendable {
    let name: String
    let bundleID: String
    let version: String
    let entitlements: [String: String]
    let sizeBytes: Int64
}

actor LocalSigningLimiter {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.available = max(1, limit)
    }

    func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            available += 1
        }
    }
}

actor LocalSigningCache {
    private let root: URL
    private let maxBytes: Int64 = 2 * 1024 * 1024 * 1024

    init() {
        root = AppPaths.dir("ZSignCache").appendingPathComponent("results", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func load(key: String) -> SignOutcome? {
        let fm = FileManager.default
        let ipa = root.appendingPathComponent("\(key).ipa")
        let meta = root.appendingPathComponent("\(key).json")
        guard fm.fileExists(atPath: ipa.path),
              let data = try? Data(contentsOf: meta),
              let cached = try? JSONDecoder().decode(CachedSignArtifact.self, from: data) else {
            return nil
        }

        let output = fm.temporaryDirectory
            .appendingPathComponent("cache-\(UUID().uuidString)-signed")
            .appendingPathExtension("ipa")
        do {
            try fm.copyItem(at: ipa, to: output)
            // Touch both cache files so the trim pass behaves like a lightweight LRU.
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: ipa.path)
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: meta.path)
            return SignOutcome(
                ipaURL: output,
                name: cached.name,
                bundleID: cached.bundleID,
                version: cached.version,
                entitlements: cached.entitlements,
                sizeBytes: cached.sizeBytes
            )
        } catch {
            try? fm.removeItem(at: ipa)
            try? fm.removeItem(at: meta)
            return nil
        }
    }

    func store(key: String, outcome: SignOutcome) {
        let fm = FileManager.default
        let cachedIPA = root.appendingPathComponent("\(key).ipa")
        let cachedMeta = root.appendingPathComponent("\(key).json")
        let tmpIPA = root.appendingPathComponent("\(key).tmp-\(UUID().uuidString).ipa")
        let tmpMeta = root.appendingPathComponent("\(key).tmp-\(UUID().uuidString).json")

        do {
            try fm.copyItem(at: outcome.ipaURL, to: tmpIPA)
            let metadata = CachedSignArtifact(
                name: outcome.name,
                bundleID: outcome.bundleID,
                version: outcome.version,
                entitlements: outcome.entitlements,
                sizeBytes: outcome.sizeBytes
            )
            try JSONEncoder().encode(metadata).write(to: tmpMeta, options: .atomic)
            try? fm.removeItem(at: cachedIPA)
            try? fm.removeItem(at: cachedMeta)
            try fm.moveItem(at: tmpIPA, to: cachedIPA)
            try fm.moveItem(at: tmpMeta, to: cachedMeta)
            trimIfNeeded()
        } catch {
            try? fm.removeItem(at: tmpIPA)
            try? fm.removeItem(at: tmpMeta)
        }
    }

    private func trimIfNeeded() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        var entries: [(url: URL, size: Int64, date: Date)] = []
        var total: Int64 = 0
        for url in files where url.pathExtension == "ipa" {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let date = values?.contentModificationDate ?? .distantPast
            entries.append((url, size, date))
            total += size
        }
        guard total > maxBytes else { return }
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard total > maxBytes else { break }
            try? fm.removeItem(at: entry.url)
            try? fm.removeItem(at: entry.url.deletingPathExtension().appendingPathExtension("json"))
            total -= entry.size
        }
    }
}

nonisolated enum LocalBulkSignEngine {
    /// Adaptive outer concurrency. ZSign itself can parallelize independent
    /// bundle nodes, so the outer pool is intentionally conservative.
    static var recommendedWorkerCount: Int {
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let memoryGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
        let memoryCap: Int
        switch memoryGB {
        case 0..<4: memoryCap = 1
        case 4..<8: memoryCap = 2
        case 8..<16: memoryCap = 3
        default: memoryCap = 4
        }
        return max(1, min(4, max(1, cores / 2), memoryCap))
    }

    static func sign(
        jobs: [LocalBulkSignJob],
        material: CertMaterial,
        maxConcurrent: Int? = nil,
        onProgress: (@Sendable (Int, Int, LocalBulkSignJob, LocalBulkSignResult) -> Void)? = nil,
        onLog: (@Sendable (String) -> Void)? = nil,
        onStatistics: (@Sendable (LocalBulkStatistics) -> Void)? = nil
    ) async -> [LocalBulkSignResult] {
        guard !jobs.isEmpty else { return [] }

        let limit = max(1, min(maxConcurrent ?? recommendedWorkerCount, jobs.count))
        let limiter = LocalSigningLimiter(limit: limit)
        let cache = LocalSigningCache()
        let total = jobs.count
        let progress = ProgressCounter()
        let startedAt = Date()
        let batchRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("msign-batch-\(UUID().uuidString)", isDirectory: true)
        let stagedRoot = batchRoot.appendingPathComponent("signing-context", isDirectory: true)
        try? FileManager.default.createDirectory(at: stagedRoot, withIntermediateDirectories: true)

        // Stage certificate/profile exactly once for the complete batch. They are
        // read-only inputs and can safely be shared by concurrent signing jobs.
        let staged: StagedSigningMaterial?
        do {
            let p12 = stagedRoot.appendingPathComponent("cert.p12")
            let prov = stagedRoot.appendingPathComponent("profile.mobileprovision")
            try material.p12.write(to: p12, options: .atomic)
            try material.provision.write(to: prov, options: .atomic)
            staged = StagedSigningMaterial(p12URL: p12, provisionURL: prov)
        } catch {
            staged = nil
            onLog?(">>> Bulk: could not create shared signing context; jobs will stage locally.")
        }

        defer { try? FileManager.default.removeItem(at: batchRoot) }

        return await withTaskGroup(of: LocalBulkSignResult.self, returning: [LocalBulkSignResult].self) { group in
            for job in jobs {
                group.addTask {
                    let start = Date()
                    await limiter.acquire()

                    do {
                        // Hashing is deliberately done once per job and includes the
                        // signing context/options, making cached results safe to reuse.
                        let cacheKey = try Self.cacheKey(for: job, material: material)
                        if let cached = await cache.load(key: cacheKey) {
                            let result = LocalBulkSignResult(
                                id: job.id, ipaURL: job.ipaURL,
                                result: .success(cached),
                                duration: Date().timeIntervalSince(start),
                                cacheHit: true
                            )
                            let completed = await progress.next()
                            onProgress?(completed, total, job, result)
                            onLog?(">>> Bulk: cache hit \(job.ipaURL.lastPathComponent)")
                            await limiter.release()
                            return result
                        }

                        var options = job.options
                        // Dylib mutation and concurrent console capture are unsafe to
                        // combine with aggressive parallelism. The engine keeps the
                        // existing safety behavior intact.
                        if options.injectDylibs.isEmpty {
                            options.parallelSigning = true
                        }
                        let output = try await ZsignSigner.signDetached(
                            ipaURL: job.ipaURL,
                            material: material,
                            options: options,
                            workspaceRoot: batchRoot,
                            stagedMaterial: staged,
                            onLog: nil
                        )
                        await cache.store(key: cacheKey, outcome: output)
                        let result = LocalBulkSignResult(
                            id: job.id, ipaURL: job.ipaURL,
                            result: .success(output),
                            duration: Date().timeIntervalSince(start),
                            cacheHit: false
                        )
                        let completed = await progress.next()
                        onProgress?(completed, total, job, result)
                        onLog?(">>> Bulk: completed \(job.ipaURL.lastPathComponent) in \(String(format: "%.2f", result.duration))s")
                        await limiter.release()
                        return result
                    } catch {
                        let result = LocalBulkSignResult(
                            id: job.id, ipaURL: job.ipaURL,
                            result: .failure(error),
                            duration: Date().timeIntervalSince(start),
                            cacheHit: false
                        )
                        let completed = await progress.next()
                        onProgress?(completed, total, job, result)
                        onLog?(">>> Bulk: failed \(job.ipaURL.lastPathComponent): \(error.localizedDescription)")
                        await limiter.release()
                        return result
                    }
                }
            }

            var results: [LocalBulkSignResult] = []
            results.reserveCapacity(jobs.count)
            for await result in group { results.append(result) }
            let order: [UUID: Int] = Dictionary(uniqueKeysWithValues: jobs.enumerated().map { ($0.element.id, $0.offset) })
            let sorted = results.sorted {
                (order[$0.id] ?? 0) < (order[$1.id] ?? 0)
            }
            let cacheHits = sorted.filter(\.cacheHit).count
            let failures = sorted.filter { !$0.succeeded }.count
            onStatistics?(LocalBulkStatistics(total: total, completed: total, cacheHits: cacheHits, failures: failures, elapsed: Date().timeIntervalSince(startedAt)))
            return sorted
        }
    }

    private static func cacheKey(for job: LocalBulkSignJob, material: CertMaterial) throws -> String {
        var hasher = SHA256()
        try update(&hasher, file: job.ipaURL)
        hasher.update(data: material.p12)
        hasher.update(data: material.provision)
        hasher.update(data: Data(material.password.utf8))
        hasher.update(data: Data(material.name.utf8))
        hasher.update(data: Data(job.options.performanceFingerprint().utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func update(_ hasher: inout SHA256, file: URL) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
    }

    actor ProgressCounter {
        private var value = 0
        func next() -> Int { value += 1; return value }
        func value() -> Int { value }
    }
}
