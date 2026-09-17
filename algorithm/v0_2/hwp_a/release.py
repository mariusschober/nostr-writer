"""Construct the mandatory empirical evaluation matrix. Does not grant approval."""
from .calibration import FAMILIES,calibrate
from .replay import PROFILES,need

BUDGETS=(1,100)


def evaluation_cells(input_domains: list[tuple[str,str]]) -> tuple[list[str],list[str]]:
    """Every admitted input/language combination needs every attack family.

    A cell is a fixed campaign distribution; additional hardware/software models,
    genres, adversary resources or language strata require separate frozen cells.
    No family can be omitted merely because no data were collected for it.
    """
    need(bool(input_domains) and len(set(input_domains))==len(input_domains),'INPUT_DOMAINS')
    attack=[]; human=[]
    for profile,language in sorted(input_domains):
        need(profile in PROFILES and type(language) is str and language and '/' not in language,'INPUT_DOMAIN')
        z=profile+'/'+language
        for family in FAMILIES:
            for budget in BUDGETS:
                attack.append(z+'/'+family+'/B'+str(budget)+'/any-false-scalar')
        human.append(z+'/all-qualifying-tasks')
    return attack,human


def evaluate_release(records,candidates,input_domains):
    attack,human=evaluation_cells(input_domains)
    return calibrate(records,candidates,attack,human)
