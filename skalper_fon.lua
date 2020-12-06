
-------------------------- настойки робота -----------------------------------------------------------------
TRADE_ACC = "76649em"      		-- торговый счет 
CLASS = "SPBFUT"                -- код класса инструмента
SEC = "GDZ0"					-- код инструмента
lots = 1                        -- количество лотов(контрактов) в заявке
volum_anomal = 750				-- сколько лотов(контрактов) считать аномальным обьемом
otstup_steps_anomal = 10		-- отступ в шагах цены от аномальной заявки для выставления заявки
otstup_rinok = 10				-- минимальное количество шагов от рыночной цены до заявки
otstup_stop = 85				-- отступ в шагах цены до стоп-заявки
otstup_profit = 10				-- отступ в шагах цены до тейкпрофита
canSell = true 					-- можно продавать
canBuy = true					-- можно покупать 

-------------------------- набор переменных ----------------------------------------------------------------fXulGKbfvLGk100
uniq_trans_id  = 0				-- id транзакции
step = 0						-- шаг цены 
price = 0						-- текущая цена инструмента
trade_last = 0                  -- номер последней сделки(защита от повторных вызовов OnTrade)
anomalBuyPrice = 0				-- цена аномальной заявки в покупке
anomalSellPrice = 0				-- цена аномальной заявки в продаже
status_trade = "N"				-- статус торговли (N - нет заявок и сделок, S - выставлена заявка на продажу, B - выставлена заявка на покупку, ST - продано, BT - куплено)
arOrderNum = {}					-- массив номеров выставленных заявок, нужен для отмены
is_run = true
------------------------------------------------------------------------------------------------------------

function main()
	while is_run == true do
		if step == 0 then
			step = getSecurityInfo(CLASS, SEC).min_price_step 						-- получаем шаг цены
		end
		stakan = getQuoteLevel2(CLASS, SEC)											-- получаем стакан котировок
		max_bid = 0																	-- максимум лотов на покупку
		max_bid_price = 0															-- цена максимума покупки
		max_offer = 0																-- максимум лотов на продажу
		max_offer_price = 0															-- цена максимума продажи
		count_bid = 0																-- количество лотов на покупку
		count_offer = 0																-- количество лотов на продажу
		if canSell == true then														-- если разрешено продавать -> анализируем покупку в стакане
			for i = tonumber(stakan.bid_count), 1, -1 do							-- анализируем покупку
				if stakan.bid[i].quantity ~= nil then   							-- На некоторых ценах могут отсутствовать заявки
					if max_bid < tonumber(stakan.bid[i].quantity) then
						max_bid = tonumber(stakan.bid[i].quantity)
						max_bid_price = tonumber(stakan.bid[i].price)
					end
					count_bid = count_bid + tonumber(stakan.bid[i].quantity)
				end
			end
		end
		if canBuy == true then														-- если разрешено покупать -> анализируем продажу в стакане
			for i = 1, tonumber(stakan.offer_count), 1 do							-- анализируем продажу
				if stakan.offer[i].quantity ~= nil then   							-- На некоторых ценах могут отсутствовать заявки
					if max_offer < tonumber(stakan.offer[i].quantity) then
						max_offer = tonumber(stakan.offer[i].quantity)
						max_offer_price = tonumber(stakan.offer[i].price)
					end
					count_offer = count_offer + tonumber(stakan.offer[i].quantity)
				end
			end
		end
		price = getParamEx(CLASS, SEC, "last").param_value			 				-- получаем цену последней сделки(актуальная цена инструмента)
		if status_trade == "N" and max_bid > max_offer then
			if max_bid > volum_anomal then
				anomalBuyPrice = max_bid_price
				if (anomalBuyPrice + step*otstup_steps_anomal + step*otstup_rinok) < tonumber(price) then	-- на достаточном удалении от рынка
					write_log("Oбнаружена аномальная заявка на покупку "..tostring(max_bid).." лотов по цене "..tostring(anomalBuyPrice)..", текущая цена "..price)
					SendOrderStop("S", anomalBuyPrice + step*otstup_steps_anomal) 	-- выставляем стоп-заявку на продажу
				end
			end
		elseif status_trade == "N" and max_bid < max_offer then
			if max_offer > volum_anomal then
				anomalSellPrice = max_offer_price
				if (anomalSellPrice - step*otstup_steps_anomal - step*otstup_rinok) > tonumber(price) then	-- на достаточном удалении от рынка
					write_log("Oбнаружена аномальная заявка на продажу "..tostring(max_offer).." лотов по цене "..tostring(anomalSellPrice)..", текущая цена "..price)
					SendOrderStop("B", anomalSellPrice - step*otstup_steps_anomal) 	-- выставляем стоп-заявку на покупку
				end
			end
		end
		if max_bid < volum_anomal and status_trade == "S" then						-- пропал аномальный объем в покупке
			write_log("Aномальная заявка на покупку исчезла, текущая цена "..price)
			if #arOrderNum > 0 then KillStopOrder(arOrderNum) end					-- если еще не отработала - снимаем заявку
			anomalBuyPrice = 0
			sleep(500)																-- ждем пол секунды, чтоб успела сняться заявка
		end
		if max_offer < volum_anomal and status_trade == "B" then					-- пропал аномальный объем в продаже
			write_log("Aномальная заявка на продажу исчезла, текущая цена "..price)
			if arOrderNum > 0 then KillStopOrder(arOrderNum) end 					-- если еще не отработала - снимаем заявку
			anomalSellPrice = 0
			sleep(500)																-- ждем пол секунды, чтоб успела сняться заявка
		end
		sleep(500)																	-- ждем, чтоб успел смениться статус по предыдущему проходу(исключаем дубли)
	end
