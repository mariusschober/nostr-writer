"""Generate public synthetic interchange vectors, never real HWP certificates."""
from pathlib import Path
import json,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT),str(ROOT/'tests')]
import hwp_crypto as h
from fixtures import make,check,seed

def main():
    f=make(author=True,identity=True)
    st=f['store']; env=h.decode(st.get(f['appraisal'])); ph,uh,payload,sig=env.value
    key=st.get(f['keys']['evaluator'])
    signature={'seed_hex':seed('evaluator').hex(),'cose_key_hex':key.hex(), 'cose_sign1_hex':st.get(f['appraisal']).hex(),'protected_hex':ph.hex(),'payload_hex':payload.hex(),'external_aad_hex':h.AAD.hex(),'sig_structure_hex':h.encode(['Signature1',ph,h.AAD,payload]).hex(),'signature_hex':sig.hex()}
    sd=seed('merkle-start'); private=[]; leaves=[]
    for i in range(7):
        event=h.encode({'kind':'fixture','index':i,'text':'Café '+str(i)}); salt=seed('merkle-salt'+str(i))
        hh=h.leaf(sd,i,salt,event); leaves.append(hh)
        private.append({'index':i,'event_hex':event.hex(),'salt_hex':salt.hex(),'leaf_hex':hh.hex()})
    bad=['1817','a2616201616102','a2616101616102','9f01ff','fb3ff0000000000000','616180','62c080','d80180']
    v={'version':'hwp-c/1','warning':'PUBLIC SYNTHETIC FIXTURES ONLY. Known private seeds, no real human evidence, no approved real detector.',
       'signature':signature,'bundle':{'hex':f['bundle'].hex(),'document_hex':f['document'].hex(),'external_test_policy_hex':f['policy_bytes'].hex(),'external_test_policy_sha256':f['policy_digest'].hex(),'root_proof':h.diagnostic_json(f['proof']),'expected':h.diagnostic_json(check(f))},
       'merkle':{'start_digest_hex':sd.hex(),'leaves':private,'prefix_roots_hex':[h.tree_root(leaves[:i]).hex() for i in range(8)],'inclusions':[{'index':i,'count':7,'path_hex':[x.hex() for x in h.inclusion(leaves,i)]} for i in range(7)],'consistencies':[{'old_count':m,'new_count':7,'path_hex':[x.hex() for x in h.consistency(leaves,m)]} for m in range(1,8)]},
       'reject_cbor_hex':bad}
    for b in bad:
        try:h.decode(bytes.fromhex(b))
        except h.Reject:pass
        else:raise AssertionError('negative CBOR vector accepted')
    (ROOT/'vectors/interchange.json').write_text(json.dumps(v,sort_keys=True,separators=(',',':'))+'\n',encoding='utf-8')
    print(json.dumps({'file':'vectors/interchange.json','sha256':h.digest((ROOT/'vectors/interchange.json').read_bytes()).hex(),'bytes':(ROOT/'vectors/interchange.json').stat().st_size},sort_keys=True))

if __name__=='__main__': main()
