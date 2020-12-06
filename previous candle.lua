-- Назначение скрипта: При запуске ждет начала часа, (минимум 11 утра по Москве) и смотрит предыдущую свечу.
-- Если предыдущая свеча растущая, определяем ее минимум и открываем позицию в продажу, если цена опускается до этого уровня и закрываем в конце часа по рынку.
-- Если предыдущая свеча падающая, определяем ее максимум и открываем позицию в покупку, если цена поднимается до этого уровня и закрываем в конце часа по рынку.
-- Если предыдущая свеча падающая нелевая(открылась и закрылась по одной цене) - ничего не делаем и ждем следующий час
-- добавлен трейлинг стоп с отступом steps_stop
-------------------------- настойки робота ---------------------------------------------
TRADE_ACC = "4110GNE"         	-- торговый счет 
CLASS = "SPBFUT"                -- код класса инструмента
SEC = "GDM0"					-- код инструмента GOLD-6.20
lots = 1                        -- количество лотов в заявке
steps_stop = 15					-- количество шагов до трейлинг стопа
-------------------------- набор переменных --------------------------------------------
uniq_trans_id  = 0				-- id транзакции
ds = nil 						-- объект график
step = 0						-- шаг цены 
hour = 9						-- текущий час, задаем 9, чтоб при наступлении 10 не бралясь в расчет предыдущая свеча, а со след. часа включалась и свеча была сегодняшняя и можно было брать значения
last_price = 0					-- цена последней сделки(актуальная цена инструмента)
exist_position = "N"			-- открытая позиция S - продажа, B - покупка, N - нет открытой позиции, NStop - позиция закрылась по стопу
trade_last = 0                  -- номер последней сделки(защита от повторных вызовов OnTrade)
candle_up = nil					-- предыдущая свеча растущая - true, падающая - false, nil - нулевая или еще не определена
allowed_trade = false			-- false не выставляем заявки (на старте, при смене таймфрейма и в клиринг), true - торгуем
stopOrderNum = 0 				-- номер стоп-заявки
priceStopOrder = 0				-- стоп-цена стоп-заявки
is_run = true
----------------------------------------------------------------------------------------

function main()
	while is_run do 
		if step == 0 then
			step = getSecurityInfo(CLASS, SEC).min_price_step 						-- получаем шаг цены
		end
		dt = getInfoParam("SERVERTIME")						  				 		-- получаем время сервера
		h_serv = dt:sub(1,2):gsub(":","")							  		 		-- берем час серверного времени, нужно чтоб получить минуты
		if tonumber(h_serv) < 10 then m = dt:sub(3,4) else m = dt:sub(4,5) end		-- берем минуты серверного времени
		if (m == "59" or (h_serv == "18" and tonumber(m) >= 44) or (h_serv == "23" and tonumber(m) >= 49)) or tonumber(h_serv) < 11 then
			Close_position()														-- закрываем позицию
		else
			ds = CreateDataSource(CLASS, SEC, INTERVAL_H1)							-- получаем часовой график - свечи
			if ds:Size() ~= nil then
				h = ds:T(ds:Size()).hour											-- получаем текущий час с графика
			end
			if hour == 9 and tonumber(h) > hour then hour = tonumber(h) end		-- чтоб не запускался сразу, а ждал следующий час
			last_price = getParamEx(CLASS, SEC, "last").param_value			 		-- получаем цену последней сделки(актуальная цена инструмента)
			tralingStop()															-- переностим стоп, если нужно
			if hour < tonumber(h) then												-- если наступил следующий час
				hour = tonumber(h)
				Close_position()
				sleep(500)
				write_log("Начало нового часа")
				allowed_trade = true
				price_O = ds:O(ds:Size()-1)											-- получаем цену открытия предыдущей свечи с графика
				price_C = ds:C(ds:Size()-1)											-- получаем цену закрытия предыдущей свечи с графика
				if tonumber(price_O) < tonumber(price_C) then						-- price_O < price_C -> свеча растущая
					candle_up = true
					price_L = ds:L(ds:Size()-1)										-- получаем минимум предыдущей свечи
					write_log("Предыдущая свеча растущая, минимальная цена "..price_L)
				elseif tonumber(price_O) > tonumber(price_C) then					-- price_O > price_C -> свеча падающая
					candle_up = false
					price_H = ds:H(ds:Size()-1)										-- получаем максимум предыдущей свечи
					write_log("Предыдущая свеча падающая, максимальная цена "..price_H)
				else 
					candle_up = nil 
					write_log("Предыдущая свеча нулевая, ждем")
				end	
			end
			if exist_position == "N" and allowed_trade == true then
				if candle_up == true and tonumber(last_price) <= price_L then 		-- цена упала до(ниже) минимальной цены предыдущей свечи
					SendOrder("S", tonumber(last_price) - 10*step) 					-- продаем и ставим стоп с отступом steps_stop 
					SendOrderStop("B", tonumber(last_price) + steps_stop*step)
					exist_position = "S"
				end
				if candle_up == false and tonumber(last_price) >= price_H then 		-- цена выросла до(выше) максимальной цены предыдущей свечи
					SendOrder("B", tonumber(last_price) + 10*step)					-- покупаем и ставим стоп с отступом steps_stop 
					SendOrderStop("S", tonumber(last_price) - steps_stop*step)
					exist_position = "B"
				end
			end
		end
		--message("last_price "..last_price.." step "..step.." hour "..hour.." h "..h.." price_O "..tostring(price_O).." price_C "..tostring(price_C).." candle_up "..tostring(candle_up).." price_L "..tostring(price_L).." price_H "..tostring(price_H),2)
		sleep(100) 
	end
