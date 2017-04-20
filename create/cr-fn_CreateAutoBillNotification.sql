-- Function: "fnCreateAutoBillNotification"(integer)

-- DROP FUNCTION "fnCreateAutoBillNotification"(integer);

-- a_reason < 0 - причина неотправки письма-извещения клиенту
-- a_reason > 1 - причина неполного автосчёта
CREATE OR REPLACE FUNCTION "fnCreateAutoBillNotification"(order_id integer, a_reason integer)
  RETURNS integer AS
$BODY$DECLARE 
mstr varchar(255);
message_id integer;
loc_bill_no INTEGER;
loc_str VARCHAR := '';
BEGIN 
    SELECT "Счет", "Дата", "Время" INTO loc_bill_no FROM bx_order WHERE "Номер" = order_id;

    mstr := E'Создан автосчёт '|| to_char(loc_bill_no, 'FM9999-9999')|| E' по заказу ' || order_id::VARCHAR || E' на kipspb.ru\n'; 
    IF a_reason = 2 THEN
       loc_str := E'Встретились несинхронизированные позиции.';
    ELSIF a_reason = 6 THEN
       loc_str := E'Для некоторых позиций не хватило товара со склада.';
    ELSIF a_reason = 7 THEN
       loc_str := E'Некоторые резервы не удалось поставить.';
    END IF; 
    -- mstr := E'Создан автосчёт '|| to_char(loc_bill_no, 'FM9999-9999') 
    mstr := mstr || loc_str || E'\nПроверьте его, пожалуйста!';
    loc_str := '';

    IF a_reason = -1 THEN
       loc_str := E'\nЗаказ с комментарием покупателя.';
    ELSIF a_reason = -2 THEN
       loc_str := E'\nПокупателем физ.лицом выбрана доставка курьерской службой.';
    ELSIF a_reason = -3 THEN
       loc_str := E'\nПокупателем юр.лицом выбрана доставка, несовместимая с автосчётом.';
    END IF; 

    IF length(loc_str) > 0 THEN
       mstr := mstr || loc_str ||  E'\nАвтосчёт НЕ отправлен клиенту.';
    END IF; 

    WITH inserted AS (
        INSERT INTO СчетОчередьСообщений ("№ счета", msg_to, msg, msg_type)
               values (loc_bill_no, 1, mstr, 9) RETURNING id
    )
    SELECT id INTO message_id FROM inserted;

    RETURN message_id;
END;$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION "fnCreateAutoBillNotification"(integer, integer)
  OWNER TO arc_energo;
