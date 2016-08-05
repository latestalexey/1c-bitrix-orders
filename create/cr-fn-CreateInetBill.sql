-- Function: fn_createinetbill(integer)

-- DROP FUNCTION fn_createinetbill(integer);

CREATE OR REPLACE FUNCTION fn_createinetbill(bx_order_no integer)
  RETURNS INTEGER AS
$BODY$
DECLARE
   oi record;
   o record;
   soderg RECORD;
   bill record;
   KS integer;
   CreateResult integer;
   -- arrOrderItems varchar[];
   -- arr_OrderItems t_order_item[];
   item RECORD;
   item_str varchar;
   item_id integer;
   Npp INTEGER;
   INN VARCHAR;
   KPP VARCHAR;
   VAT numeric;
   bill_no INTEGER;
   Price numeric;
   bx_sum NUMERIC;
   EmpRec RECORD;
   loc_OrderItemProcessingTime varchar;
   inserted_bill_item RECORD;
   our_emp_id INTEGER;
   vendor_id INTEGER;
   flgOwen BOOLEAN;
   skipCheckOwen BOOLEAN;
   ourFirm VARCHAR;
   debug_rec RECORD;
   loc_in_stock NUMERIC; 
BEGIN
RAISE NOTICE '##################### Начало fn_createinetbill, заказ=%', bx_order_no;
INSERT INTO aub_log(bx_order_no, descr) VALUES(bx_order_no, 'Начало обработки заказа');

SELECT bo.*, bb.bx_name, bf.fvalue AS email INTO o
    FROM vw_bx_actual_order bo, bx_buyer bb, bx_order_feature bf
    WHERE 
        bo."Номер" = bx_order_no
        AND bo.bx_buyer_id = bb.bx_buyer_id
        AND (bo."Номер" = bf."bx_order_Номер" AND bf.fname = 'Контактный Email')
UNION
SELECT bo.*, bb.bx_name, bf.fvalue AS email
    FROM vw_bx_actual_order bo, bx_buyer bb, bx_order_feature bf
    WHERE 
        bo."Номер" = bx_order_no
        AND bo.bx_buyer_id = bb.bx_buyer_id
        AND (bo."Номер" = bf."bx_order_Номер" AND bf.fname = 'EMail');     

IF o IS NULL THEN
   CreateResult := 4; -- отменённый или неполный заказ, покупатель или отсутствуют оба 'EMail' и 'Контактный email'
ELSE
    CreateResult := 3; -- пустой состав заказа
    bx_sum := 0;
END IF;

CREATE TEMPORARY TABLE IF NOT EXISTS tmp_order_items(ks integer, oi_okei_code integer, oi_measure_unit character varying(50), oi_quantity numeric(18,3), item_str character varying);
TRUNCATE tmp_order_items; -- if exists

flgOwen := False;
skipCheckOwen := FALSE;

