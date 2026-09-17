#!/usr/bin/env python3
"""Materialize pinned HWP sources; optionally regenerate the exact frozen vector.

Development tool only. No networking, package installation, manifest rewriting or
trust/empirical approval. Refuses changed existing files and unsafe archive paths.
"""
from __future__ import annotations
import argparse, hashlib, io, json, lzma, os, subprocess, sys, tarfile, tempfile
from pathlib import Path, PurePosixPath

ARCHIVE_SHA = "84b89a4db5cd647c5fda3450a85c39902d626954ec62a3f535dc8b29c71191c7"
FREEZE_SHA = "c04ded3b82a462aa22a7289a5bcbeccd5719124a4718cb5fbd4f47c297993d88"
PROTOCOL_SHA = "58efebeb46689cfafd597230facda03a9541d423b244d36b84cff35b2fc8c6d4"
VECTOR_SHA = "356a1cea43b4e961176cf52855fa4c2f4808e9d37d59a4c781c3967532b96bbe"
VECTOR_SIZE = 16_161_774
VECTOR = "vectors/interchange.json"
MAX_ARCHIVE = 200_000
MAX_TAR = 2_000_000

def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()

def need(ok: bool, reason: str) -> None:
    if not ok: raise ValueError(reason)

def safe_relative(name: str) -> PurePosixPath:
    p = PurePosixPath(name)
    need(bool(name) and not p.is_absolute() and ".." not in p.parts and "\\" not in name and str(p)==name, "unsafe-source-path")
    return p

def read_transport(repo: Path) -> dict[str, bytes]:
    source = repo / "product/mac/inputs"
    meta = json.loads((source/"protocol-source.json").read_text())
    need(meta["format"] == "writer-frozen-source-transport/1", "transport-version")
    need(meta["archive_sha256"] == ARCHIVE_SHA, "transport-pin")
    chunks=[]; names=set();total=0
    for part in meta["parts"]:
        name=str(safe_relative(part["path"]))
        need(name not in names and "/" not in name,"duplicate-or-nested-part")
        names.add(name);path=source/name
        need(not path.is_symlink(),"symlink-part")
        need(path.stat().st_size==part["size"] and part["size"] <= MAX_ARCHIVE,"part-size")
        total += part["size"];need(total<=MAX_ARCHIVE,"archive-size")
        raw=path.read_bytes();need(digest(raw)==part["sha256"],"part-digest:"+name);chunks.append(raw)
    raw=b"".join(chunks)
    need(len(raw)==meta["archive_size"] and digest(raw)==ARCHIVE_SHA,"archive-identity")
    decoder=lzma.LZMADecompressor()
    expanded=decoder.decompress(raw,max_length=MAX_TAR+1)
    need(len(expanded)<=MAX_TAR and decoder.eof and not decoder.unused_data,"archive-decompression-limit")
    files={};total=0
    with tarfile.open(fileobj=io.BytesIO(expanded),mode="r:") as tf:
        for member in tf:
            name=str(safe_relative(member.name))
            need(member.isfile() and name not in files and member.size<=MAX_TAR,"archive-member")
            total+=member.size;need(total<=MAX_TAR and len(files)<100,"archive-members-limit")
            handle=tf.extractfile(member);need(handle is not None,"archive-member-data")
            files[name]=handle.read()
    need(digest(files["FREEZE.json"])==FREEZE_SHA,"original-freeze-pin")
    need(files["FREEZE.sha256"].decode().split()[0]==FREEZE_SHA,"original-freeze-companion")
    freeze=json.loads(files["FREEZE.json"])
    need(freeze["protocol_definition_sha256"]==PROTOCOL_SHA,"protocol-pin")
    inventory={item["path"]:item for item in freeze["files"]}
    need(len(inventory)==len(freeze["files"]),"duplicate-inventory")
    need(set(files)==(set(inventory)-{VECTOR})|{"FREEZE.json","FREEZE.sha256"},"incomplete-transport")
    for name,blob in files.items():
        if name in inventory:
            f=inventory[name];need(len(blob)==f["size"] and digest(blob)==f["sha256"],"frozen-content:"+name)
    need(inventory[VECTOR]["sha256"]==VECTOR_SHA and inventory[VECTOR]["size"]==VECTOR_SIZE,"vector-pin")
    return files

def safe_destination(root: Path, name: str) -> Path:
    need(not root.parent.is_symlink(),"symlink-protocol-parent")
    relative=safe_relative(name);target=root.joinpath(*relative.parts)
    cursor=target
    while cursor != root.parent:
        need(not cursor.is_symlink(),"symlink-destination")
        if cursor==root:break
        cursor=cursor.parent
    need(root.resolve() in target.resolve().parents,"destination-escape")
    return target

def materialize(repo: Path, extract_only: bool=False) -> dict:
    files=read_transport(repo);root=repo/"protocol/v0"
    # Validate every existing input before writing even one missing file.
    targets={name:safe_destination(root,name) for name in files}
    for name,path in targets.items():
        if path.exists():need(path.is_file() and path.read_bytes()==files[name],"existing-frozen-file-changed:"+name)
    for name,path in targets.items():
        if not path.exists():
            path.parent.mkdir(parents=True,exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=path.parent,delete=False) as temp:
                temp.write(files[name]);temp.flush();os.fsync(temp.fileno());temporary=Path(temp.name)
            try:os.replace(temporary,path)
            finally:temporary.unlink(missing_ok=True)
    if extract_only:return {"status":"SOURCES-MATERIALIZED","files":len(files),"vector":"not checked; run full bootstrap after installing pinned development requirements"}
    vector=safe_destination(root,VECTOR)
    if vector.exists():need(vector.stat().st_size==VECTOR_SIZE and digest(vector.read_bytes())==VECTOR_SHA,"existing-vector-changed")
    else:
        with tempfile.TemporaryDirectory(prefix="writer-hwp-vector-") as tmp:
            candidate=Path(tmp)/"interchange.json"
            subprocess.run([sys.executable,str(root/"tools/generate_vectors.py"),str(candidate)],cwd=root,check=True,timeout=300)
            need(candidate.stat().st_size==VECTOR_SIZE and digest(candidate.read_bytes())==VECTOR_SHA,"regenerated-vector-mismatch")
            vector.parent.mkdir(parents=True,exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=vector.parent,delete=False) as out:
                out.write(candidate.read_bytes());out.flush();os.fsync(out.fileno());temporary=Path(out.name)
            try:os.replace(temporary,vector)
            finally:temporary.unlink(missing_ok=True)
    subprocess.run([sys.executable,str(root/"tools/check_freeze.py")],cwd=root,check=True,timeout=30)
    return {"status":"PASS","files":69,"protocol_definition_sha256":PROTOCOL_SHA,"freeze_sha256":FREEZE_SHA}

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--extract-only",action="store_true")
    args=parser.parse_args();repo=Path(__file__).resolve().parents[1]
    try:print(json.dumps(materialize(repo,args.extract_only),indent=2));return 0
    except (OSError,ValueError,KeyError,lzma.LZMAError,tarfile.TarError,subprocess.SubprocessError) as error:
        print(json.dumps({"status":"FAIL","reason":str(error),"hint":"Use a dedicated Python environment with protocol/v0/requirements.txt; never rebuild frozen manifests."}),file=sys.stderr);return 1
if __name__=="__main__":raise SystemExit(main())
