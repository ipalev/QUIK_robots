-- набор основных функций для работы скриптов на Lua

-- функция записи логов write_log
-- принимает параметр fileName: имя файла без расширения (генерим в скриптах)
-- и log_str: строку для записи в файл лога
function write_log(log_str, fileName)										
	dt = getInfoParam("SERVERTIME")										  	-- получаем время
	if fileName == nil then
		fileName = 'log'
	end
	f = io.open(getScriptPath().."\\"..fileName..".txt","a")     			-- открываем файл логов
	if f == nill then 													  
		f = io.open(getScriptPath().."\\"..fileName..".txt","w")			-- если файл не существует -> создаем
	end
	f:write(dt.."  "..log_str.."\n")										-- пишем лог и закрываем 
	f:flush()
	f:close()
end

-- функция SendOrderStopProfit выставляет связанную стоп-заявку
-- параметр buy_sell: вид заявки "B" - купля или "S" - продажа
-- параметр price_order: цена для связанной заявкаи
-- параметр price_stop: цена стопа
-- параметр lots: количество лотов
-- параметр CLASS: класс инструмента
-- параметр SEC: код инструмента
-- параметр TRADE_ACC: торговый счет
-- step шаг цены инструмента
-- параметр uniq_trans_id: уникальный номер транзакции (генерируем порядковые номера в скрипте)
-- LogFileName: имя файла для записи логов
function SendOrderStopProfit(buy_sell, price_order, price_stop, lots, CLASS, SEC, TRADE_ACC, step, uniq_trans_id, LogFileName) 				
	local priceForStop = 0
	if buy_sell == "S" then 														--  добавляем 10 шагов цены для гарантии исполнения по рынку
		priceForStop = price_stop - 10*step 
	elseif buy_sell == "B" then
		priceForStop = price_stop + 10*step
	end
	uniq_trans_id = uniq_trans_id + 1
	local trans = {
        ["ACTION"] = "NEW_STOP_ORDER",
        ["CLASSCODE"] = CLASS,
        ["SECCODE"] = SEC,
        ["ACCOUNT"] = TRADE_ACC,
        ["OPERATION"] = buy_sell,
		["STOPPRICE"] = tostring(price_stop),										-- стоп-цена
		["PRICE"] = tostring(priceForStop),											-- цена для исполнения стоп-заявки +- шаги
		["STOP_ORDER_KIND"] = "WITH_LINKED_LIMIT_ORDER",
		["LINKED_ORDER_PRICE"] = tostring(price_order),								-- цена для связанной заявки
        ["KILL_IF_LINKED_ORDER_PARTLY_FILLED"] = "NO",							
		["QUANTITY"] = tostring(lots),
		["CLIENT_CODE"] = "Skalper"..SEC.."_"..TRADE_ACC,
        ["TRANS_ID"] = tostring(uniq_trans_id)
    }
  local res = sendTransaction(trans)
  write_log("Send stop order "..buy_sell.." price-stop: "..price_stop.." with a linked bid by price: "..price_order.." lots: "..lots.." last price: "..price, LogFileName)
end

