import copy
import unittest
from math import isclose
from scipy.stats import beta,binom
from hwp_a.calibration import *
from hwp_a.model import *
from hwp_a.features import Q,extract,adequate
from hwp_a.replay import replay,make_units,InvalidTrace
from hwp_a.fixtures import Builder,TEXT,permissive_fixture_model
from hwp_a.dataset import extract_case,extract_dataset,false_mask
from hwp_a.verify import score,TrustedInputs
from hwp_a.attacks import retime,staged_transcription,adaptive_retiming


def make_row(i,split,label,features=None):
    return {'id':split+'-'+str(i),'cluster':split+'-cluster-'+str(i),
            'document':split+'-document-'+str(i),'split':split,'links':{},
            'domain':'keyboard|en|birth','label':label,
            'features':features or {'a':5000 if label=='H' else -5000,'b':0}}


class CalibrationTests(unittest.TestCase):
    def test_exact_binomial_acceptance_matches_rational_enumeration(self):
        from fractions import Fraction
        from math import comb
        for n in range(1,25):
            for k in range(n+1):
                for p in (Fraction(1,1000),Fraction(1,2),Fraction(9,10)):
                    probability=sum(Fraction(comb(n,i))*p**i*(1-p)**(n-i) for i in range(k+1))
                    self.assertEqual(exact_lower_tail_at_most(k,n,p,Fraction(1,20)),probability<=Fraction(1,20))
    def test_exact_zero_failure_bound(self):
        self.assertEqual(zero_failure_n(.001,.05),2995)
        self.assertLessEqual(upper(0,2995,.05),.001)
        self.assertGreater(upper(0,2994,.05),.001)
    def test_nonzero_bounds(self):
        for k,n in ((1,10),(4,25),(99,100)):
            self.assertTrue(isclose(upper(k,n,.03),beta.ppf(.97,k+1,n-k)))
            self.assertTrue(isclose(lower(k,n,.03),beta.ppf(.03,k,n-k+1)))
    def test_empty_and_all_failure(self):
        self.assertEqual(upper(0,0,.05),1)
        self.assertEqual(upper(4,4,.05),1)
        self.assertEqual(lower(0,0,.05),0)
    def test_cluster_not_window_denominator(self):
        records=[{'cell':'attack','cluster':'one','kind':'attack','score':-20} for _ in range(2000)]
        records += [{'cell':'human','cluster':str(i),'kind':'human','score':20} for i in range(200)]
        result=calibrate(records,[0],['attack'],['human'])
        self.assertEqual(result['reports'][0]['attack']['attack']['n'],1)
        self.assertFalse(result['eligible'])
    def test_sufficient_synthetic_numeric_sample(self):
        records=[{'cell':'a','cluster':str(i),'kind':'attack','score':-10} for i in range(6000)]
        records += [{'cell':'h','cluster':str(i),'kind':'human','score':10} for i in range(200)]
        result=calibrate(records,[-10,0,11],['a'],['h'])
        self.assertEqual(result['threshold'],0)
        self.assertFalse(result['approval_granted'])
        self.assertFalse(result['reports'][0]['eligible'])
        self.assertFalse(result['reports'][-1]['eligible'])
        self.assertAlmostEqual(result['alpha_attack'],.025/3)
    def test_missing_required_attack_and_human_cells(self):
        rows=[{'cell':'a','cluster':str(i),'kind':'attack','score':-10} for i in range(6000)]
        rows += [{'cell':'h','cluster':str(i),'kind':'human','score':10} for i in range(200)]
        self.assertFalse(calibrate(rows,[0],['a','b'],['h'])['eligible'])
        self.assertFalse(calibrate(rows,[0],['a'],['h','h2'])['eligible'])
    def test_missing_human_data_even_zero_coverage_target(self):
        rows=[{'cell':'a','cluster':str(i),'kind':'attack','score':-10} for i in range(6000)]
        self.assertFalse(calibrate(rows,[0],['a'],['h'],min_coverage=0)['eligible'])
    def test_attack_max_human_min(self):
        rows=[{'cell':'a','cluster':'x','kind':'attack','score':s} for s in (-100,100)]
        rows += [{'cell':'h','cluster':'x','kind':'human','score':s} for s in (-100,100)]
        result=calibrate(rows,[0],['a'],['h'])['reports'][0]
        self.assertEqual(result['attack']['a']['failures'],1)
        self.assertEqual(result['coverage']['h']['all_tasks_passed'],0)
    def test_one_false_scalar_is_failure(self):
        score={'valid':True,'scalar_scores':[-100,15,-100]}
        self.assertEqual(campaign_score([score],[[False,True,False]]),15)
        self.assertEqual(campaign_score([score],[[True,False,True]]),-100)
        with self.assertRaises(InvalidTrace): campaign_score([score],[[True]])
    def test_threshold_grid_fixed_and_bounded(self):
        grid=thresholds(list(range(1000)))
        self.assertLessEqual(len(grid),32); self.assertEqual(grid[0],0); self.assertEqual(grid[-1],10**9)
        with self.assertRaises(InvalidTrace): calibrate([], [2,1],['a'],['h'])
    def test_unregistered_cell_rejected(self):
        with self.assertRaises(InvalidTrace): calibrate([{'cell':'surprise','cluster':'x','kind':'attack','score':0}],[0],['a'],['h'])


class LearningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows=[]
        for i,label in enumerate(('H',)+HEADS):
            for j in range(4): cls.rows.append(make_row(i*4+j,'train',label))
        cls.rows += [make_row(i,'development','H') for i in range(99)]
        cls.fitted=fit(cls.rows)
    def test_complete_export_and_nontrivial_scores(self):
        m=self.fitted; art=m['domains']['keyboard|en|birth']
        self.assertEqual(set(art['heads']),set(HEADS))
        self.assertTrue(all(len(x)==32 for x in art['heads'].values()))
        h=evaluate({'a':5000,'b':0},art,['a','b'])
        a=evaluate({'a':-5000,'b':0},art,['a','b'])
        self.assertGreater(h[0],a[0]); self.assertTrue(h[1]); self.assertFalse(a[1])
    def test_frozen_refit_reproducible_in_environment(self):
        self.assertEqual(self.fitted,fit(self.rows))
    def test_final_test_never_fits(self):
        changed=self.rows+[make_row(1,'test','H',{'a':-9999,'b':5000})]
        self.assertEqual(fit(changed),self.fitted)
    def test_missing_head_training_excludes_domain(self):
        self.assertEqual(fit([r for r in self.rows if r['label']!='simulation'])['domains'],{})
    def test_writer_source_cluster_leakage_rejected(self):
        for key in ('writer','source','prompt','campaign'):
            rows=[make_row(1,'train','H'),make_row(2,'test','H')]
            for r in rows: r['links']={key:['shared']}
            with self.assertRaises(InvalidTrace): validate_splits(rows)
    def test_ambiguous_not_training_negative(self):
        with self.assertRaises(InvalidTrace): validate_splits([make_row(1,'train','U')])
    def test_duplicate_rows_rejected(self):
        with self.assertRaises(InvalidTrace): validate_splits([self.rows[0],self.rows[0]])
    def test_malformed_tree_and_features(self):
        with self.assertRaises(InvalidTrace): tree_score({'value':0,'threshold':0},[0])
        with self.assertRaises(InvalidTrace): tree_score({'value':5000},[0])
        with self.assertRaises(InvalidTrace): vector({'b':0,'a':0},['a','b'])