end

function tralingStop()																-- переностим стоп, если нужно
	if stopOrderNum > 0 then														-- если есть номер заявки и есть что снимать
		local killStop = false
		if exist_position == "S" and priceStopOrder > tonumber(last_price) + steps_stop*step then
			killStop = true
		elseif priceStopOrder ~= 0 and exist_position == "B" and priceStopOrder < tonumber(last_price) - steps_stop*step then
			killStop = true
		end
		if killStop == true then
			KillStopOrder(stopOrderNum)	
			sleep(1000)																-- ждем секунду, чтоб отработало снятие заявки
			if stopOrderNum == 0 then												-- стоп-заявка снята - выставляем новую
				if exist_position == "S" then											
					SendOrderStop("B", tonumber(last_price) + steps_stop*step)		
				elseif exist_position == "B" then
					SendOrderStop("S", tonumber(last_price) - steps_stop*step)
				end
			end
		end
	end
end

function Close_position()
	if exist_position ~= "NStop" then												-- если не закрылась по стопу
		if exist_position ~= "N" then write_log("Конец таймфрейма, закрываем позицию") end
		if exist_position == "S" then SendOrder("B", last_price + 10*step) end
		if exist_position == "B" then SendOrder("S", last_price - 10*step) end
		allowed_trade = false
		if stopOrderNum > 0 then 													-- снимаем стоп
			KillStopOrder(stopOrderNum)
		end		
	end
	exist_position = "N"
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
		["CLIENT_CODE"] = "previous_candle"..SEC,
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
		["CLIENT_CODE"] = "previous_candle"..SEC,
		["TRANS_ID"] = tostring(uniq_trans_id)
    }
	write_log("Cнимаем стоп-заявку "..order_num)
	local res = sendTransaction(trans)
	stopOrderNum = 0
end

function SendOrder(buy_sell, price) 												-- функция выставления заявки
	uniq_trans_id = uniq_trans_id + 1
	local trans = {
        ["ACTION"] = "NEW_ORDER",
        ["CLASSCODE"] = CLASS,
        ["SECCODE"] = SEC,
        ["ACCOUNT"] = TRADE_ACC,
        ["OPERATION"] = buy_sell,
        ["PRICE"] = tostring(price),
        ["QUANTITY"] = tostring(lots),
		["CLIENT_CODE"] = "previous_candle"..SEC,
        ["TRANS_ID"] = tostring(uniq_trans_id)
    }
  local res = sendTransaction(trans)
  write_log("Заявка "..buy_sell.." по цене "..price.." текущая цена "..last_price)
end

function OnStopOrder(order_data)													
	--message("brokerref "..order_data["brokerref"],2)
	if order_data["brokerref"] == "previous_candle"..SEC then						-- если заявка выставлена этим скриптом(не ручная или другого скрипта)	
		if bit.band(order_data["flags"], 4) > 0 then B_S = "S" else B_S = "B" end	-- стоп-заявка на продажу иначе на покупку
		if bit.band(order_data["flags"], 1) > 0 and bit.band(order_data["flags"], 2) == 0 then		
			stopOrderNum = order_data.order_num										-- стоп-заявка выставлекна - получаем номер заявки чтоб потом снимать	
			write_log("Bыставлена стоп-заявка "..B_S.." №"..order_data.order_num.." лотов "..tostring(math.floor(order_data["qty"])).." по цене "..order_data["condition_price"])
		elseif bit.band(order_data["flags"], 1) == 0 and bit.band(order_data["flags"], 2) > 0 then					-- стоп-заявка снята
			stopOrderNum = 0
			write_log("Cнята стоп-заявка "..B_S.." №"..order_data.order_num.." лотов "..tostring(math.floor(order_data["qty"])).." по цене "..order_data["condition_price"])
		elseif bit.band(order_data["flags"], 1) == 0 and bit.band(order_data["co_order_price"], 2) == 0 then		-- стоп-заявка исполнена
			exist_position = "NStop"
			stopOrderNum = 0
		end
	end
end

function OnTrade(trade)																-- если произошла сделка
	if trade_last < trade["trade_num"] and trade["sec_code"] == SEC then 			-- если сделка по заданному инструменту
		if bit.band(trade["flags"], 4) > 0 then 									-- если сделка продажи
			write_log("Произошла продажа "..tostring(math.floor(trade["qty"])).." лотов по цене "..trade["price"])
		else 																		-- иначе сделка покупки
			write_log("Произошла покупка "..tostring(math.floor(trade["qty"])).." лотов по цене "..trade["price"])
		end
		trade_last = trade["trade_num"]												-- защита от повторных срабатываний по одной сделке
	end	
end

function write_log(log_str)															-- функция записи логов
	dt = getInfoParam("SERVERTIME")										  		-- получаем время
	f = io.open(getScriptPath().."\\Log_prev_candle"..SEC..".txt","a")          -- открываем файл логов
	if f == nill then 													  
		f = io.open(getScriptPath().."\\Log_prev_candle"..SEC..".txt","w")		-- если файл не существует -> создаем
	end
	f:write(dt.."  "..log_str.." позиция "..exist_position.."\n")									  		-- пишем лог и закрываем 
	f:flush()
	f:close()
end

function OnInit(s)																	-- инициализация
	write_log("----------------------- Запуск скрипта ------------------------")
	message("START",2)
end

function OnStop(s)
	--Close_position()
	write_log("---------------------- Остановка скрипта ----------------------")
	is_run = false
end
