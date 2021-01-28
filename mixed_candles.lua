-- робот берет предыдущие свечи по инструментаи, если они разнонаправленные - открывает позиции.
-- продает выросший инструмент и покупает упавший, закрывает позиции по окончанию таймфрейма
-- формула расчета коэффициента прописывается в функции getK (для каждого набора инструментов своя)

-------------------------- настойки робота ------------------------------------------------------------------------------------------
arTools = {}																		-- таблица с параметрами инструментов
----------------------- инструмент 1
arTools[1] = {
	['SEC'] = 'MXZ0',																-- SEC код инструмента 
	['CLASS'] = 'SPBFUT',															-- CLASS класс инструмента 
	['lots'] = 1																	-- количество лотов для заявок
}
----------------------- инструмент 2
arTools[2] = {
	['SEC'] = 'SiZ0',																-- SEC код инструмента 
	['CLASS'] = 'SPBFUT',															-- CLASS класс инструмента
	['lots'] = 1																	-- количество лотов для заявок
}

TRADE_ACC = "SPBFUT00APS"      														-- торговый счет 
-------------------------служебные переменные----------------------------------------------------------------------------------------
logFileName = 'LogMixedCandles' 													-- имя файла логов
uniq_trans_id  = 0																	-- id транзакции
isOpenPosition = false																-- открыта позиция
dofile(getScriptPath().."\\func\\functions.lua")									-- подключаем набор функций
is_run = true
-------------------------------------------------------------------------------------------------------------------------------------

function main()
	while is_run do 
		sleep(100) 
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

function OnInit(s)																	-- инициализация
	write_log("--------3апуск скрипта--------", logFileName)	
end

function OnStop(s)																	-- остановка скрипта
	if isOpenPosition == true then
		--open_closePosition('close')												-- если открыта позиция -> закрываем
		write_log("Позиции открыты, не забудьте закрыть!", logFileName)
	end
	write_log("-------Oстановка скрипта-------", logFileName)
	is_run = false
end