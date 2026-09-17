"""Preregistered complete-trial accounting. No IDs or statistics establish actual independence.

This is the mandatory input gate before calibration/final testing. Collection staff
supply the frozen ledger independently of submitted traces and observed successes.
"""
from .replay import need, num, shape
from .calibration import calibrate, FAMILIES
from .model import SCORE_FLOOR


def validate_ledger(ledger: dict, results: list[dict]) -> list[dict]:
    shape(ledger, {'version','phase','claim_kind','cells','slots'})
    need(ledger['version']=='hwp-a-ledger/0.3', 'LEDGER_VERSION')
    need(ledger['phase'] in ('calibration','test'), 'LEDGER_PHASE')
    need(ledger['claim_kind'] in ('fresh-composition','wording-origin'), 'LEDGER_CLAIM')
    cells=ledger['cells']; slots=ledger['slots']
    need(type(cells) is dict and 0<len(cells)<=1024, 'LEDGER_CELLS')
    for key,cell in cells.items():
        need(type(key) is str and bool(key), 'LEDGER_CELL_ID')
        shape(cell, {'kind','attempts_per_block','sampling_contract'})
        need(cell['kind'] in ('attack','human') and type(cell['sampling_contract']) is str and bool(cell['sampling_contract']), 'LEDGER_SAMPLING')
        num(cell['attempts_per_block'],1,10000)
    need(type(slots) is list and 0<len(slots)<=1_000_000, 'LEDGER_SLOTS')
    expected={}; blocks={}; owners={}
    for slot in slots:
        shape(slot, {'id','cell','block','attempt','links'})
        for key in ('id','cell','block'): need(type(slot[key]) is str and bool(slot[key]), 'LEDGER_ID')
        need(slot['id'] not in expected and slot['cell'] in cells, 'LEDGER_DUPLICATE_OR_CELL')
        attempt=num(slot['attempt'],0,cells[slot['cell']]['attempts_per_block']-1)
        expected[slot['id']]=slot
        key=(slot['cell'],slot['block']); blocks.setdefault(key,[]).append(attempt)
        links=slot['links']
        need(type(links) is list and bool(links) and all(type(x) is str and bool(x) for x in links) and len(links)==len(set(links)), 'LEDGER_LINKS')
        # Shared participant/adversary-state links cannot create two independent blocks in a cell.
        for link in links:
            owner=(slot['cell'],link)
            need(owner not in owners or owners[owner]==slot['block'], 'DEPENDENT_BLOCKS')
            owners[owner]=slot['block']
    for (cell,block), attempts in blocks.items():
        need(sorted(attempts)==list(range(cells[cell]['attempts_per_block'])), 'LEDGER_BUDGET_INCOMPLETE')
    need({cell for cell,block in blocks}==set(cells), 'LEDGER_EMPTY_CELL')
    need(type(results) is list, 'RESULTS_LIST')
    actual={}; records=[]
    for r in results:
        shape(r, {'id','status','score','claim_kind'})
        need(type(r['id']) is str and r['id'] in expected and r['id'] not in actual, 'RESULT_SLOT')
        need(r['status'] in ('scored','structural-rejection'), 'INCOMPLETE_ATTEMPT')
        need(r['claim_kind']==ledger['claim_kind'], 'RESULT_CLAIM_MISMATCH')
        num(r['score'],SCORE_FLOOR,40000)
        if r['status']=='structural-rejection': need(r['score']==SCORE_FLOOR, 'INVALID_ATTEMPT_SCORE')
        actual[r['id']]=r
        slot=expected[r['id']]
        records.append({'cell':slot['cell'],'cluster':slot['block'],'kind':cells[slot['cell']]['kind'],'score':r['score']})
    need(set(actual)==set(expected), 'MISSING_ATTEMPT')
    return records


def evaluate_ledger(ledger: dict, results: list[dict], candidates: list[int]) -> dict:
    records=validate_ledger(ledger,results)
    if ledger['phase']=='test': need(len(candidates)==1,'FINAL_THRESHOLD_NOT_FROZEN')
    attack=[k for k,v in ledger['cells'].items() if v['kind']=='attack']
    human=[k for k,v in ledger['cells'].items() if v['kind']=='human']
    report=calibrate(records,candidates,attack,human)
    report.update(phase=ledger['phase'],claim_kind=ledger['claim_kind'],ledger_complete=True)
    return report


def run_ledger(ledger, cases, model, contexts, candidates):
    """Execute raw attempts; do not substitute hand-selected numeric scores.

    Contexts and ground truth are experiment-controller inputs, not author claims.
    A missing or malformed annotation for an otherwise accepted attempt aborts
    evaluation instead of converting it to a reassuring failed attack.
    """
    from .model import validate_model
    from .verify import snapshot
    validate_model(model)
    need(len(snapshot(model))<=20_000_000,'INVALID_STUDY_MODEL')
    from .dataset import labels_for
    from .replay import replay
    from .verify import score
    need(type(cases) is list and len({c['id'] for c in cases})==len(cases), 'CASE_IDS')
    by_id={c['id']:c for c in cases}; results=[]
    need(set(by_id)=={s['id'] for s in ledger['slots']} and set(contexts)==set(by_id), 'CASE_LEDGER_ALIGNMENT')
    for slot in ledger['slots']:
        case=by_id[slot['id']]; context=contexts[slot['id']]
        # risk_record uses the default fresh-composition endpoint; the other
        # endpoint is computed explicitly below with the identical mask rules.
        from .dataset import false_mask
        from .calibration import campaign_score
        outcome=score(case['bundle'],model,context,ledger['claim_kind'])
        kind=ledger['cells'][slot['cell']]['kind']
        if kind=='human':
            labels=set(labels_for(case,replay(case['bundle'])).values()) if outcome['valid'] else set()
            value=outcome['document_score'] if labels=={'H'} else SCORE_FLOOR
        else:
            value=campaign_score([outcome],[false_mask(case)]) if outcome['valid'] else SCORE_FLOOR
        results.append({'id':case['id'],'status':'scored' if outcome['valid'] else 'structural-rejection',
                        'score':value,'claim_kind':ledger['claim_kind']})
    return evaluate_ledger(ledger,results,candidates),results


def phase_separation(calibration, final_test):
    """Reject declared cross-phase leakage; disjoint IDs do not prove independence."""
    need(calibration['phase']=='calibration' and final_test['phase']=='test', 'PHASE_ORDER')
    need(calibration['claim_kind']==final_test['claim_kind'], 'PHASE_CLAIM')
    def keys(ledger):
        return ({s['id'] for s in ledger['slots']},
                {link for s in ledger['slots'] for link in s['links']})
    a,b=keys(calibration),keys(final_test)
    need(not a[0]&b[0] and not a[1]&b[1], 'CROSS_PHASE_DEPENDENCY')
    return True
