"""Real RFC3161 token operations under a local, temporary synthetic TSA trust root."""
import datetime as dt
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from hwp0.core import Reject
from hwp0.rfc3161 import verify_token

class Timestamp(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='hwp-tsa-test-'); cls.p=Path(cls.temp.name)
        def run(*args):
            r=subprocess.run(['openssl',*args],cwd=cls.p,capture_output=True,timeout=15)
            if r.returncode: raise RuntimeError(r.stderr.decode())
            return r.stdout
        run('req','-x509','-newkey','rsa:2048','-nodes','-keyout','root.key','-out','root.pem','-subj','/CN=HWP SYNTHETIC TEST CA','-days','2','-addext','basicConstraints=critical,CA:TRUE','-addext','keyUsage=critical,keyCertSign,cRLSign')
        run('req','-new','-newkey','rsa:2048','-nodes','-keyout','tsa.key','-out','tsa.csr','-subj','/CN=HWP SYNTHETIC TEST TSA')
        (cls.p/'ext.cnf').write_text('basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,timeStamping\n')
        run('x509','-req','-in','tsa.csr','-CA','root.pem','-CAkey','root.key','-CAcreateserial','-out','tsa.pem','-days','1','-extfile','ext.cnf')
        (cls.p/'serial').write_text('01\n')
        (cls.p/'tsa.cnf').write_text('''[tsa]
default_tsa = config
[config]
serial = serial
signer_cert = tsa.pem
certs = root.pem
signer_key = tsa.key
signer_digest = sha256
default_policy = 1.3.6.1.4.1.55555.1
digests = sha256, sha512
accuracy = secs:1, millisecs:500
ordering = no
tsa_name = yes
ess_cert_id_chain = yes
ess_cert_id_alg = sha256
''')
        cls.data=b'SYNTHETIC ARCHIVE: not a Human Writing Proof'
        (cls.p/'data').write_bytes(cls.data)
        run('ts','-query','-data','data','-sha512','-cert','-out','request.der')
        run('ts','-reply','-config','tsa.cnf','-queryfile','request.der','-out','response.der')
        run('ts','-reply','-in','response.der','-token_out','-out','token.der')
        cls.token=(cls.p/'token.der').read_bytes(); cls.ca=(cls.p/'root.pem').read_bytes(); cls.now=int(time.time())
    @classmethod
    def tearDownClass(cls): cls.temp.cleanup()
    def verify(self,**kw):
        args=dict(token=self.token,data=self.data,ca_pem=self.ca,validation_time=self.now,allowed_policy_oids={'1.3.6.1.4.1.55555.1'})
        args.update(kw); return verify_token(**args)
    def test_valid_token(self):
        r=self.verify(); self.assertEqual(r['status'],'VALID-TIMESTAMP'); self.assertEqual(r['accuracy_us'],1_500_000)
        self.assertEqual(r['hash_algorithm'],'sha512'); self.assertIsNone(r['hwp_composition_inference'])
    def test_wrong_document(self):
        with self.assertRaises(Reject): self.verify(data=self.data+b'!')
    def test_wrong_authority(self):
        with self.assertRaises(Reject): self.verify(ca_pem=b'not a trusted root')
    def test_wrong_policy(self):
        with self.assertRaises(Reject): self.verify(allowed_policy_oids={'1.2.3.4'})
    def test_wrong_nonce(self):
        with self.assertRaises(Reject): self.verify(expected_nonce=1)
    def test_trailing_der(self):
        with self.assertRaises(Reject): self.verify(token=self.token+b'\x00')
    def test_tampered_signature(self):
        t=bytearray(self.token); t[-1]^=1
        with self.assertRaises(Reject): self.verify(token=bytes(t))
