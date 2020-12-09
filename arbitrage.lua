-- Арбитражный робот получает коэффициент из текущих цен для набора инструментов и получает коэффициент на основе которого принимается решение об открытии и закрытии позиций
-- параметры инструментов задаются в таблице(массиве) arTools, можно задать как один набор значений для одного инструментаа, так и несколько (неограничено)
-- формула расчета коэффициента прописывается в функции getK (для каждого набора инструментов своя)

-------------------------- настойки робота ------------------------------------------------------------------------------------------
arTools = {}																		-- таблица с параметрами инструментов
----------------------- инструмент 1
arTools[1] = {
	['SEC'] = 'MXZ0',																-- SEC код инструмента 
	['CLASS'] = 'SPBFUT',															-- CLASS класс инструмента 
	['lots'] = 1,																	-- количество лотов для заявок
	['buy_sell'] = "S",																-- вид заявки при открытии позиции купля продажа "B" - купля, "S" - продажа
	['bid_offer'] = "BID"															-- цена из стакана для расчета коэффициента "BID" - спрос, - "OFFER" - предложение
}
----------------------- инструмент 2
arTools[2] = {
	['SEC'] = 'SiZ0',																-- SEC код инструмента 
	['CLASS'] = 'SPBFUT',															-- CLASS класс инструмента
	['lots'] = 1,																	-- количество лотов для заявок
	['buy_sell'] = "B",																-- вид заявки при открытии позиции "B" - купля, "S" - продажа
	['bid_offer'] = "OFFER"															-- цена из стакана для расчета коэффициента "BID" - спрос, - "OFFER" - предложение
}
----------------------- инструмент 3
arTools[3] = {
	['SEC'] = 'RIZ0',																-- SEC код инструмента
	['CLASS'] = 'SPBFUT',															-- CLASS класс инструмента
	['lots'] = 1,																	-- количество лотов для заявок
	['buy_sell'] = "B",																-- вид заявки при открытии позиции "B" - купля, "S" - продажа
	['bid_offer'] = "OFFER"															-- цена из стакана для расчета коэффициента "BID" - спрос, - "OFFER" - предложение
}
-------------------------------------
kOpen = 170																			-- значение коэффициента для открытия позиций(если превышает открываем позиции)
kClose = -180																		-- значение коэффициента для закрытия позиций (если становится меньше закрываем позиции)
profitClose = 10																	-- суммарный профит по всем инструментам для закрытия позиции
logCountLoop = 30																	-- номер прохода для логирования расчета коэффициента
-------------------------------------														
TRADE_ACC = "SPBFUT00APS"      														-- торговый счет 
-------------------------служебные переменные----------------------------------------------------------------------------------------
profit = 0																			-- суммарный профит при открытых позициях
logFileName = 'LogArbitrage_EXAMPLE' 												-- имя файла логов
uniq_trans_id  = 0																	-- id транзакции
k = nil																				-- расчетный коэффициент
isOpenPosition = false																-- открыта позиция
loop = 0																			-- номер прохода в цикле главной функцуии
is_run = true
dofile(getScriptPath().."\\func\\functions.lua")									-- подключаем набор функций
-------------------------------------------------------------------------------------------------------------------------------------

function getK(arParam)																-- получаем коэффициент для принятия решения
	if arParam == nil or arParam[1] == nil then
		return nil
	end
	for key, param in pairs(arParam) do												-- если хоть один параметр не получен - возвращаем nil
		if param == nil then
			return nil
		end
	end
	k = arParam[1] * 4809707787.4153 / arParam[2] / 152678.585651 - arParam[3]		-- формула расчета настраивается здесь(разделитель дробной части обязательно "точка")
	return k
end

