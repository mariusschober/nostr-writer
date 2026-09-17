import Foundation
import CryptoKit

public enum HWPMerkle {
    public static let maximumEvents = 1_000_000
    public static func digest(_ bytes: Data) -> Data { Data(SHA256.hash(data: bytes)) }
    private static func node(_ left: Data, _ right: Data) -> Data { digest(Data([1]) + left + right) }
    private static func split(_ count: Int) -> Int {
        var result = 1
        while result <= (count - 1) / 2 { result *= 2 }
        return result
    }
    private static func rootOfValidated(_ leaves: ArraySlice<Data>) throws -> Data {
        try Task.checkCancellation()
        if leaves.isEmpty { return digest(Data()) }
        if leaves.count == 1 { return leaves.first! }
        let count = split(leaves.count)
        return try node(rootOfValidated(leaves.prefix(count)), rootOfValidated(leaves.dropFirst(count)))
    }
    public static func root(_ leaves: [Data]) throws -> Data {
        guard leaves.count <= maximumEvents, leaves.allSatisfy({ $0.count == 32 }) else { throw HWPReject("tree-size") }
        return try rootOfValidated(leaves[...])
    }
    public static func leaf(startDigest: Data, index: Int, salt: Data, event: Data) throws -> Data {
        guard startDigest.count == 32, salt.count == 32 else { throw HWPReject("byte-string-length") }
        guard (0..<maximumEvents).contains(index) else { throw HWPReject("integer-domain") }
        _ = try HWPCBOR.decode(event)
        return try digest(Data([0]) + HWPCBOR.encode(.array([
            .text("HWP/0:event"), .bytes(startDigest), .unsigned(UInt64(index)), .bytes(salt), .bytes(event)
        ])))
    }
    public static func inclusion(_ leaves: [Data], index: Int) throws -> [Data] {
        guard leaves.count <= maximumEvents, leaves.indices.contains(index), leaves.allSatisfy({ $0.count == 32 }) else { throw HWPReject("integer-domain") }
        func walk(_ items: ArraySlice<Data>, _ i: Int) throws -> [Data] {
            try Task.checkCancellation()
            if items.count == 1 { return [] }
            let k = split(items.count)
            if i < k { return try walk(items.prefix(k), i) + [rootOfValidated(items.dropFirst(k))] }
            return try walk(items.dropFirst(k), i-k) + [rootOfValidated(items.prefix(k))]
        }
        return try walk(leaves[...], index)
    }
    public static func verifyInclusion(leaf: Data, index: Int, count: Int, path: [Data], root: Data) throws -> Bool {
        guard (1...maximumEvents).contains(count), (0..<count).contains(index), leaf.count == 32,
              root.count == 32, path.count <= 32, path.allSatisfy({ $0.count == 32 }) else { return false }
        var cursor = 0
        func walk(_ i: Int, _ n: Int) throws -> Data {
            try Task.checkCancellation()
            if n == 1 { return leaf }
            let k = split(n)
            let sub = try i < k ? walk(i,k) : walk(i-k,n-k)
            guard cursor < path.count else { throw HWPReject("inclusion-truncated") }
            let sibling = path[cursor]; cursor += 1
            return i < k ? node(sub,sibling) : node(sibling,sub)
        }
        do { let result = try walk(index,count); return cursor == path.count && result == root }
        catch is HWPReject { return false }
    }
    public static func consistency(_ leaves: [Data], oldCount: Int) throws -> [Data] {
        guard leaves.count <= maximumEvents, (1...max(1,leaves.count)).contains(oldCount), !leaves.isEmpty,
              leaves.allSatisfy({ $0.count == 32 }) else { throw HWPReject("integer-domain") }
        func sub(_ m: Int, _ items: ArraySlice<Data>, known: Bool) throws -> [Data] {
            try Task.checkCancellation()
            if m == items.count { return try known ? [] : [rootOfValidated(items)] }
            let k = split(items.count)
            if m <= k { return try sub(m,items.prefix(k),known: known) + [rootOfValidated(items.dropFirst(k))] }
            return try sub(m-k,items.dropFirst(k),known: false) + [rootOfValidated(items.prefix(k))]
        }
        return try sub(oldCount,leaves[...],known: true)
    }
    public static func verifyConsistency(oldCount: Int, newCount: Int, oldRoot: Data, newRoot: Data, path: [Data]) throws -> Bool {
        guard (0...maximumEvents).contains(oldCount), (oldCount...maximumEvents).contains(newCount),
              oldRoot.count == 32, newRoot.count == 32, path.count <= 32,
              path.allSatisfy({ $0.count == 32 }) else { return false }
        if oldCount == 0 { return oldRoot == digest(Data()) && path.isEmpty && (newCount > 0 || newRoot == oldRoot) }
        if oldCount == newCount { return oldRoot == newRoot && path.isEmpty }
        var fn = oldCount - 1, sn = newCount - 1
        while fn & 1 != 0 { fn >>= 1; sn >>= 1 }
        var first: Data, second: Data, cursor: Int
        if fn == 0 { first = oldRoot; second = oldRoot; cursor = 0 }
        else {
            guard let initial = path.first else { return false }
            first = initial; second = initial; cursor = 1
        }
        for sibling in path.dropFirst(cursor) {
            try Task.checkCancellation()
            guard sn != 0 else { return false }
            if fn & 1 != 0 || fn == sn {
                first = node(sibling,first); second = node(sibling,second)
                while fn != 0 && fn & 1 == 0 { fn >>= 1; sn >>= 1 }
            } else { second = node(second,sibling) }
            fn >>= 1; sn >>= 1
        }
        return sn == 0 && first == oldRoot && second == newRoot
    }
    public static func lineageCommitment(salt: Data, lineage: Data) throws -> Data {
        guard salt.count == 32 else { throw HWPReject("byte-string-length") }
        return try digest(HWPCBOR.encode(.array([.text("HWP/0:lineage"), .bytes(salt), .bytes(lineage)])))
    }
}
