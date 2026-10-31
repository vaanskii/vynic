import test from 'node:test';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
// Installed Wrangler against a localhost-only provider fixture with a dummy token.
// The fixture rejects all writes; it never touches the real Worker or R2.
test('strict upload preserves dashboard logs and inherits the existing binding without R2 management',async()=>{
const root=fileURLToPath(new URL('..',import.meta.url));
const config=JSON.parse(await readFile(join(root,'wrangler.json'),'utf8'));
const temp=await mkdtemp(join(tmpdir(),'vynic-strict-proof-'));
const observations=[];
try {
 for(const [preserveLogs,denyRoutes] of [[false,false],[true,false],[true,true]]) {
  const calls=[];
  const script={tag:'synthetic-worker-tag',last_deployed_from:'dash',compatibility_date:'2026-06-16',compatibility_flags:[],observability:{enabled:true,head_sampling_rate:1,logs:{enabled:true,head_sampling_rate:1,invocation_logs:true,persist:true},traces:{enabled:false,persist:true,head_sampling_rate:1}}};
  const server=createServer((req,res)=>{
   const path=new URL(req.url,'http://localhost').pathname;calls.push({method:req.method,path});
   res.setHeader('Content-Type','application/json');
   if(req.method!=='GET'){res.statusCode=409;res.end(JSON.stringify({success:false,errors:[{code:10021,message:'Synthetic proof deliberately stops before upload'}]}));return;}
   let result;
   if(denyRoutes && (path.endsWith('/routes')||path.endsWith('/domains/records'))){res.statusCode=403;res.end(JSON.stringify({success:false,errors:[{code:10000,message:'Synthetic route permission denied'}]}));return;}
   if(path.endsWith('/workers/services/vynic-installer-downloads'))result={default_environment:{environment:'production',script}};
   else if(path.endsWith('/bindings'))result=[{type:'r2_bucket',name:'INSTALLERS',bucket_name:'vynic-installers'},{type:'secret_text',name:'DOWNLOAD_GATEWAY_SECRET'}];
   else if(path.endsWith('/routes')||path.endsWith('/domains/records'))result=[];
   else if(path.endsWith('/subdomain'))result={enabled:false,previews_enabled:false};
   else if(path.endsWith('/environments/production'))result={script};
   else if(path.endsWith('/schedules'))result={schedules:[]};
   else if(path.endsWith('/secrets'))result=[{name:'DOWNLOAD_GATEWAY_SECRET',type:'secret_text'}];
   else if(path.endsWith('/settings'))result={bindings:[{type:'r2_bucket',name:'INSTALLERS',bucket_name:'vynic-installers'},{type:'secret_text',name:'DOWNLOAD_GATEWAY_SECRET'}]};
   else if(path.endsWith('/r2/buckets/vynic-installers')){res.statusCode=403;res.end(JSON.stringify({success:false,errors:[{code:10000,message:'Synthetic permission denied; no R2 admin grant'}]}));return;}
   else {res.statusCode=404;res.end(JSON.stringify({success:false,errors:[{code:10090,message:'Unknown synthetic read'}]}));return;}
   res.end(JSON.stringify({success:true,result}));
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const env={...process.env};for(const k of Object.keys(env))if(/^(CF|CLOUDFLARE|WRANGLER)_/.test(k))delete env[k];
  Object.assign(env,{CI:'true',CLOUDFLARE_API_TOKEN:'synthetic-local-only',CLOUDFLARE_API_BASE_URL:`http://127.0.0.1:${server.address().port}/client/v4`,WRANGLER_SEND_METRICS:'false',WRANGLER_LOG_PATH:join(temp,'wrangler.log')});
  const local={...config,main:join(root,'src/index.mjs')}; if(!preserveLogs)delete local.observability;
  const configPath=join(temp,`config-${preserveLogs}.json`);await writeFile(configPath,JSON.stringify(local));
  let output='';
  const child=spawn(process.execPath,[join(root,'node_modules/wrangler/bin/wrangler.js'),'versions','upload','--strict','--keep-vars','--config',configPath,'--tag','a'.repeat(40)],{cwd:root,env});
  child.stdout.on('data',x=>output+=x);child.stderr.on('data',x=>output+=x);
  const timer=setTimeout(()=>child.kill('SIGTERM'),20000);
  const code=await new Promise(resolve=>child.on('close',resolve));clearTimeout(timer);
  await new Promise(resolve=>server.close(resolve));
  observations.push({preserveLogs,denyRoutes,dashboardReadFailed:output.includes('Unable to fetch bindings, routes, or services metadata'),exit:code,strictConflict:output.includes('Aborting the upload operation because of conflicts'),writeAttemptsToSyntheticServer:calls.filter(c=>c.method!=='GET').length,reads:calls.filter(c=>c.method==='GET').map(c=>c.path.split('/').slice(-2).join('/'))});
 }
 assert.equal(observations[0].strictConflict,true);
 assert.equal(observations[0].writeAttemptsToSyntheticServer,0);
 assert.equal(observations[1].strictConflict,false,'checked-in config must preserve enabled logs');
 assert.equal(observations[1].writeAttemptsToSyntheticServer,1);
 assert.equal(observations[1].exit,1,'fixture refuses the real upload');
 assert.ok(observations[1].reads.every(p=>!p.startsWith('buckets/')),'no R2 management read is needed');
 assert.equal(observations[2].dashboardReadFailed,true,'per-Worker token cannot satisfy legacy dashboard route reads');
 assert.equal(observations[2].writeAttemptsToSyntheticServer,0,'permission failure happens before version upload');
} finally {await rm(temp,{recursive:true,force:true});}

});
