"""Deterministic, publicly keyed integration vectors. No real human sessions."""
import sys,json,copy
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from hwp0 import core as c, protocol as p, bridge
from hwp0.algorithm.fixtures import Builder,TEXT
from tests.support import make,check,restatement,policy_change,seed

def generate():
    pool={};cases=[]
    def put(raw):
        h=c.digest(raw).hex();pool[h]=raw.hex();return h
    def add(name,f,expected=None,recompute_expected=None):
        got=check(f);full=check(f,recompute=True)
        if expected:assert got['status']==expected,(name,got)
        if recompute_expected:assert full['status']==recompute_expected,(name,full)
        summary={k:c.diagnostic_json(got[k]) for k in ('status','outcome','claim','scope','ranges','author','document','proof','release') if k in got}
        cases.append({'id':name,'bundle':put(f['bundle']),'document':put(f['document']),'policy':put(f['policy_bytes']),
                      'policy_pin':f['policy_pin'].hex(),'disclosures':put(c.encode(f['disclosures'])),
                      'expected_public':summary,'expected_recomputation':full['status'],
                      'expected_class_v':'NO-VALID-HWP' if f['store'].obj(f['statement'])['mode']=='disclosed-v1' else got['status']})
        return f
    for profile in ('keyboard','touch-tap','ime','gesture'):add(profile,make(profile=profile,name=profile),'TEST-ONLY','TEST-ONLY')
    base=add('disclosed',make(mode='disclosed-v1',name='disclosed'),'TEST-ONLY','TEST-ONLY')
    author=add('identified',make(author=True,identity=True,name='identity'),'TEST-ONLY','TEST-ONLY')
    b=Builder('quotation').type(TEXT*2).splice(len(TEXT*2),len(TEXT*2),' SOURCE QUOTATION',source='paste');n=len((TEXT*2).encode())
    add('selected-quotation',make(name='quotation',record=b.record(),scope_ranges=lambda cap:[{'start':0,'end':n,'origin':['observed',[cap]]},{'start':n,'end':len(b.text.encode()),'origin':['excluded','external quotation']}]),'TEST-ONLY','TEST-ONLY')
    parent=make(name='parent',claim='wording-origin');b=Builder('child').control('copy',from_doc='parent',start=0,end=len(parent['record']['final_text']),to=0,parent_text=parent['record']['final_text'])
    add('inherited',make(name='child',claim='wording-origin',record=b.record(),parents=(parent,),scope_ranges=[{'start':0,'end':len(parent['document']),'origin':['inherited',parent['proof'],0,len(parent['document'])]}]),'TEST-ONLY','TEST-ONLY')
    f=make(name='negative-base')
    add('production-denies-fixture',policy_change(f,lambda po:po.update(purpose='production')),'NO-VALID-HWP')
    add('changed-document',dict(f,document=f['document']+b'\n'),'NO-VALID-HWP')
    add('unsupported-zk',restatement(f,lambda st:st.update(mode='zk-v0')),'NO-VALID-HWP')
    add('wrong-policy-pin',dict(f,policy_pin=bytes(32)),'NO-VALID-HWP')
    add('unresigned-statement',restatement(f,lambda st:st.update(nonce=seed('changed')),False),'NO-VALID-HWP')
    from tests.test_protocol import replacement_capture
    lying=Builder('negative-base').splice(0,0,f['record']['final_text'],source='paste').record()
    add('admitted-lying-evaluator',replacement_capture(f,lying),'TEST-ONLY','NO-VALID-HWP')
    # Empirical approval cannot modify the tested operation or upgrade old captures.
    staged=make(name='staging-vector');st=staged['store'];rr=st.obj(staged['release']);dd=st.obj(rr['validation'])
    dd.update(stage='empirical',candidate=staged['release'],reports=[{'role':role,'artifact':st.add(('SYNTHETIC REPORT ONLY '+role).encode())} for role in p.REPORT_ROLES])
    empirical=st.put(dict(rr,stage='empirical',validation=st.put(dd)))
    granted=policy_change(staged,lambda po:po.update(releases=c.reference_list(po['releases']+[empirical])))
    add('empirical-no-retroactive-upgrade',restatement(granted,lambda state:state.update(release=empirical)),'NO-VALID-HWP','NO-VALID-HWP')
    wrong_candidate=st.put(dict(rr,claim='wording-origin'))
    bad=st.put(dict(rr,stage='empirical',validation=st.put(dict(dd,candidate=wrong_candidate))))
    granted=policy_change(staged,lambda po:po.update(releases=c.reference_list(po['releases']+[bad])))
    add('empirical-candidate-mismatch',restatement(granted,lambda state:state.update(release=bad)),'NO-VALID-HWP','NO-VALID-HWP')
    # A full, independently checkable intermediate ladder for one actual execution.
    f=make(name='ladder');store=f['store'];start_body,_=store.signed(f['start'])
    all_leaves=[c.leaf(f['start']['sha256'],o['index'],o['salt'],o['event']) for o in f['openings']]
    selected_indexes=[0,1,2,len(all_leaves)-1]
    ladder={'bundle':put(f['bundle']),'policy':put(f['policy_bytes']),'document':put(f['document']),
            'disclosures':put(c.encode(f['disclosures'])),'lineage':put(f['lineage']),
            'record':put(c.encode(f['record'])),'computed':c.diagnostic_json(f['computed']),
            'start':c.diagnostic_json(f['start']),'end':c.diagnostic_json(f['end']),
            'root_hex':c.tree_root(all_leaves).hex(),'count':len(all_leaves),
            'selected_openings':[dict(index=i,event_hex=f['openings'][i]['event'].hex(),salt_hex=f['openings'][i]['salt'].hex(),leaf_hex=all_leaves[i].hex(),path_hex=[x.hex() for x in c.inclusion(all_leaves,i)]) for i in selected_indexes]}
    small=[c.digest(('node'+str(i)).encode()) for i in range(7)]
    merkle={'leaves_hex':[x.hex() for x in small],'prefix_roots_hex':[c.tree_root(small[:i]).hex() for i in range(8)],
            'consistency':[{'old_count':i,'new_count':7,'path_hex':[x.hex() for x in c.consistency(small,i)]} for i in range(1,8)]}
    primitive=[c.encode(x).hex() for x in [-2**63,-2**32,-1,0,23,24,255,256,2**53,2**64-1,{24:1,-1:2},'é\n']]
    return {'format':'hwp/0-conformance-vectors/1','notice':'Synthetic public fixture keys and machine-generated writing; no Human Writing Proofs issued.',
            'protocol_sha256':c.digest(p.installed()[0]).hex(),'objects':pool,'cases':cases,'ladder':ladder,'merkle':merkle,
            'canonical_cbor_hex':primitive,'reject_cbor_hex':['1800','9fff','a201000100','f90000','0000','61ff','d100']}
if __name__=='__main__':
    raw=json.dumps(generate(),sort_keys=True,ensure_ascii=True,separators=(',',':'))+'\n'
    out=Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'vectors/interchange.json';out.write_text(raw)
    print(c.digest(raw.encode()).hex())
