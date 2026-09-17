import unittest
from math import isclose
from scipy.stats import beta
from hwp0.algorithm.calibration import *
from hwp0.algorithm.replay import InvalidTrace
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


