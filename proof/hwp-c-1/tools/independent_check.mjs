// Independent standards-layer CBOR/SHA256/COSE/Merkle vector checker.
// This is NOT a second full HWP policy or behavioural verifier.
import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
const file=process.argv[2]||new URL('../vectors/interchange.json',import.meta.url);
const V=JSON.parse(fs.readFileSync(file,'utf8'));
const B=x=>Buffer.from(x,'hex');
const hash=x=>crypto.createHash('sha256').update(x).digest();
const cat=(...xs)=>Buffer.concat(xs);
class Tag{constructor(n,v){this.n=n;this.v=v;}}
function head(m,n){
  assert(Number.isSafeInteger(n)&&n>=0); if(n<24)return Buffer.from([m*32+n]);
  for(const [a,w] of [[24,1],[25,2],[26,4],[27,8]])if(n<2**(w*8)){
    const b=Buffer.alloc(1+w);b[0]=m*32+a;let k=BigInt(n);
    for(let j=w;j>0;j--){b[j]=Number(k&255n);k>>=8n;}return b;
  }throw Error('integer');
}
function enc(x){
  if(x===null)return Buffer.from([246]);if(x===false)return Buffer.from([244]);if(x===true)return Buffer.from([245]);
  if(typeof x==='number')return x>=0?head(0,x):head(1,-1-x);
  if(Buffer.isBuffer(x))return cat(head(2,x.length),x);
  if(typeof x==='string'){const b=Buffer.from(x,'utf8');assert.equal(new TextDecoder('utf-8',{fatal:true}).decode(b),x);return cat(head(3,b.length),b);}
  if(Array.isArray(x))return cat(head(4,x.length),...x.map(enc));
  if(x instanceof Map){const pairs=[...x].map(([k,v])=>[enc(k),enc(v)]).sort((a,b)=>Buffer.compare(a[0],b[0]));return cat(head(5,pairs.length),...pairs.flat());}
  if(x instanceof Tag){assert.equal(x.n,18);return cat(head(6,18),enc(x.v));}throw Error('unsupported');
}
function dec(raw){let p=0,items=0;
 function take(n){assert(n>=0&&n<=raw.length-p);const b=raw.subarray(p,p+n);p+=n;return b;}
 function val(d){assert(d<=32&&++items<=100000);const f=take(1)[0],m=f>>5,a=f&31;
  if(m===7){assert([20,21,22].includes(a));return a===20?false:a===21?true:null;}
  assert(a<=27);let n=a;
  if(a>=24){n=0n;for(const x of take(2**(a-24)))n=(n<<8n)|BigInt(x);assert(n<=BigInt(Number.MAX_SAFE_INTEGER));n=Number(n);assert(n>=(a===24?24:2**(8*2**(a-25))));}
  if(m===0)return n;if(m===1)return -1-n;if(m===2)return take(n);
  if(m===3)return new TextDecoder('utf-8',{fatal:true}).decode(take(n));
  if(m===4){assert(n<=100000);return Array.from({length:n},()=>val(d+1));}
  if(m===5){assert(n<=100000);const out=new Map();let prev=null;
    for(let i=0;i<n;i++){const begin=p,k=val(d+1),kb=raw.subarray(begin,p);assert(typeof k==='string'||(typeof k==='number'&&Number.isInteger(k)));assert(!out.has(k));assert(!prev||Buffer.compare(prev,kb)<0);prev=kb;out.set(k,val(d+1));}return out;}
  assert(m===6&&n===18);return new Tag(n,val(d+1));
 }const out=val(0);assert.equal(p,raw.length);assert.deepEqual(enc(out),raw);return out;
}
const objects=new Map(),bundle=dec(B(V.bundle.hex));assert.equal(bundle.get('v'),'hwp-c/1');
let prev=null;for(const [h,raw]of bundle.get('objects')){assert.deepEqual(hash(raw),h);assert(!prev||Buffer.compare(prev,h)<0);prev=h;objects.set(h.toString('hex'),raw);}
function object(r){const b=objects.get(r.get('sha256').toString('hex'));assert(b);assert.equal(b.length,r.get('size'));assert.deepEqual(hash(b),r.get('sha256'));return dec(b);}
const proof=object(bundle.get('root'));const statement=object(proof.get('statement'));
assert.deepEqual(statement.get('document').get('sha256'),hash(B(V.bundle.document_hex)));
assert.deepEqual(hash(B(V.bundle.external_test_policy_hex)),B(V.bundle.external_test_policy_sha256));
let signatures=0;
function verifyCose(raw){const e=dec(raw);assert(e instanceof Tag&&e.n===18&&e.v.length===4);const [pr,up,pay,sig]=e.v,p=dec(pr);
 assert.deepEqual([...p.keys()].sort((a,b)=>a-b),[1,3,4]);assert.equal(p.get(1),-19);assert.equal(p.get(3),'application/cbor');assert.equal(up.size,0);
 const kraw=objects.get(p.get(4).toString('hex'));assert(kraw);assert.deepEqual(hash(kraw),p.get(4));const k=dec(kraw);
 assert.equal(k.get(1),1);assert.equal(k.get(3),-19);assert.equal(k.get(-1),6);assert.equal(k.get(-2).length,32);
 const spki=cat(B('302a300506032b6570032100'),k.get(-2));const key=crypto.createPublicKey({key:spki,format:'der',type:'spki'});
 const message=enc(['Signature1',pr,Buffer.from('HWP-C/1','ascii'),pay]);assert(crypto.verify(null,message,key,sig));signatures++;return {pr,pay,sig,message};
}
for(const raw of objects.values()){let o;try{o=dec(raw);}catch{continue;}if(o instanceof Tag)verifyCose(raw);}
const s=verifyCose(B(V.signature.cose_sign1_hex));for(const [key,data]of [['protected_hex',s.pr],['payload_hex',s.pay],['signature_hex',s.sig],['sig_structure_hex',s.message]])assert.deepEqual(data,B(V.signature[key]));
const leaves=V.merkle.leaves.map(v=>{const b=hash(cat(Buffer.from([0]),enc(['HWP-C/1:event',B(V.merkle.start_digest_hex),v.index,B(v.salt_hex),B(v.event_hex)])));assert.deepEqual(b,B(v.leaf_hex));return b;});
function tree(a){if(!a.length)return hash(Buffer.alloc(0));if(a.length===1)return a[0];let k=1;while(k*2<a.length)k*=2;return hash(cat(Buffer.from([1]),tree(a.slice(0,k)),tree(a.slice(k))));}
for(let i=0;i<=7;i++)assert.deepEqual(tree(leaves.slice(0,i)),B(V.merkle.prefix_roots_hex[i]));
for(const v of V.merkle.inclusions){let p=0;function climb(i,n){if(n===1)return leaves[v.index];let k=1;while(k*2<n)k*=2;const sub=i<k?climb(i,k):climb(i-k,n-k),sib=B(v.path_hex[p++]);return hash(cat(Buffer.from([1]),...(i<k?[sub,sib]:[sib,sub])));}assert.deepEqual(climb(v.index,v.count),tree(leaves));assert.equal(p,v.path_hex.length);}
for(const hex of V.reject_cbor_hex)assert.throws(()=>dec(B(hex)));
console.log(JSON.stringify({status:'PASS',node:process.version,objects:objects.size,signatures_checked:signatures,merkle_inclusions:7,merkle_prefix_roots:8,negative_cbor:V.reject_cbor_hex.length,scope:'Independent standards-layer checker, not full HWP policy verification or behavioural detection'}));
