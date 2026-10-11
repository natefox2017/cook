import test from 'node:test';
import assert from 'node:assert/strict';
import { isAdminSession, validateAdminResponse } from '../src/api-contracts.ts';
const admin = {id:'fixture',username:'owner',role:'owner',mustChangePassword:false};
test('session rejects invalid dates, unknown roles and malformed token', () => {
  const session = {token:'fixture',expiresAt:'2099-01-01T00:00:00Z',admin};
  assert.equal(isAdminSession(session),true);
  for (const invalid of [{...session,expiresAt:'bad'},{...session,token:1},{...session,admin:{...admin,role:'root'}},null,[]]) assert.equal(isAdminSession(invalid),false);
});
test('malformed payloads fail at boundary instead of crashing rendering', () => {
  for (const [fn,path,value] of [
    ['admin-dashboard','',{stats:{},growth:[]}],['admin-users','',{data:[{}],total:1,page:1,pageSize:20}],
    ['admin-subscriptions','/plans',[{}]],['admin-subscriptions','/records',[{user:null}]],
    ['admin-auth','/factors',{totp:{enabled:false,enabledAt:null},passkeys:[{created_at:'bad'}]}],
    ['admin-auth','/login',{factorRequired:false,methods:[],admin}],['admin-ai','/providers',{data:[{}]}],
  ]) assert.throws(() => validateAdminResponse(fn,path,'GET',value), /incompatible data/);
});
test('empty collections and provider save acknowledgement remain compatible', () => {
  for (const [fn,path,value] of [['admin-subscriptions','/plans',[]],['admin-subscriptions','/records',[]],['admin-ai','/providers',{data:[]}],['admin-users','',{data:[],total:0,page:1,pageSize:20}],['admin-auth','/factors',{totp:{enabled:false,enabledAt:null},passkeys:[]}]]) assert.doesNotThrow(() => validateAdminResponse(fn,path,'GET',value));
  assert.doesNotThrow(() => validateAdminResponse('admin-ai','/providers','POST',{id:'fixture'}));
});
