"""Validate interchange examples and local OpenAPI references; no live backend tests."""
import json
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker
from openapi_spec_validator import validate_spec
ROOT = Path(__file__).resolve().parents[1]
schema = json.loads((ROOT/'schemas/import-v1.schema.json').read_text())
Draft202012Validator.check_schema(schema)
cases = json.loads(Path(__file__).with_name('contract-examples.json').read_text())
for case in cases:
    chosen = dict(schema, **{'$ref':'#/$defs/'+case['definition']})
    errors = list(Draft202012Validator(chosen,format_checker=FormatChecker()).iter_errors(case['value']))
    assert (not errors) == case['valid'], (case['name'], [e.message for e in errors])
api = json.loads((ROOT/'schemas/import-v1.openapi.json').read_text())
# Inline external definitions for validators that cannot fetch relative files.
def resolve(value):
    if isinstance(value,dict):
        if '$ref' in value and value['$ref'].startswith('./import-v1.schema.json#/$defs/'):
            name=value['$ref'].rsplit('/',1)[-1]
            return {'$ref':'#/components/schemas/'+name}
        return {k:resolve(v) for k,v in value.items()}
    if isinstance(value,list): return [resolve(v) for v in value]
    return value
api=resolve(api)
def local_refs(value):
    if isinstance(value,dict):
        return {k:('#/components/schemas/'+v.rsplit('/',1)[-1] if k=='$ref' and v.startswith('#/$defs/') else local_refs(v)) for k,v in value.items()}
    if isinstance(value,list): return [local_refs(v) for v in value]
    return value
api['components']['schemas']=local_refs(schema['$defs'])
validate_spec(api)
transitions=schema['x-state-transitions']
assert set(transitions)==set(schema['$defs']['Job']['properties']['status']['enum'])
assert transitions['completed']==transitions['needs_review']==[]
assert 'completed' not in transitions['received'] and 'completed' not in transitions['queued']
assert transitions['failed']==['queued']
print(f'PASS: {len(cases)} positive/negative examples, OpenAPI 3.1, state graph; live durability/AI not tested')
