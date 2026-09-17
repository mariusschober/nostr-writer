"""Run against unmodified extracted baselines, not the v0 fork."""
import sys,json
from pathlib import Path
# Supply a directory with unmodified extracted a03/ and c1/ archives.
BASE=Path(sys.argv[1]) if len(sys.argv)>1 else Path('baseline-inputs')
sys.path[:0]=[str(BASE/'c1/proof/hwp-c-1'),str(BASE/'c1/proof/hwp-c-1/tests'),str(BASE/'a03/algorithm/v0_3')]
import hwp_crypto as c
import fixtures as old
from hwp_a.fixtures import Builder,TEXT
from hwp_a.replay import replay
out={}
f=old.make(name='prospective')
s=f['store'];r=s.obj(f['release']);r['artifacts']['model']=s.add(b'OTHER SYNTHETIC MODEL');rr=s.put(r)
g=old.change_statement(f,lambda st:st.update(release=rr));g=old.change_policy(g,lambda p:p.update(releases=c.reference_list(p['releases']+[rr])))
out['changed_release_without_resigning_capture_start']=old.check(g)['status']
f=old.make(name='whitespace');s=f['store'];raw=('\u2028'*64).encode();doc=s.add(raw)
events=[{'kind':'header','fixture':True},{'kind':'record','fixture':True},{'kind':'end','document':raw}]
root,_=c.commit_events(f['start'],events,[old.seed(str(i)) for i in range(3)])
e=s.signed(f['end'])[0];e['root']=root;e['count']=3;er=s.add(c.sign(e,old.seed('capture')))
scope=s.put({'v':c.VERSION,'type':'scope','document':doc,'kind':'whole-document','ranges':[{'start':0,'end':len(raw),'origin':['observed',[er]]}]})
g=old.change_statement(f,lambda st:st.update(document=doc,scope=scope,captures=[er],target_capture=er));g['document']=raw
out['line_separator_only_nonvacuity']=old.check(g)['status']
out['capture_end_has_explicit_final_document']='document' in e
b=Builder().type(TEXT);b.time+=1000;b.observation('focus_out',b.time,'out');b.control('navigate',start=0,end=0)
try:replay(b.bundle());out['out_of_focus_native_control_structurally_accepted']=True
except Exception:out['out_of_focus_native_control_structurally_accepted']=False
out['interpretation']='Conditional synthetic fixtures with admitted test keys; no achieved attack on human composition or evaluated capture.'
print(json.dumps(out,sort_keys=True,indent=2))
