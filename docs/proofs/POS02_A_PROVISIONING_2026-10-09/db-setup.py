import tempfile,subprocess,pathlib,json,socket,os
root=pathlib.Path(tempfile.mkdtemp(prefix='vynic-pos02a-pg-',dir='/private/tmp'))
bin='/opt/homebrew/opt/postgresql@17/bin/'
s=socket.socket();s.bind(('127.0.0.1',0));port=s.getsockname()[1];s.close()
log=open(root/'setup.log','w')
subprocess.run([bin+'initdb','-D',str(root/'data'),'-A','trust','-U','pos02a_test','--no-locale'],stdout=log,stderr=subprocess.STDOUT,check=True)
subprocess.run([bin+'pg_ctl','-D',str(root/'data'),'-l',str(root/'server.log'),'-o',f'-h 127.0.0.1 -p {port} -k {root}','-w','start'],stdout=log,stderr=subprocess.STDOUT,check=True)
url=f'postgresql://pos02a_test@127.0.0.1:{port}/pos02a_provisioning'
subprocess.run([bin+'createdb','-h','127.0.0.1','-p',str(port),'-U','pos02a_test','pos02a_provisioning'],check=True)
pathlib.Path('/private/tmp/pos02a-db.json').write_text(json.dumps({'root':str(root),'url':url,'port':port}))
print(json.dumps({'isolatedDatabase':'pos02a_provisioning','root':str(root),'port':port}))