FOR oi in (SELECT bx_order_item.*
                , lpad(bx_order_item_feature.fvalue::VARCHAR, 12, '0')  as mod_id
            FROM bx_order_item
            LEFT JOIN bx_order_item_feature ON bx_order_item_feature.bx_order_item_id = bx_order_item."Ид" 
                                    AND bx_order_item_feature."bx_order_Номер" = bx_order_item."bx_order_Номер"
                                    AND bx_order_item_feature.fname = 'КодМодификации'
            WHERE o."Номер" = bx_order_item."bx_order_Номер" 
              AND POSITION(':' in bx_order_item."Наименование") = 0
UNION
           SELECT bx_order_item.*
                , regexp_replace(bx_order_item."Наименование", '^.*: ', '')::VARCHAR AS mod_id
           FROM bx_order_item
           WHERE o."Номер" = bx_order_item."bx_order_Номер" 
             AND POSITION(':' in bx_order_item."Наименование") > 0
           ORDER BY id 
) LOOP
    --
    RAISE NOTICE 'Заказ=%, обрабатываем Товар=%, oi.mod_id=%', oi."bx_order_Номер", oi.Наименование, oi.mod_id;
    INSERT INTO aub_log(bx_order_no, mod_id, descr) VALUES(bx_order_no, oi.mod_id, format('Старт %s', oi.Наименование));
    SELECT "КодСодержания","Поставщик" INTO KS, vendor_id from vwsyncdev 
            WHERE vwsyncdev.mod_id = oi.mod_id;
    RAISE NOTICE 'KS=%, vendor_id=%', KS, vendor_id;
    
    IF (KS is null) THEN
       CreateResult := 2; -- есть не синхронизированная позиция в заказе
       RAISE NOTICE 'В заказе %  не синхронизированная позиция с mod_id=%', bx_order_no, oi.mod_id;
       INSERT INTO aub_log(bx_order_no, mod_id, descr, res_code) VALUES(bx_order_no, oi.mod_id,  format(
        '%s - не синхронизированная позиция', oi.Наименование
       ), CreateResult );
       -- не прерываем обработку! EXIT; -- дальше не проверяем
    ELSE
       -- если Овен, "Поставщик" = 30049
       IF 30049 = vendor_id AND NOT skipCheckOwen THEN
         flgOwen := TRUE;
       ELSE
         flgOwen := False;
         skipCheckOwen := TRUE; -- если встретился 'не Овен', больше не проверяем
       END IF;
       
       loc_in_stock := is_in_stock(KS, oi."Количество");
       IF loc_in_stock >= oi."Количество" THEN
          IF CreateResult NOT IN (2,6) THEN 
             CreateResult := 1; -- позиция заказа синхронизирована
          END IF;    
          item_str := format(' %s, %s, ''%s'', %s', KS, oi."Код", (SELECT "ЕдИзм" FROM "ОКЕИ" WHERE "КодОКЕИ" = oi."Код") , oi."Количество");
          -- 
          INSERT INTO aub_log(bx_order_no, mod_id, descr, res_code) VALUES(bx_order_no, oi.mod_id, format(
             '%s(KS=%s) синхронизирован и есть на складе', oi.Наименование, KS
          ), 1 ); 
          RAISE NOTICE '   строка заказа item_str=%', item_str;
          -- arrOrderItems := array_append(arrOrderItems, item_str);
          INSERT INTO tmp_order_items(ks, oi_okei_code, oi_measure_unit, oi_quantity, item_str)
                 VALUES (KS, oi."Код", (SELECT "ЕдИзм" FROM "ОКЕИ" WHERE "КодОКЕИ" = oi."Код") , oi."Количество", item_str);
       ELSE
          CreateResult := 6; -- позиция заказа синхронизирована, но недостаточно количества
          RAISE NOTICE 'Для KS=% нет достаточного количества=%', KS, oi."Количество";
          INSERT INTO aub_log(bx_order_no, mod_id, descr, res_code) VALUES(bx_order_no, oi.mod_id, format(
            'Для %(KS=%s) нужно [%s], доступно [%s]', oi.Наименование, KS, oi."Количество", loc_in_stock
          ), CreateResult );
          -- не прерываем обработку! EXIT; -- дальше не проверяем
       END IF;    
    END IF;    
    -- Для контроля "потерянных" позиций
    bx_sum := bx_sum + oi."Сумма";
    RAISE NOTICE 'CreateResult = %', CreateResult;
    INSERT INTO aub_log(bx_order_no, mod_id, descr) VALUES(bx_order_no,  oi.mod_id, format(
        'Финиш %s , результат=%s', oi.Наименование, CreateResult
    ));
END LOOP; -- orders item

-- Контроль "потерянных" позиций по сумме
IF (o."Сумма" <> bx_sum) AND (1 = CreateResult) THEN
   CreateResult := 5;
   RAISE NOTICE 'Не совпадают bx_order_sum=%, items_sum=%', o."Сумма", bx_sum; 
