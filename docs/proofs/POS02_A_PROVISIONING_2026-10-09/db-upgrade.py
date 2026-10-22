import json,os,pathlib,subprocess,tempfile,shutil
repo=pathlib.Path('/Users/vaanskii/Developer/vynic');backend=repo/'apps/backend';proof=repo/'docs/proofs/POS02_A_PROVISIONING_2026-10-09'
c=json.load(open('/private/tmp/pos02a-db.json'));url=c['url'].replace('/pos02a_provisioning','/pos02a_upgrade');bin='/opt/homebrew/opt/postgresql@17/bin/'
subprocess.run([bin+'createdb','-h','127.0.0.1','-p',str(c['port']),'-U','pos02a_test','pos02a_upgrade'],check=True)
root=pathlib.Path(tempfile.mkdtemp(prefix='pos02a-previous-',dir='/private/tmp'));shutil.copy(backend/'prisma/schema.prisma',root/'schema.prisma');shutil.copytree(backend/'prisma/migrations',root/'migrations');shutil.rmtree(root/'migrations/20261018120000_printer_provisioning')
env={**os.environ,'DATABASE_URL':url}
with open(proof/'populated-upgrade.log','w') as log:
 def run(args):subprocess.run(args,cwd=backend,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
 run(['node','node_modules/prisma/build/index.js','migrate','deploy','--schema',str(root/'schema.prisma')])
 script="""const {PrismaClient}=require('@prisma/client');const p=new PrismaClient();(async()=>{const org=await p.organization.create({data:{name:'preserved fixture',venues:{create:{name:'Before POS02A',timezone:'Asia/Tbilisi',currency:'GEL'}}},include:{venues:true}});const d=await p.device.create({data:{venueId:org.venues[0].id,installationId:require('crypto').randomUUID(),displayName:'Original Device',platform:'WINDOWS',credentialHash:'disposable test verifier',runtimeConfig:{preserved:true}}});require('fs').writeFileSync(process.env.PREEXISTING,JSON.stringify(d));await p.$disconnect()})().catch(e=>{console.error(e);process.exit(1)})"""
 env['PREEXISTING']=str(root/'device.json');run(['node','-e',script])
 run(['node','node_modules/prisma/build/index.js','migrate','deploy'])
 script="""const {PrismaClient}=require('@prisma/client');const p=new PrismaClient();(async()=>{const old=JSON.parse(require('fs').readFileSync(process.env.PREEXISTING));const now=await p.device.findUniqueOrThrow({where:{id:old.id}});if(JSON.stringify(now)!==JSON.stringify(old))throw Error('Existing Device changed');if(await p.printerInstallation.count()!==0)throw Error('Migration issued authority');console.log('Populated Device identity, credential verifier and runtimeConfig preserved; no printer authority minted: PASS');await p.$disconnect()})().catch(e=>{console.error(e);process.exit(1)})"""
 run(['node','-e',script])
 run(['node','node_modules/prisma/build/index.js','validate'])
with open(proof/'schema-diff.sql','w') as log:
 subprocess.run(['node','node_modules/prisma/build/index.js','migrate','diff','--from-url',url,'--to-schema-datamodel',str(backend/'prisma/schema.prisma'),'--script'],cwd=backend,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
print('Populated upgrade and schema comparison completed')
