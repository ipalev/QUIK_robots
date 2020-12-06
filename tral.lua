--Скрипт выставляет противоположную стоп-заявку при обнаружении сделки с целью защиты от убытков, 
--далее при движении тренда в сторону отдаленния от цены стопа скрипт передвигает стоп за трендом
-------------------------- настойки робота -----------------------------------------------------------------
TRADE_ACC = "SPBFUTK7pqs"      	-- торговый счет 
CLASS = "SPBFUT"                -- код класса инструмента
SEC = "BRQ0"					-- код инструмента
lots = 2                        -- количество лотов(контрактов) в заявке
steps_stop = 25					-- количество шагов до трейлинг стопа

-------------------------- набор переменных ----------------------------------------------------------------fXulGKbfvLGk100
uniq_trans_id  = 0				-- id транзакции
step = 0						-- шаг цены 
price = 0						-- текущая цена инструмента
status_trade = "N"				-- статус торговли (N - нет сделок, S - произошла продажа, B - произошла покупка)
stopOrderNum = 0				-- номер выставленной стоп-заявки, нужен для отмены
trade_last = 0                  -- номер последней сделки(защита от повторных вызовов OnTrade)
trade_price = 0					-- цена вхождения в позицию
last_price = 0					-- цена последней сделки
priceStopOrder = 0				-- цена срабатывания стоп-заявки
is_run = true
------------------------------------------------------------------------------------------------------------

function main()
	while is_run do 
		if step == 0 then
			step = getSecurityInfo(CLASS, SEC).min_price_step 						-- получаем шаг цены
		end
		last_price = getParamEx(CLASS, SEC, "last").param_value			 			-- получаем цену последней сделки(актуальная цена инструмента)
		tralingStop()
		sleep(100) 
	end
end

function tralingStop()																-- переностим стоп, если нужно
	if stopOrderNum > 0 then														-- если есть номер заявки и есть что снимать
		local killStop = false
		if status_trade == "S" and priceStopOrder > tonumber(last_price) + steps_stop*step and tonumber(trade_price) > tonumber(last_price) + 6*step then
			killStop = true
		elseif priceStopOrder ~= 0 and status_trade == "B" and priceStopOrder < tonumber(last_price) - steps_stop*step and tonumber(trade_price) < tonumber(last_price) - 6*step then
			killStop = true
		end
		if killStop == true then
			KillStopOrder(stopOrderNum)	
			sleep(500)																-- ждем пол секунды, чтоб отработало снятие заявки
			if stopOrderNum == 0 then												-- стоп-заявка снята - выставляем новую
				local price_for_stop = 0
				if status_trade == "S" then	
					if tonumber(last_price) + steps_stop*step > tonumber(trade_price) - 10*step then 
						price_for_stop = tonumber(trade_price) - 3*step
					else
						price_for_stop = tonumber(last_price) + steps_stop*step
					end
					SendOrderStop("B", price_for_stop)		
				elseif status_trade == "B" then
					if tonumber(last_price) - steps_stop*step < tonumber(trade_price) + 10*step then 
						price_for_stop = tonumber(trade_price) + 3*step
					else
						price_for_stop = tonumber(last_price) - steps_stop*step
					end
					SendOrderStop("S", price_for_stop)
				end
			end
		end
	end
end

function OnStopOrder(order_data)					
	if order_data["brokerref"] == "tral"..SEC then									-- если заявка выставлена этим скриптом(не ручная или другого скрипта)	
		if bit.band(order_data["flags"], 1) > 0 and bit.band(order_data["flags"], 2) == 0 then		
			stopOrderNum = order_data.order_num										-- стоп-заявка выставлекна - получаем номер заявки чтоб потом снимать	
		else																		-- стоп-заявка снята или исполнена
			stopOrderNum = 0
		end
	end
end

function SendOrderStop(buy_sell, price_stop) 										-- функция выставления стоп-заявки
	uniq_trans_id = uniq_trans_id + 1
	local priceForTrade = 0
	if buy_sell == "S" then 
		priceForTrade = price_stop - 10*step 
	elseif buy_sell == "B" then
		priceForTrade = price_stop + 10*step
	end
	local trans = {
        ["ACTION"] = "NEW_STOP_ORDER",
        ["CLASSCODE"] = CLASS,
        ["SECCODE"] = SEC,
        ["ACCOUNT"] = TRADE_ACC,
        ["OPERATION"] = buy_sell,
		["STOPPRICE"] = tostring(price_stop),										-- стоп-цена
		["PRICE"] = tostring(priceForTrade),										-- цена для исполнения стоп-заявки +- шаги для гарантии исполнения по рынку							
		["QUANTITY"] = tostring(lots),
		["CLIENT_CODE"] = "tral"..SEC,
        ["TRANS_ID"] = tostring(uniq_trans_id)
    }
	priceStopOrder = price_stop
	write_log("Bыставляем стоп-заявку "..buy_sell.." по цене "..price_stop.." лотов "..lots.." текущая цена "..last_price)
	local res = sendTransaction(trans)
end

function KillStopOrder(order_num)   												-- сниимаем стоп по номеру
	uniq_trans_id = uniq_trans_id + 1
	local trans = {
		["ACTION"] = "KILL_STOP_ORDER",
		["ACCOUNT"] = TRADE_ACC,
		["CLASSCODE"] = CLASS,
		["SECCODE"] = SEC,
		["STOP_ORDER_KEY"] = tostring(order_num),
		["CLIENT_CODE"] = "tral"..SEC,
		["TRANS_ID"] = tostring(uniq_trans_id)
    }
	write_log("Cнимаем стоп-заявку "..order_num)
	stopOrderNum = 0
	local res = sendTransaction(trans)
end

function OnTrade(trade)																-- если произошла сделка
	if trade_last < trade["trade_num"] and trade["sec_code"] == SEC then 			-- если сделка по заданному инструменту
		trade_price = trade["price"]
		if stopOrderNum > 0 then KillStopOrder(stopOrderNum) end
		if bit.band(trade["flags"], 4) > 0 then 									-- если сделка продажи
			write_log("Произошла продажа "..tostring(math.floor(trade["qty"])).." лотов по цене "..trade["price"])
			if status_trade == "B" then
				status_trade = "N"
			else 
				status_trade = "S"
				SendOrderStop("B", trade["price"] + steps_stop*step)
			end
		else 																		-- иначе сделка покупки
			write_log("Произошла покупка "..tostring(math.floor(trade["qty"])).." лотов по цене "..trade["price"])
			if status_trade == "S" then
				status_trade = "N" 
			else 
				status_trade = "B"
				SendOrderStop("S", trade["price"] - steps_stop*step)	
			end
			
		end
		trade_last = trade["trade_num"]												-- защита от повторных срабатываний по одной сделке
	end	
end

function write_log(log_str)															-- функция записи логов
	dt = getInfoParam("SERVERTIME")										  			-- получаем время
	f = io.open(getScriptPath().."\\Log_tral"..SEC..".txt","a")          			-- открываем файл логов
	if f == nill then 													  
		f = io.open(getScriptPath().."\\Log_tral"..SEC..".txt","w")					-- если файл не существует -> создаем
	end
	f:write(dt.."  "..log_str.." позиция "..status_trade.."\n")						-- пишем лог и закрываем 
	f:flush()
	f:close()
end

function OnInit(s)																	-- инициализация
	write_log("----------------------- Запуск скрипта ------------------------")
	message("START",2)
end

function OnStop(s)
	if stopOrderNum > 0 then KillStopOrder(stopOrderNum) end
	write_log("---------------------- Остановка скрипта ----------------------")
	is_run = false
end