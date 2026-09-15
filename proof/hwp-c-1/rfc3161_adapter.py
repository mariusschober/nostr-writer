"""Detached RFC3161 verification, not HWP certification or lifetime validation.

The caller supplies CA anchors, permitted policy OIDs and validation time from
an independent trust decision. This adapter does not retrieve revocation data.
"""
from __future__ import annotations
import datetime as dt
import hashlib
import subprocess
import tempfile
from pathlib import Path
from asn1crypto import cms, tsp
from hwp_crypto import Reject, require, octets, integer


def verify_token(token:bytes, data:bytes, ca_pem:bytes, validation_time:int,
                 allowed_policy_oids:set[str], expected_nonce:int|None=None) -> dict:
    octets(token); octets(data); octets(ca_pem); integer(validation_time)
    require(bool(allowed_policy_oids),'timestamp-policy-not-selected')
    try:
        ci=cms.ContentInfo.load(token,strict=True)
        require(ci.dump()==token and ci['content_type'].native=='signed_data','timestamp-cms')
        sd=ci['content']; enc=sd['encap_content_info']
        require(enc['content_type'].native=='tst_info','timestamp-content-type')
        info=enc['content'].parsed
        require(isinstance(info,tsp.TSTInfo),'timestamp-tst-info')
        original_tst=info.dump()
        require(info.dump(force=True)==original_tst,'timestamp-tst-der')
        extensions=info['extensions'].native or []
        require(not any(e.get('critical',False) for e in extensions),'timestamp-critical-extension')
        require(info['version'].native=='v1','timestamp-version')
        policy=info['policy'].dotted
        require(policy in allowed_policy_oids,'timestamp-policy-oid')
        imprint=info['message_imprint']; alg=imprint['hash_algorithm']['algorithm'].native
        require(alg in ('sha256','sha512'),'timestamp-hash-algorithm')
        require(imprint['hashed_message'].native==hashlib.new(alg,data).digest(),'timestamp-message-imprint')
        if expected_nonce is not None:
            integer(expected_nonce,0,(1<<256)-1); require(info['nonce'].native==expected_nonce,'timestamp-nonce')
        when=info['gen_time'].native
        require(when.tzinfo is not None,'timestamp-timezone')
        epoch=dt.datetime(1970,1,1,tzinfo=dt.timezone.utc)
        delta=when-epoch; micros=delta.days*86400_000000+delta.seconds*1_000000+delta.microseconds
        accuracy=info['accuracy'].native
        error=None
        if accuracy is not None:
            sec=accuracy.get('seconds') or 0; millis=accuracy.get('millis') or 0; us=accuracy.get('micros') or 0
            integer(sec)
            if accuracy.get('millis') is not None: integer(millis,1,999)
            if accuracy.get('micros') is not None: integer(us,1,999)
            error=sec*1_000000+millis*1000+us
        with tempfile.TemporaryDirectory(prefix='hwp-rfc3161-') as td:
            p=Path(td); (p/'token.der').write_bytes(token); (p/'data.bin').write_bytes(data); (p/'anchors.pem').write_bytes(ca_pem)
            proc=subprocess.run(['openssl','ts','-verify','-token_in','-in',str(p/'token.der'),'-data',str(p/'data.bin'),'-CAfile',str(p/'anchors.pem'),'-attime',str(validation_time)],capture_output=True,timeout=15,check=False)
            require(proc.returncode==0,'timestamp-signature-or-chain')
        return {'status':'VALID-TIMESTAMP','object_sha256':hashlib.sha256(data).hexdigest(),'hash_algorithm':alg,'policy_oid':policy,'gen_time_us':micros,'accuracy_us':error,'existence_upper_bound_us':None if error is None else micros+error,'certificate_validation_time':validation_time,'revocation':'not-assessed','hwp_composition_inference':None}
    except Reject: raise
    except (ValueError,TypeError,KeyError,OverflowError,subprocess.SubprocessError,OSError) as e:
        raise Reject('timestamp-parse-or-backend') from e
