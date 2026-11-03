'use strict';
let _socialVenue;
function socialVenue() {
  return _socialVenue ||= AftrSocial.create({
    client:sb,staff:true,user:()=>me,notice:message=>toast(message),
    club:()=>club,identity:()=>['admin','propietario'].includes(me?.rol)?'club':'rrpp',
    events:async()=>{const {data,error}=await sb.rpc('aftr_eventos');if(error)throw error;return(data||[]).filter(e=>e.club?.id===club||e.club_id===club);},
    canModerate:h=>h.can_retirar===true,
    storyCTA:h=>window.open(`https://aftr-web.vercel.app/#/evento/${encodeURIComponent(h.evento_id)}?historia=${encodeURIComponent(h.id)}`,'_blank','noopener')
  });
}
const socialMenu=document.createElement('div');socialMenu.className='venue-social-menu';socialMenu.hidden=true;
socialMenu.innerHTML='<button type="button" data-historias>Historias</button><button type="button" data-reventa>Reventa</button>';
document.body.append(socialMenu);
socialMenu.querySelector('[data-historias]').onclick=()=>socialVenue().mineStories().catch(e=>toast(e.message,'error'));
socialMenu.querySelector('[data-reventa]').onclick=()=>socialVenue().gestion().catch(e=>toast(e.message,'error'));
function actualizarSocialVenue(){const visible=!!me&&['admin','propietario','jefe','rrpp'].includes(me.rol);socialMenu.hidden=!visible;socialMenu.querySelector('[data-reventa]').hidden=!['admin','propietario'].includes(me?.rol);}
setInterval(actualizarSocialVenue,1500);actualizarSocialVenue();
document.addEventListener('pointerdown',e=>{if(!e.target.closest('input,textarea,select,button,a,label,[contenteditable]')&&document.activeElement?.matches('input,textarea,[contenteditable]'))document.activeElement.blur();});