class DatasetAndAttackTests(unittest.TestCase):
    def case(self,label='H'):
        b=Builder().type(TEXT).bundle(); n=len(b['documents'][0]['transactions'])
        return {'id':'c','cluster':'c','split':'train','links':{},'bundle':b,
                'labels':[{'document':'d','start_tx':0,'end_tx':n,'label':label}], 'condition':'SYNTHETIC'}
    def test_raw_annotations_generate_features(self):
        cc=self.case(); rows=extract_case(cc)
        self.assertTrue(rows); self.assertTrue(all(r['label']=='H' for r in rows))
        self.assertFalse(any(false_mask(cc)))
        self.assertTrue(all(false_mask(self.case('transcription'))))
    def test_negative_spelling_derivation_not_hidden_by_human_roots(self):
        b=Builder().type(TEXT); start=b.text.index('writer'); n=len(b.transactions)
        b.splice(start,start+6,'writex',source='spelling')
        cc={'id':'s','cluster':'s','split':'train','links':{},'bundle':b.bundle(),'condition':'SYNTHETIC',
            'labels':[{'document':'d','start_tx':0,'end_tx':n,'label':'H'},
                      {'document':'d','start_tx':n,'end_tx':n+1,'label':'simulation'}]}
        self.assertEqual(sum(false_mask(cc)),6)
        self.assertIn('simulation',{r['label'] for r in extract_case(cc)})
    def test_annotation_gap_rejected(self):
        cc=self.case(); cc['labels'][0]['end_tx']-=1
        with self.assertRaises(InvalidTrace): extract_case(cc)
    def test_mixed_origin_label_locality(self):
        cc=self.case(); n=cc['labels'][0]['end_tx']
        cc['labels']=[{'document':'d','start_tx':0,'end_tx':n-1,'label':'H'},
                      {'document':'d','start_tx':n-1,'end_tx':n,'label':'transcription'}]
        mask=false_mask(cc); self.assertEqual(sum(mask),1)
        self.assertIn('transcription',{r['label'] for r in extract_case(cc)})
    def test_ambiguity_is_quarantined(self):
        cc=self.case('U'); self.assertEqual(extract_case(cc),[])
        cc['split']='ambiguity'; self.assertTrue(all(r['label']=='U' for r in extract_case(cc)))
    def test_delayed_input_pooling_rejected(self):
        b=Builder().type('a').bundle(); b['documents'][0]['transactions'][0]['t']+=251_000
        with self.assertRaises(InvalidTrace): replay(b)
    def test_retiming_preserves_document_and_lineage(self):
        b=Builder().type(TEXT,seed=9).bundle(); changed=retime(b,8)
        a,z=replay(b),replay(changed)
        self.assertEqual(a.documents['d'].text,z.documents['d'].text)
        self.assertEqual(a.atoms,z.atoms)
    def test_staged_revisions_reconstruct_target(self):
        b=staged_transcription(TEXT,3)
        self.assertEqual(replay(b).documents['d'].text,TEXT)
        self.assertGreater(len(b['documents'][0]['transactions']),len(TEXT))
    def test_adaptive_search_retains_attempts_not_iid_trials(self):
        b=Builder().type(TEXT).bundle(); m=permissive_fixture_model(b)
        ctx=TrustedInputs(frozenset({'d'}),False,None,frozenset(m['domains']))
        report=adaptive_retiming(b,m,ctx,budget=3)
        self.assertEqual(len(report['attempts']),3)
        self.assertEqual(report['statistical_units'],1)
        self.assertFalse(report['human_accuracy_measured'])
    def test_keyboard_autorepeat_is_not_many_motor_actions(self):
        b=Builder().type('a').bundle(); d=b['documents'][0]
        press=d['observations'][0]; token=press['token']; t=press['t']
        d['observations']= [press]
        for i in range(1,80):
            d['observations'].append({'i':i,'t':t+i*10_000,'kind':'repeat','token':token,'source':'device','profile':'keyboard'})
            d['transactions'].append({'i':i,'t':t+i*10_000,'op':'splice','profile':'keyboard','causes':[i],
                                      'start':i,'end':i,'text':'a','deleted':'','source':'direct'})
        d['observations'].append({'i':80,'t':t+800_000,'kind':'release','token':token,'source':'device','profile':'keyboard'})
        d['final_text']='a'*80; c=replay(b); uu,_=make_units(c,'d')
        self.assertTrue(uu); self.assertTrue(all(not adequate(c,u) for u in uu))

class ReleaseAndMetricsTests(unittest.TestCase):
    def test_required_matrix_complete(self):
        from hwp_a.release import evaluation_cells
        a,h=evaluation_cells([('keyboard','en')])
        self.assertEqual(len(a),16); self.assertEqual(len(h),1)
        for family in FAMILIES: self.assertEqual(sum('/'+family+'/' in x for x in a),2)
        with self.assertRaises(InvalidTrace): evaluation_cells([('keyboard','en'),('keyboard','en')])
    def test_empty_required_matrix_not_certifying(self):
        from hwp_a.release import evaluate_release
        r=evaluate_release([], [0], [('keyboard','en')])
        self.assertFalse(r['eligible']); self.assertFalse(r['approval_granted'])
    def test_metrics_preserve_invalid_human_denominator(self):
        from hwp_a.metrics import evaluate_cases
        b=Builder().type(TEXT).bundle(); n=len(b['documents'][0]['transactions']); cases=[]
        for i,label in enumerate(('H','transcription','H')):
            cases.append({'id':str(i),'cluster':str(i),'split':'test','links':{},'condition':'SYNTHETIC',
                          'bundle':copy.deepcopy(b),'labels':[{'document':'d','start_tx':0,'end_tx':n,'label':label}]})
        cases[2]['bundle']['documents'][0]['final_text']='tampered'
        m=permissive_fixture_model(b); ctx=TrustedInputs(frozenset({'d'}),False,None,frozenset(m['domains']))
        r=evaluate_cases(cases,m,{str(i):ctx for i in range(3)},0)
        self.assertEqual(r['counts']['qualifying_documents'],2)
        self.assertEqual(r['document_coverage'],.5)
        self.assertEqual(r['campaigns_with_false_scalar'],1)
        self.assertEqual(r['counts']['invalid_attempts'],1)

if __name__=='__main__': unittest.main()
