import { validarMedio } from './media.ts';
function rechaza(b: Uint8Array) { let error=false;try{validarMedio(b);}catch{error=true;}if(!error)throw new Error('Aceptó un medio inválido.'); }
function caja(tipo:string,datos:Uint8Array){const b=new Uint8Array(8+datos.length);new DataView(b.buffer).setUint32(0,b.length);b.set(new TextEncoder().encode(tipo),4);b.set(datos,8);return b;}
function juntar(...a:Uint8Array[]){const b=new Uint8Array(a.reduce((n,x)=>n+x.length,0));let p=0;for(const x of a){b.set(x,p);p+=x.length;}return b;}
function video(seg:number){const h=new Uint8Array(24);const d=new DataView(h.buffer);d.setUint32(12,1000);d.setUint32(16,seg*1000);const handler=new Uint8Array(16);handler.set(new TextEncoder().encode('vide'),8);return juntar(caja('ftyp',new TextEncoder().encode('isom0000')),caja('moov',juntar(caja('mvhd',h),caja('trak',caja('mdia',caja('hdlr',handler))))),caja('mdat',new Uint8Array([1,2,3,4])));}
Deno.test('no admite SVG/HTML ni archivos vacíos',()=>{rechaza(new Uint8Array());rechaza(new TextEncoder().encode('<svg onload="alert(1)"></svg>'));});
Deno.test('no admite archivos superiores a 30MB',()=>rechaza(new Uint8Array(30*1024*1024+1)));
Deno.test('verifica duración MP4 en servidor',()=>{if(validarMedio(video(30)).duracion_ms!==30000)throw new Error('Duración incorrecta');rechaza(video(31));});
Deno.test('rechaza cajas MP4 truncadas y pista inexistente',()=>{rechaza(video(10).slice(0,-1));rechaza(caja('ftyp',new TextEncoder().encode('isom0000')));});
Deno.test('imágenes siempre tienen cinco segundos',()=>{const b=new Uint8Array([255,216,255,1,2,3,4,5,6,7,8,9,10,255,217]);if(validarMedio(b).duracion_ms!==5000)throw new Error('Duración incorrecta');});
