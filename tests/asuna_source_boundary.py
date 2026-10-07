from pathlib import Path
import hashlib,json
FIXTURE=json.loads((Path(__file__).parent/'fixtures/asuna_source/core-seams.json').read_text())
def reverse_asuna_core(source):
    for index,row in enumerate(FIXTURE['seams']):
        if source.count(row['after'])!=1:
            raise AssertionError(f'Asuna seam {index} missing, duplicated or changed')
        source=source.replace(row['after'],row['before'],1)
    if hashlib.sha256(source.encode()).hexdigest()!=FIXTURE['baseline_sha256']:
        raise AssertionError('Unapproved historical source modification')
    return source
