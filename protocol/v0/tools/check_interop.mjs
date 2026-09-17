// Independently verifies the public attestation path and private commitment ladder.
// No Python code is executed. This is NOT a second behavioural classifier.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {hash,enc,dec,verifyAttested} from './verify_attested.mjs';
const B=x=>Buffer.from(x,'hex'),cat=(...v)=>Buffer.concat(v);
const v=JSON.parse(fs.readFileSync(process.argv[2]||new URL('../vectors/interchange.json',import.meta.url),'utf8'));
const objects=new Map(Object.entries(v.objects).map(([h,x])=>{const raw=B(x);assert.equal(hash(raw).toString('hex'),h);return [h,raw];}));
const def=B(fs.readFileSync(new URL('../manifests/protocol.cbor.hex',import.meta.url),'utf8').trim());assert.equal(hash(def).toString('hex'),v.protocol_sha256);
const names=JSON.parse(fs.readFileSync(new URL('../docs/FEATURE_NAMES.json',import.meta.url),'utf8'));
let publicChecks=0;
for(let x of v.cases){let got=verifyAttested(objects.get(x.bundle),objects.get(x.document),objects.get(x.policy),B(x.policy_pin),def,names);assert.equal(got.status,x.expected_class_v,x.id+': '+JSON.stringify(got));if(got.status==='TEST-ONLY'){
 for(let k of ['outcome','claim','scope','ranges','author'])assert.deepEqual(got[k],x.expected_public[k],x.id+': '+k);
 for(let k of ['document','proof','release'])assert.equal(got[k],x.expected_public[k].sha256);}
 publicChecks++;}
for(let x of v.canonical_cbor_hex)assert.deepEqual(enc(dec(B(x))),B(x));
for(let x of v.reject_cbor_hex)assert.throws(()=>dec(B(x)));
function tree(a){if(!a.length)return hash(Buffer.alloc(0));if(a.length===1)return a[0];let k=1;while(k*2<a.length)k*=2;return hash(cat(Buffer.from([1]),tree(a.slice(0,k)),tree(a.slice(k))));}
const leaves=v.merkle.leaves_hex.map(B);v.merkle.prefix_roots_hex.forEach((r,i)=>assert.deepEqual(tree(leaves.slice(0,i)),B(r)));
const l=v.ladder,disclosure=dec(objects.get(l.disclosures)),logs=disclosure.get('logs');assert.equal(logs.length,1);const openings=logs[0].get('openings');assert.equal(openings.length,l.count);
const leafs=openings.map((o,i)=>{assert.equal(o.get('index'),i);dec(o.get('event'));return hash(cat(Buffer.from([0]),enc(['HWP/0:event',B(l.start.sha256),i,o.get('salt'),o.get('event')])));});assert.deepEqual(tree(leafs),B(l.root_hex));
const ev=openings.map(o=>dec(o.get('event'))),header=ev[0],terminal=ev.at(-1);assert.equal(header.get('adapter'),'hwp-a-v0-cbor/1');assert.equal(header.get('kind'),'header');assert.equal(terminal.get('kind'),'end');
let obs=[],tx=[];for(let [i,w]of ev.slice(1,-1).entries()){assert.equal(w.get('value').get('seq'),i);assert(['observation','transaction'].includes(w.get('kind')));(w.get('kind')==='observation'?obs:tx).push(w.get('value'));}
let record=new Map([['id',header.get('id')],['language',header.get('language')],['resolution_us',header.get('resolution_us')],['paths',header.get('paths')],['observations',obs],['transactions',tx],['final_text',terminal.get('final_text')]]);
assert.deepEqual(enc(record),objects.get(l.record));assert.deepEqual(Buffer.from(record.get('final_text'),'utf8'),objects.get(l.document));
const salt=disclosure.get('lineage_salts').at(-1).get('salt');assert.deepEqual(hash(enc(['HWP/0:lineage',salt,objects.get(l.lineage)])),B(l.computed.lineage));
for(let o of l.selected_openings){let cursor=0;function climb(i,n){if(n===1)return B(o.leaf_hex);let k=1;while(k*2<n)k*=2;let sub=i<k?climb(i,k):climb(i-k,n-k),sibling=B(o.path_hex[cursor++]);return hash(cat(Buffer.from([1]),...(i<k?[sub,sibling]:[sibling,sub])));}assert.deepEqual(climb(o.index,l.count),B(l.root_hex));assert.equal(cursor,o.path_hex.length);}
console.log(JSON.stringify({status:'PASS',node:process.version,public_cases:publicChecks,canonical_cbor:v.canonical_cbor_hex.length,rejected_cbor:v.reject_cbor_hex.length,private_event_commitments:openings.length,normalized_records:1,lineage_commitments:1,inclusion_paths:l.selected_openings.length,scope:'Independent class-V attestation verifier and binding-layer checks; no independent behavioural recomputation.'}));
