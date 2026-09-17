import Foundation
import Darwin

let arguments = CommandLine.arguments.dropFirst()
if arguments.elementsEqual(["--help"]) {
    print("Usage: hwp-verify --source <source.md> --proof <proof.hwp> --policy <policy> --mode V|R")
    print("Native verification is unavailable until Stage 04. No proof is accepted by this shell.")
    exit(0)
}
if arguments.elementsEqual(["--version"]) { print("hwp-verify 0.1.0 (Stage 01 interface only)"); exit(0) }
FileHandle.standardError.write(Data("UNSUPPORTED: native HWP verification is not implemented (Stage 04).\n".utf8))
exit(69)
