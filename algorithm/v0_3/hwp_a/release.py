"""Mandatory path-specific evaluation cells; eligibility never grants approval."""
from .calibration import FAMILIES
from .replay import PROFILES,need
from .ledger import evaluate_ledger
BUDGETS=(1,100)
HUMAN_CONDITIONS=('unaided','ai-informed','fluent-expert','revision-heavy','interrupted','second-language')


def evaluation_cells(input_domains, claim_kind='fresh-composition'):
    need(claim_kind in ('fresh-composition','wording-origin'), 'CLAIM_KIND')
    need(type(input_domains) is list and input_domains, 'INPUT_DOMAINS')
    normalized=[]
    for row in input_domains:
        need(type(row) in (tuple,list) and len(row)==3, 'INPUT_DOMAIN')
        profile,path,language=row
        need(profile in PROFILES and all(type(v) is str and v and '|' not in v for v in (path,language)), 'INPUT_DOMAIN')
        normalized.append(tuple(row))
    need(len(set(normalized))==len(normalized), 'DUPLICATE_DOMAIN')
    attacks=[]; humans=[]
    for profile,path,language in sorted(normalized):
        z='|'.join((profile,path,language,claim_kind))
        attacks += [z+'|'+family+'|B'+str(budget) for family in FAMILIES for budget in BUDGETS]
        humans.extend(z+'|'+condition for condition in HUMAN_CONDITIONS)
    return attacks,humans


def validate_release_matrix(ledger,input_domains):
    attack,human=evaluation_cells(input_domains,ledger['claim_kind'])
    need(set(ledger['cells'])==set(attack+human), 'REQUIRED_MATRIX')
    for cell in attack:
        need(ledger['cells'][cell]['kind']=='attack' and ledger['cells'][cell]['attempts_per_block']==int(cell.rsplit('B',1)[1]), 'CELL_BUDGET')
    for cell in human: need(ledger['cells'][cell]['kind']=='human', 'CELL_KIND')
    return True


def evaluate_release(ledger,results,candidates,input_domains):
    validate_release_matrix(ledger,input_domains)
    return evaluate_ledger(ledger,results,candidates)


def run_release(ledger,cases,model,contexts,candidates,input_domains):
    """Raw-case release entrypoint, including required task-condition coverage."""
    from .ledger import run_ledger
    validate_release_matrix(ledger,input_domains)
    by_id={c['id']:c for c in cases}
    for slot in ledger['slots']:
        cell=slot['cell'];parts=cell.split('|')
        expected=parts[-2] if ledger['cells'][cell]['kind']=='attack' else parts[-1]
        need(slot['id'] in by_id and by_id[slot['id']]['condition']==expected, 'CASE_CONDITION_MISMATCH')
    _,results=run_ledger(ledger,cases,model,contexts,candidates)
    return evaluate_release(ledger,results,candidates,input_domains),results
