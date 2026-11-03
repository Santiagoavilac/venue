'use strict';
let _socialAftr;
function socialAftr() {
  return _socialAftr ||= AftrSocial.create({
    client: sb, user: () => E.sesion?.user, login: asegurarCuenta, notice: avisar,
    events: () => cargarEventos(), walletRefresh: () => cargarAccesos(),
    storyCTA: h => {
      sessionStorage.setItem('aftr.historia',JSON.stringify({id:h.id,evento:h.evento_id,vence:h.vence_at,cta:h.cta}));
      location.hash=`#/evento/${h.evento_id}?historia=${h.id}`;
    }
  });
}
function historiaCompra(evento,cta) {
  try { const h=JSON.parse(sessionStorage.getItem('aftr.historia'));
    return h?.evento===evento && h.cta===cta && Date.parse(h.vence)>Date.now()?h.id:null;
  } catch { return null; }
}
document.addEventListener('pointerdown',e=>{
  if(!e.target.closest('input,textarea,select,button,a,label,[contenteditable]') && document.activeElement?.matches('input,textarea,[contenteditable]'))document.activeElement.blur();
});
