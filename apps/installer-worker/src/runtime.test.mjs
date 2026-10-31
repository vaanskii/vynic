import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { Miniflare } from 'miniflare';
const deployment = JSON.parse(readFileSync(new URL('../wrangler.json', import.meta.url), 'utf8'));
const id='12345678-1234-1234-1234-123456789abc',token='a'.repeat(43);
const key='windows/beta/1.0.1/build18/Vynic-Windows-1.0.1-build18-beta-offline.zip';
test('workerd local R2 binding supports authenticated GET HEAD Range and revocation',async()=>{
 const mf=new Miniflare({host:'127.0.0.1',workers:[{name:'installer',modules:true,scriptPath:new URL('../'+deployment.main,import.meta.url).pathname,compatibilityDate:deployment.compatibility_date,bindings:{DOWNLOAD_GATEWAY_SECRET:'b'.repeat(43)},r2Buckets:{[deployment.r2_buckets[0].binding]:'local-test-only'},outboundService:'authority'}, {name:'authority',modules:true,compatibilityDate:deployment.compatibility_date,script:`export default {async fetch(r){ const b=await r.json(); if(b.clientIp==='192.0.2.99')return Response.json({}, {status:404});const range=b.range?.slice(6).split('-');return Response.json({expiresAt:new Date(Date.now()+60000).toISOString(),key:${JSON.stringify(key)},bytes:5,sha256:'c'.repeat(64),start:range?Number(range[0]):0,end:range?Math.min(Number(range[1]||4),4):4,partial:!!range});}}`}]});
 try {const bucket=await mf.getR2Bucket('INSTALLERS');await bucket.put(key,'hello',{customMetadata:{sha256:'c'.repeat(64)}});for(const [method,range,want,status] of [['GET',null,'hello',200],['HEAD',null,'',200],['GET','bytes=1-3','ell',206]]){const r=await mf.dispatchFetch('https://releases.vynic.ge/windows/access/'+id+'/file',{method,headers:{'CF-Connecting-IP':'192.0.2.1',Cookie:'__Secure-vynic-download='+token,...(range?{Range:range}:{})}});assert.equal(r.status,status);assert.equal(r.headers.get('content-length'),range?'3':'5');assert.equal(await r.text(),want)}const denied=await mf.dispatchFetch('https://releases.vynic.ge/windows/access/'+id+'/file',{headers:{'CF-Connecting-IP':'192.0.2.99',Cookie:'__Secure-vynic-download='+token}});assert.equal(denied.status,404);}finally{await mf.dispose()}
});