function main()
	while is_run == true do
		loop = loop + 1
		local prices = {}
		local logStr = ''
		for key, tool in pairs(arTools) do											-- получаем нужные цены для каждого ниструмента из стаканов согласно заданным параметрам 
			local bid_offer = ''
			if isOpenPosition == true then											-- при открытой позиции берем противоположные значения из стакана (OFFER -> BID) для расчета k
				bid_offer = inversionBidOffer(tool['bid_offer'])
			else
				bid_offer = tool['bid_offer']
			end
			prices[key] = getBestPriceFromGlass(tool['CLASS'], tool['SEC'], bid_offer)
			if loop == logCountLoop and prices[key] ~= nil then 					-- готовим строку для лога (цены из стакана)
				logStr = logStr..' priceTool'..key..' = '..prices[key]
			end
		end
		if isOpenPosition == true and profitClose > 0 then							-- при открытых позициях считаем профит, если задан profitClose
			profit = 0
			for key, tool in pairs(arTools) do
				if tool['buy_sell'] == 'B' then										-- если покупали - из текущей цены вычитаем цену открытия позиции 
					profit = profit + tonumber(prices[key]) - tonumber(tool['priceOpen'])
				end
				if tool['buy_sell'] == 'S' then										-- если продавали - из цены открытия позиции вычитаем текущую цену
					profit = profit + tonumber(tool['priceOpen']) - tonumber(prices[key])
				end
			end
			logStr = logStr..' profit: '..profit
		end
		k = getK(prices)
		if loop == logCountLoop and k ~= nil then									-- на каждом указанном в logCountLoop шаге пишем лог расчета коэффициента
			logStr = logStr..' -> k = '..k
			write_log(logStr, logFileName)
			loop = 0
		end
		if k ~=nil and isOpenPosition == true and (k < kClose or profit > profitClose) then	-- если открыта позиция и коэффициент менее заданного в параметре kClose или профит достиг желаемого -> закрываем позицию
			write_log("k = "..k.." -> close position  profit: "..profit, logFileName)
			open_closePosition('close')
		elseif k ~=nil and isOpenPosition == false and k > kOpen then				-- если позиция не открыта и коэффициент более заданного в параметре kOpen -> открываем позицию
			write_log("k = "..k.." -> open position", logFileName)
			for key, tool in pairs(arTools) do										-- при открытии позиций записываем текущие цены инструментов для расчета профита
				tool['priceOpen'] = prices[key]
			end
			open_closePosition('open')
		end
		sleep(500)
	end
end

function open_closePosition(open_close)												-- открываем или закрываем позиции в зависимости от параметра open_close
	for key, tool in pairs(arTools) do
		local buy_sell = ''
		if open_close == "open" then
			buy_sell = tool['buy_sell']
		elseif open_close == "close" then											-- если позиции закрываем - инвертируем парапметр buy_sell
			buy_sell = inversionBuySell(tool['buy_sell'])
		end
		if tool['step'] == nil then													-- получаем шаг цены инструмента, если еще не получен
			tool['step'] = getSecurityInfo(tool['CLASS'], tool['SEC']).min_price_step
		end
		uniq_trans_id = uniq_trans_id + 1
		local price = getParamEx(tool['CLASS'], tool['SEC'], "last").param_value 	-- получаем цену последней сделки(актуальную рыночную)
		if 	buy_sell == "B" then													-- добавляем шаги для гарантированной покупки по рынку
			price = price + 10 * tool['step']
		end
		if 	buy_sell== "S"	then													-- вычитаем шаги для гарантированной продажи по рынку
			price = price - 10 * tool['step']
		end
		inversionOpenClosePosition()												-- инвертируем значение открытой позиции
		if price == math.floor(price) then											-- убираем точку из цены (123.0 -> 123) тупой баг квика
			price = math.floor(price)
		end
		write_log('price open position '..tool['SEC']..': '..tool['priceOpen'], logFileName) 
		SendOrder(buy_sell, price, tool['lots'], tool['CLASS'], tool['SEC'], TRADE_ACC, uniq_trans_id, logFileName) -- выставляем заявку
	end
end

function inversionOpenClosePosition()												-- инвертируем значение открытости позиции при ее открытии/закрытии
	if isOpenPosition == true then
		isOpenPosition = false
	else 
		isOpenPosition = true
	end
end

function inversionBuySell(buy_sell)													-- инвертируем параметр buy_sell заявки для закрытия позиций
	if buy_sell == "S" then 
		return "B"
	elseif buy_sell == "B" then 
		return "S"
	end
end

function inversionBidOffer(bid_offer)												-- инвертируем bid_offer чтоб брать противоположные значения для рассчета коэффициента при открытой позиции
	if bid_offer == 'BID' then
		return 'OFFER'
	elseif bid_offer == 'OFFER' then
		return 'BID'
	end
end

function OnInit(s)																	-- инициализация
	write_log("--------3апуск скрипта--------", logFileName)	
end

function OnStop(s)																	-- остановка скрипта
	if isOpenPosition == true then
		open_closePosition('close')													-- если открыта позиция -> закрываем
	end
	write_log("-------Oстановка скрипта-------", logFileName)
	is_run = false
end
