import Foundation
import Darwin
import WriterHWP

private struct InputFailure: Error {}
private struct Options {
    var proof: String?, document: String?, policy: String?, pin: String?, disclosure: String?
    var recompute = false
    init(_ arguments: [String]) throws {
        var index = 0, positional: [String] = [], seen: Set<String> = [], mode: String?
        while index < arguments.count {
            let option = arguments[index]; index += 1
            if !option.hasPrefix("--") { positional.append(option); continue }
            guard seen.insert(option).inserted else { throw InputFailure() }
            if option == "--recompute" { recompute = true; continue }
            guard ["--proof", "--source", "--policy", "--policy-pin", "--disclosure", "--mode"].contains(option), index < arguments.count else { throw InputFailure() }
            let value = arguments[index]; index += 1
            guard !value.hasPrefix("--") else { throw InputFailure() }
            switch option {
            case "--proof": proof = value
            case "--source": document = value
            case "--policy": policy = value
            case "--policy-pin": pin = value
            case "--disclosure": disclosure = value
            case "--mode": mode = value
            default: throw InputFailure()
            }
        }
        if !positional.isEmpty {
            guard positional.count == 2, proof == nil, document == nil else { throw InputFailure() }
            proof = positional[0]; document = positional[1]
        }
        guard proof != nil, document != nil, policy != nil, pin != nil else { throw InputFailure() }
        if let mode {
            guard mode == "V" || mode == "R" else { throw InputFailure() }
            if mode == "R" { recompute = true }
            else if recompute || disclosure != nil { throw InputFailure() }
        }
    }
}

/// Explicit regular files only. O_NONBLOCK prevents FIFOs/devices from hanging
/// before fstat; read-time bounds also catch a file that grows after the stat.
private func read(_ path: String, maximum: Int = HWPCBOR.maximumBytes) throws -> Data {
    let fd = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
    guard fd >= 0 else { throw InputFailure() }; defer { Darwin.close(fd) }
    var stat = Darwin.stat()
    guard fstat(fd, &stat) == 0, (stat.st_mode & S_IFMT) == S_IFREG, stat.st_size >= 0, stat.st_size <= maximum else { throw InputFailure() }
    var result = Data(), buffer = [UInt8](repeating: 0, count: 65_536)
    result.reserveCapacity(Int(stat.st_size))
    while true {
        let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        if count == 0 { return result }
        if count < 0 { if errno == EINTR { continue }; throw InputFailure() }
        guard count <= maximum - result.count else { throw InputFailure() }
        result.append(contentsOf: buffer.prefix(count))
    }
}
private func pin(_ text: String) throws -> Data {
    let bytes = Array(text.utf8)
    guard bytes.count == 64 else { throw InputFailure() }
    return try Data(stride(from: 0, to: bytes.count, by: 2).map { index in
        guard let byte = UInt8(String(decoding: bytes[index..<index+2], as: UTF8.self), radix: 16) else { throw InputFailure() }; return byte
    })
}
private func json(_ value: HWPValue) throws -> Any {
    switch value {
    case .null: return NSNull()
    case .boolean(let b): return b
    case .unsigned(let n): return NSNumber(value: n)
    case .negative(let n): return NSNumber(value: n)
    case .bytes(let raw): return raw.map { String(format: "%02x", $0) }.joined()
    case .text(let raw): return try AlgorithmText(utf8: raw).string
    case .array(let values): return try values.map(json)
    case .map(let entries):
        var result: [String: Any] = [:]
        for entry in entries {
            guard case .text(let key) = entry.key else { throw HWPReject("diagnostic-key") }
            result[String(decoding: key, as: UTF8.self)] = try json(entry.value)
        }
        return result
    default: throw HWPReject("diagnostic-type")
    }
}
private func failure(_ reason: String) -> HWPValue {
    .map([HWPEntry(.text("protocol"), .text("hwp/0")), HWPEntry(.text("status"), .text("NO-VALID-HWP")),
          HWPEntry(.text("outcome"), .text("NOT PROVABLE")), HWPEntry(.text("reason"), .text(reason)), HWPEntry(.text("authorship_inference"), .null)])
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--help"] {
    print("""
    Usage: hwp-verify proof.hwp source.md --policy selected.cbor --policy-pin HEX
                      [--disclosure private.hwp] [--recompute]
    Also accepts --proof PATH --source PATH and --mode V|R.

    The policy pin must be selected independently of the proof. Verification is
    offline; bundled source is never executed. R recomputes the complete evidence.
    V accepts no --disclosure and rejects proofs requiring disclosed recomputation.
    Without --mode, disclosed proofs still require their complete private evidence.
    Exit 0: admitted production proof; 2: TEST-ONLY / NOT PROVABLE; 1: no valid proof.
    The installed default production policy contains no approved releases.
    """)
    exit(0)
}
if arguments == ["--version"] { print("hwp-verify 0.1.0 (native hwp/0, normative revision 0.0.0)"); exit(0) }
let result: HWPValue
do {
    let options = try Options(arguments)
    let privateValue = try options.disclosure.map { try HWPDisclosure.unpack(read($0)) }
    result = try HWPProtocol.verify(bundle: read(options.proof!), document: read(options.document!, maximum: 1024 * 1024),
        policyBytes: read(options.policy!), policyPin: pin(options.pin!), disclosures: privateValue, recompute: options.recompute)
} catch is CancellationError {
    FileHandle.standardError.write(Data("Verification cancelled.\n".utf8)); exit(130)
} catch is InputFailure { result = failure("input-error") }
catch let error as HWPReject { result = failure(error.reason) }
catch { result = failure("verification-unavailable") }
do {
    var output = try JSONSerialization.data(withJSONObject: json(result), options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    output.append(0x0a); FileHandle.standardOutput.write(output)
} catch { FileHandle.standardError.write(Data("Verification result unavailable.\n".utf8)); exit(1) }
exit(result.field("status") == .text("VALID-HWP") ? 0 : result.field("status") == .text("TEST-ONLY") ? 2 : 1)
