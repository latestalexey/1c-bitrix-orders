SELECT 
r."Ф_НазваниеКратко"
, f."Ф_ИНН"
, r."Ф_КПП"
, r."Ф_РассчетныйСчет"
, r."Ф_Банк"
, "Ф_КоррСчет"
, "Ф_БИК"
, b."Сумма"
, b."№ счета"
, e.email
, e.telephone
, e."Имя"
FROM "Счета" b
JOIN "Фирма" f ON b."фирма" = f."КлючФирмы"
JOIN "ФирмаРеквизиты" r ON b."фирма" = r."КодФирмы" AND r."Ф_Активность" = TRUE
JOIN "Сотрудники" e ON b."Хозяин" = e."Менеджер"
WHERE 
b."№ счета" = 12201229
