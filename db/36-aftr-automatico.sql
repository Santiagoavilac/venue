-- AFTR automático: todo boliche activo y todo evento publicado en Venue sale
-- en AFTR sin tocar nada. aftr_visible / aftr_publico pasan a ser "apagar":
-- quedan en true salvo que el boliche no quiera aparecer.
--
-- Las listas NO se abren solas (aftr_publica sigue en false): son de los
-- rrpp, y abrir una al público lo decide el boliche.
--
-- Re-ejecutable.

alter table clubs   alter column aftr_visible set default true;
alter table eventos alter column aftr_publico set default true;

update clubs   set aftr_visible = true where not aftr_visible;
update eventos set aftr_publico = true where not aftr_publico;