end

function SendOrderStopProfit(buy_sell, price_order, price_stop, lotov) 				-- функция выставления связанной стоп-заявки
	local priceForStop = 0
	if buy_sell == "S" then 
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
		["PRICE"] = tostring(priceForStop),											-- цена для исполнения стоп-заявки +- шаги для гарантии исполнения по рынку
		["STOP_ORDER_KIND"] = "WITH_LINKED_LIMIT_ORDER",
		["LINKED_ORDER_PRICE"] = tostring(price_order),								-- цена для связанной заявки
        ["KILL_IF_LINKED_ORDER_PARTLY_FILLED"] = "NO",							
		["QUANTITY"] = tostring(lotov),
		["CLIENT_CODE"] = "Skalper"..SEC.."_"..TRADE_ACC,
        ["TRANS_ID"] = tostring(uniq_trans_id)
    }
  local res = sendTransaction(trans)
  write_log("Bыставляем стоп "..buy_sell.." по цене : "..price_stop.." со связанной заявкой по цене: "..price_order.." текущая цена: "..price)
end

function SendOrderStop(buy_sell, price_stop) 										-- функция выставления стоп-заявки
	uniq_trans_id = uniq_trans_id + 1
	local priceForStop = 0
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
	write_log("Bыставляем стоп-заявку "..buy_sell.." по цене "..price_stop.." лотов "..lots.." текущая цена "..price)
	local res = sendTransaction(trans)
end

function KillStopOrder(arOrders)   													-- сниимаем стопы по номерам заявок
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
		write_log("Cнимаем стоп-заявку "..order_num)
		local res = sendTransaction(trans)
	end
	arOrderNum = {}																	-- очищаем массив заявок
end

function OnTrade(trade)																-- если произошла сделка
	if trade["brokerref"] == "Skalper"..SEC.."_"..TRADE_ACC then					-- если заявка выставлена этим скриптом(не ручная или другого скрипта)
		if trade_last < trade["trade_num"] and trade["sec_code"] == SEC then 		-- если сделка по заданному инструменту и номер сделки больше предыдущего
			if bit.band(trade["flags"], 4) > 0 then 								-- если сделка продажи
				if status_trade == "S" then
					SendOrderStopProfit("B", trade["price"] - otstup_profit*step, trade["price"] + otstup_stop*step, math.floor(trade["qty"]))	-- выставляем связанную заявку на покупку со стопом
				end
				write_log("Произошла продажа "..tostring(math.floor(trade["qty"])).." лотов по цене "..trade["price"])
			else 																	-- иначе сделка покупки
				if status_trade == "B" then
					SendOrderStopProfit("S", trade["price"] + otstup_profit*step, trade["price"] - otstup_stop*step, math.floor(trade["qty"]))	-- выставляем связанную заявку на продажу со стопом
				end
				write_log("Произошла покупка "..tostring(math.floor(trade["qty"])).." лотов по цене "..trade["price"])
			end
			trade_last = trade["trade_num"]
		end	
	end
