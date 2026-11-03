"""Prepara packshots reales y carga borradores sin inventar precios ni stock.

Ejecutar con el Python bundled que ya incluye Pillow:
  python catalogo_aftr.py --preparar
  python catalogo_aftr.py --cargar
La carga exige la migración PULSE; nunca imprime credenciales.
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
import urllib.request
import urllib.error
from PIL import Image, ImageOps, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'work/catalogo-aftr'
EXPECTED='https://cxksjarupexptfksnptg.supabase.co'

def descargar(url):
    req=urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0'})
    with urllib.request.urlopen(req,timeout=30) as r:
        data=r.read(16*1024*1024)
    if len(data)>=16*1024*1024: raise ValueError('Imagen demasiado grande')
    return data

def preparar():
    WORK.mkdir(parents=True,exist_ok=True)
    fuentes=json.loads((ROOT/'db/catalogo_aftr.json').read_text())
    salida=[]; previews=[]
    for f in fuentes:
        r={k:f[k] for k in ['clave','nombre','categoria','es_bebida','verificacion_pendiente'] if k in f}
        r.setdefault('es_bebida',True);r.setdefault('verificacion_pendiente',False)
        r['foto_fuente']=f.get('fuente');r['foto_url']=None
        if f.get('imagen'):
            path=WORK/(f['clave']+'.webp')
            if not path.exists():
                img=Image.open(io.BytesIO(descargar(f['imagen']))).convert('RGBA')
                img.thumbnail((640,800),Image.Resampling.LANCZOS)
                img.save(path,'WEBP',quality=85,method=6)
            r['archivo']=path.name
            r['objeto']='base/'+f['clave']+'-'+hashlib.sha256(path.read_bytes()).hexdigest()[:12]+'.webp'
            im=Image.new('RGB',(200,250),'#141416');pic=Image.open(path).convert('RGBA');pic.thumbnail((180,205))
            im.paste(pic,((200-pic.width)//2,5),pic);ImageDraw.Draw(im).text((8,220),f['nombre'][:25],fill='white');previews.append(im)
        salida.append(r)
    (WORK/'manifest.json').write_text(json.dumps(salida,ensure_ascii=False,indent=2))
    sheet=Image.new('RGB',(200*5,250*2),'#0b0b0d')
    for i,im in enumerate(previews):sheet.paste(im,((i%5)*200,(i//5)*250))
    sheet.save(WORK/'revision.jpg')
    print(json.dumps({'productos':len(salida),'fotos':len(previews),'bytes':sum(p.stat().st_size for p in WORK.glob('*.webp'))}))

def cargar():
    env={}
    for line in (ROOT/'.env.local').read_text().splitlines():
        if '=' in line and not line.startswith('#'):
            k,v=line.split('=',1);env[k.strip()]=v.strip().strip('"\'')
    base=env.get('SUPABASE_URL','').rstrip('/')
    if base!=EXPECTED:raise SystemExit('El proyecto no coincide con VENUE/AFTR')
    key=env['SUPABASE_SERVICE_ROLE_KEY']
    def request(path,body=None,method='GET',ctype='application/json',prefer=None):
        headers={'apikey':key,'Authorization':'Bearer '+key,'Content-Type':ctype}
        if prefer:headers['Prefer']=prefer
        if body is not None and not isinstance(body,bytes):body=json.dumps(body).encode()
        req=urllib.request.Request(base+path,data=body,method=method,headers=headers)
        try:
            with urllib.request.urlopen(req,timeout=30) as r:
                data=r.read();return json.loads(data) if data else None
        except urllib.error.HTTPError as e:
            detail=e.read().decode('utf8','replace')[:400]
            raise RuntimeError(f'HTTP {e.code}: {detail}') from None
    # Comprobar la migración antes de subir ningún archivo.
    request('/rest/v1/aftr_catalogo_base?select=clave&limit=1')
    manifest=json.loads((WORK/'manifest.json').read_text())
    for row in manifest:
        row=dict(row);objeto=row.pop('objeto',None);archivo=row.pop('archivo',None)
        if objeto:
            path='/storage/v1/object/bar-catalogo/'+objeto
            try:request('/storage/v1/object/info/bar-catalogo/'+objeto)
            except RuntimeError as e:
                if '404' not in str(e) and 'not_found' not in str(e):raise
                request(path,(WORK/archivo).read_bytes(),'POST','image/webp')
            row['foto_url']=base+'/storage/v1/object/public/bar-catalogo/'+objeto
        request('/rest/v1/aftr_catalogo_base?on_conflict=clave',[row],'POST',prefer='resolution=merge-duplicates,return=minimal')
    clubs=request('/rest/v1/clubs?select=id')
    for club in clubs:
        creados=request('/rest/v1/rpc/venue_cargar_catalogo_base',{'p_club':club['id']},'POST')
        print(json.dumps({'club':club['id'],'borradores_nuevos':creados}))
    print('Catálogo cargado. Ningún producto fue publicado ni recibió precio o stock.')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--preparar',action='store_true');p.add_argument('--cargar',action='store_true');a=p.parse_args()
    if a.preparar:preparar()
    if a.cargar:cargar()