-- функция SendOrderStop выставляет стоп-заявки
-- принимает параметр buy_sell: вид заявки "B" - купля или "S" - продажа 
-- параметр price_stop: цена стопа
-- параметр lots: количество лотов
-- параметр CLASS: класс инструмента
-- параметр SEC: код инструмента
-- параметр TRADE_ACC: торговый счет
-- step шаг цены инструмента
-- параметр uniq_trans_id: уникальный номер транзакции (генерируем порядковые номера в скрипте)
-- LogFileName: имя файла для записи логов
function SendOrderStop(buy_sell, price_stop, lots, CLASS, SEC, TRADE_ACC, step, uniq_trans_id, LogFileName)
	uniq_trans_id = uniq_trans_id + 1
	local priceForStop = 0															--  добавляем 10 шагов цены для гарантии исполнения по рынку
	if buy_sell == "S" then 
		priceForStop = price_stop - 10*step 
	elseif buy_sell == "B" then
		priceForStop = price_stop + 10*step
	end
	local trans = {
        ["ACTION"] = "NEW_STOP_ORDER",
        ["CLASSCODE"] = CLASS,
        ["SECCODE"] = SEC,
        ["ACCOUNT"] = TRADE_ACC,
        ["OPERATION"] = buy_sell,
		["STOPPRICE"] = tostring(price_stop),										-- стоп-цена
		["PRICE"] = tostring(priceForStop),											-- цена для исполнения стоп-заявки +- шаги для гарантии исполнения по рынку							
		["QUANTITY"] = tostring(lots),
		["CLIENT_CODE"] = "Skalper"..SEC.."_"..TRADE_ACC,
        ["TRANS_ID"] = tostring(uniq_trans_id)
    }
	status_trade = buy_sell
	write_log("Send stop order "..buy_sell.." price-stop: "..price_stop.." lots "..lots.." last price: "..price, LogFileName)
	local res = sendTransaction(trans)
end

-- функция KillStopOrder сниимает стопы
-- принимает массив с номерами заявок для снятия
-- и uniq_trans_id: уникальный номер транзакции (генерируем порядковые номера в скрипте)
-- LogFileName: имя файла для записи логов
function KillStopOrder(arOrders, uniq_trans_id, LogFileName)   													
	for key, order_num in pairs(arOrders) do
		uniq_trans_id = uniq_trans_id + 1
		local trans = {
			["ACTION"] = "KILL_STOP_ORDER",
			["ACCOUNT"] = TRADE_ACC,
			["CLASSCODE"] = CLASS,
			["SECCODE"] = SEC,
			["STOP_ORDER_KEY"] = tostring(order_num),
			["CLIENT_CODE"] = "Skalper"..SEC.."_"..TRADE_ACC,
			["TRANS_ID"] = tostring(uniq_trans_id)
		}
		write_log("Kill stop order: "..order_num, LogFileName)
		local res = sendTransaction(trans)
	end
end

-- функция SendOrder выставляет простую заявку
-- параметр buy_sell: вид заявки "B" - купля или "S" - продажа 
-- параметр price: цена
-- параметр lots: количество лотов
-- параметр CLASS: класс инструмента
-- параметр SEC: код инструмента
-- параметр TRADE_ACC: торговый счет
-- параметр uniq_trans_id: уникальный номер транзакции (генерируем порядковые номера в скрипте)
-- LogFileName: имя файла для записи логов
function SendOrder(buy_sell, price, lots, CLASS, SEC, TRADE_ACC, uniq_trans_id, LogFileName)
  uniq_trans_id = uniq_trans_id + 1
  local trans = {
          ["ACTION"] = "NEW_ORDER",
          ["CLASSCODE"] = CLASS,
          ["SECCODE"] = SEC,
          ["ACCOUNT"] = TRADE_ACC,
          ["OPERATION"] = buy_sell,
          ["PRICE"] = tostring(price),
          ["QUANTITY"] = tostring(lots),
          ["TRANS_ID"] = tostring(uniq_trans_id)
                }
  local res = sendTransaction(trans)
  write_log("Send order "..buy_sell.." instrument SEC: "..SEC.." price "..price.." lots: "..lots, LogFileName)
end

-- функция getBestPriceFromGlass возвращает лучшую цену спроса или предложения из стакана(стакан по инструменту должен быть открыт)
-- параметр CLASS: класс инструмента
-- параметр SEC: код инструмента
-- параметр BidOffer: "BID" - отдаст цену спроса, "OFFER" - предложения
function getBestPriceFromGlass(CLASS, SEC, BidOffer)
	glass = getQuoteLevel2(CLASS, SEC)
	if glass.bid ~= nil then
		if BidOffer == 'BID' then
			return glass.bid[tonumber(glass.bid_count)].price
		elseif  BidOffer == 'OFFER' then
			return glass.offer[1].price
		end
	else 
		return nil
	end
end