end

function addOrder(orderNum)
	local found = false
	for key, order_num in pairs(arOrderNum) do										-- ищем номер в массиве, чтоб не дублировать
		if order_num == orderNum then
			found = true
		end
	end
	if found == false then 															-- если не найден такой номер заявки, то добавляем
		arOrderNum[#arOrderNum + 1] = orderNum
	end
end

function dellOrder(orderNum)
	local ar = {}
	for key, order_num in pairs(arOrderNum) do										-- перезаписываем массив, исключая удаляемый номер
		if order_num ~= orderNum then 
			ar[#ar + 1] = order_num
		end
	end
	arOrderNum = ar
end

function OnStopOrder(order_data)	
	if order_data["brokerref"] == "Skalper"..SEC.."_"..TRADE_ACC then												-- если заявка выставлена этим скриптом(не ручная или другого скрипта)	
		
		if bit.band(order_data["flags"], 4) > 0 then B_S = "S" else B_S = "B" end									-- стоп-заявка на продажу иначе на покупку
		if bit.band(order_data["flags"], 1) > 0 and bit.band(order_data["flags"], 2) == 0 then						-- стоп-заявка ВЫСТАВЛЕНА
			addOrder(order_data.order_num)
			if order_data.stop_order_type == 3 then																	-- если со связанной
				if B_S == "S" then status_trade = "BT" elseif B_S == "B" then status_trade = "ST" end
				write_log("Bыставлена стоп-заявка "..B_S.." №"..order_data.order_num.." лотов "..tostring(math.floor(order_data["qty"])).." по цене "..order_data["condition_price"].." со связанной заявкой по цене "..order_data["co_order_price"])
			elseif order_data.stop_order_type == 1 then																-- если просто стоп-заявка
				status_trade = B_S
				orderNum = order_data.order_num
				write_log("Bыставлена стоп-заявка "..B_S.." №"..order_data.order_num.." лотов "..tostring(math.floor(order_data["qty"])).." по цене "..order_data["condition_price"])
			end
		elseif bit.band(order_data["flags"], 1) == 0 and bit.band(order_data["flags"], 2) > 0 then					-- стоп-заявка СНЯТА
			dellOrder(order_data.order_num)
			if order_data.stop_order_type == 3 then																	-- если со связанной
				status_trade = "N"
				write_log("Снята стоп-заявка "..B_S.." №"..order_data.order_num.." лотов "..tostring(math.floor(order_data["qty"])).." по цене "..order_data["condition_price"].." исполнена связанная заявка по цене "..order_data["co_order_price"])
			elseif order_data.stop_order_type == 1 then																-- если просто стоп-заявка
				status_trade = "N"
				write_log("Cнята стоп-заявка "..B_S.." №"..order_data.order_num.." лотов "..tostring(math.floor(order_data["qty"])).." по цене "..order_data["condition_price"])
			end
		end
	end
end

function write_log(log_str)																-- функция записи логов
	dt = getInfoParam("SERVERTIME")										  				-- получаем время
	f = io.open(getScriptPath().."\\Scalper"..SEC.."_TrAc_"..TRADE_ACC..".txt","a")     -- открываем файл логов
	if f == nill then 													  
		f = io.open(getScriptPath().."\\Scalper"..SEC.."_TrAc_"..TRADE_ACC..".txt","w")	-- если файл не существует -> создаем
	end
	f:write(dt.."  "..log_str.." статус "..status_trade.."\n")							-- пишем лог и закрываем 
	f:flush()
	f:close()
end

function OnInit(s)																		-- инициализация
	write_log("--------3апуск скрипта--------")
end

function OnStop(s)
	write_log("-------Oстановка скрипта-------")
	is_run = false
end