END IF;
--  
IF (CreateResult = 1) THEN -- все позиции заказа синхронизированы и достаточное количество на складе
    EmpRec := fn_GetEmpCode(o.bx_buyer_id, o."Номер");
    RAISE NOTICE 'FirmCode=%, EmpCode=%', EmpRec."Код", EmpRec."КодРаботника" ;

    IF EmpRec."Код" is NOT NULL THEN
        ourFirm := getFirm(EmpRec."Код", flgOwen);
        loc_OrderItemProcessingTime := 'В наличии'; -- для всего счёта: если Отправка, '1...3 рабочих дня' иначе '!Со склада'
        bill := fn_InsertBill(o."Сумма", o."Номер", EmpRec."Код", EmpRec."КодРаботника", ourFirm);
        Npp := 1;
        VAT := bill."ставкаНДС";
        bill_no := bill."№ счета";

        -- FOREACH item IN ARRAY arrOrderItems loop
        FOR item in SELECT * FROM tmp_order_items LOOP
            -- здесь м.б. только "В наличии"
            -- SELECT OrderItem_ProcessingTime() INTO loc_OrderItemProcessingTime; -- by KS
            -- SELECT devmod.get_def_time_delivery(oi.mod_id) INTO loc_OrderItemProcessingTime;
            SELECT "НазваниевСчет", "Цена" INTO soderg FROM "Содержание" s WHERE s."КодСодержания" = item.ks;
            Price := soderg."Цена"*100/(100 + VAT);
            --
            RAISE NOTICE 'bill_no=%, item.ks=%', bill."№ счета", item.ks;
            -- TODO Выявлять услугу "Оплата доставки"

           -- IF do_reserve_bill_item(EmpRec."Код", bill."Хозяин", (item).ks, (item).oi_quantity) THEN 

                    with inserted as (
                       insert into "Содержание счета"
                            ("КодПозиции",
                            "№ счета",
                            "КодСодержания", "КодОКЕИ", "Ед Изм", "Кол-во",
                            "Срок2",
                            "ПозицияСчета", "Наименование",
                            "Цена", "ЦенаНДС",
                            "Гдезакупать")
                            values ((select max("КодПозиции")+1 from "Содержание счета"),
                            bill_no,
                            item.ks, item.oi_okei_code, item.oi_measure_unit, item.oi_quantity,
                            loc_orderitemprocessingtime,
                            npp, soderg."НазваниевСчет",
                            round(price, 2), soderg."Цена",
                            "Рез.склада") 
                     returning * 
                     ) select * into inserted_bill_item from inserted;
                     Npp := Npp+1;

                    /**/
                    SELECT "Номер" INTO our_emp_id FROM "Сотрудники" WHERE bill."Хозяин" = "Менеджер";
                    INSERT INTO "Резерв"("Счет", "Резерв", "Подкого_Код", "Когда", "Докуда", "Кем_Номер", "КодПозиции", "КодСодержания", "ПримечаниеСклада", "КодСклада") 
                                  VALUES(bill."№ счета", item.oi_quantity, EmpRec."Код", now(), now()+'10 days'::interval, our_emp_id, inserted_bill_item."КодПозиции", item.ks, '', 2);
                    /**/
                /**
                    EXECUTE E'INSERT INTO "Содержание счета" '
                            || E'("КодПозиции", '
                            || E'"№ счета", '
                            || E'"КодСодержания", "КодОКЕИ", "Ед Изм", "Кол-во", '
                            || E'"Срок2", '
                            || E'"ПозицияСчета", "Наименование", '
                            || E'"Цена", "ЦенаНДС") '
                            || E'VALUES ((SELECT MAX("КодПозиции")+1 FROM "Содержание счета"), '
                            || bill_no || ', ' -- '"№ счета"
                            || (item).item_str || ', '  -- "КодСодержания", "КодОКЕИ", "Ед Изм", "Кол-во",'
                            || E'''' || loc_OrderItemProcessingTime || ''', '
                            || Npp || ', ''' || soderg."НазваниевСчет" || ''', '  -- '"ПозицияСчета", "Наименование", '
                            || round(Price, 2)  || ', ' || soderg."Цена" -- '"Цена", "ЦенаНДС") '
                            || ');' ;
                    Npp := Npp+1;      
                **/
           -- END IF; -- do_reserve  
        END LOOP;

        INSERT INTO aub_log(bx_order_no, descr, res_code) VALUES(bx_order_no, format(
            'Автосчёт %s создан', bill."№ счета"
        ), 99);
    ELSE -- Код IS NULL
        CreateResult := 9; -- bad Firm
        RAISE NOTICE 'Невозможно определить Код Предприятия. Счёт не создан. bx_order.billcreated=%', CreateResult;
    END IF;
END IF;

UPDATE bx_order SET billcreated = CreateResult, "Счет" = bill_no WHERE "Номер" = bx_order_no ;

TRUNCATE tmp_order_items;

RETURN CreateResult;
END;$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION fn_createinetbill(integer)
  OWNER TO arc_energo;
