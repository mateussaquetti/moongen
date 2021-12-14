local mg     = require "moongen"
local memory = require "memory"
local device = require "device"
local ts     = require "timestamping"
local stats  = require "stats"
local hist   = require "histogram"

local PKT_SIZE	= 126
local ETH_DST	= "08:11:11:11:11:08"
local ETH_DST2  = "08:22:22:22:22:08"

local ETH_SRC   = "08:11:11:11:11:08"
local ETH_SRC2  = "08:11:11:11:11:08"

local ctr       = 0 

local function getRstFile(...)
	local args = { ... }
	for i, v in ipairs(args) do
		result, count = string.gsub(v, "%-%-result%=", "")
		if (count == 1) then
			return i, result
		end
	end
	return nil, nil
end

function configure(parser)
	parser:description("Generates bidirectional CBR traffic with hardware rate control and measure latencies.")
	parser:argument("dev1", "Device to transmit/receive from."):convert(tonumber)
	parser:argument("dev2", "Device to transmit/receive from."):convert(tonumber)
	parser:option("-r --rate", "Transmit rate in Mbit/s."):default(10000):convert(tonumber)
	parser:option("-f --file", "Filename of the latency histogram."):default("histogram.csv")
end

function master(args)
	local dev1 = device.config({port = args.dev1, rxQueues = 2, txQueues = 2})
	local dev2 = device.config({port = args.dev2, rxQueues = 2, txQueues = 2})
	device.waitForLinks()
	dev1:getTxQueue(0):setRate(args.rate)
	dev2:getTxQueue(0):setRate(args.rate)
	mg.startTask("loadSlave", dev1:getTxQueue(0), 0)
	if dev1 ~= dev2 then
		mg.startTask("loadSlave", dev2:getTxQueue(0), 1)
	end
	stats.startStatsTask{dev1, dev2}
	mg.startSharedTask("timerSlave", dev1:getTxQueue(1), dev2:getRxQueue(1), args.file)
	mg.waitForTasks()
end

function loadSlave(queue, ctr)
        
        if ctr == 1 then
          local mem = memory.createMemPool(function(buf)
               -- buf:getEthernetPacket():fill{
               --         ethSrc = txDev,
               --         ethDst = ETH_DST2,
               --         ethType = 0x1234 -- 0x1234
               -- }
           buf:getUdpPacket():fill{
                ethSrc = ETH_SRC,
                ethDst = ETH_DST,
                ip4Src = "10.1.1.1",
                ip4Dst = "10.2.2.2",
                udpSrc = SRC_PORT,
                udpDst = DST_PORT,
                pktLength = PKT_SIZE
           }
          end)
          local bufs = mem:bufArray()
           while mg.running() do
                bufs:alloc(PKT_SIZE)
                bufs:setVlans(2)
                queue:send(bufs)
           end
        end

        if ctr == 0 then
	   local mem = memory.createMemPool(function(buf)
           --10.0.0.2
           -- 10.1.1.2
           buf:getUdpPacket():fill{
                ethSrc = ETH_SRC2,
                ethDst = ETH_DST2,
                ip4Src = "10.1.1.1",
                ip4Dst = "10.2.2.2",
                udpSrc = SRC_PORT,
                udpDst = DST_PORT,
                pktLength = PKT_SIZE
           }

	   end)
 	   local bufs = mem:bufArray()
    	   while mg.running() do
		bufs:alloc(PKT_SIZE)
                bufs:setVlans(1)
		queue:send(bufs)
	   end
        end
end

function timerSlave(txQueue, rxQueue, histfile)
	local timestamper = ts:newTimestamper(txQueue, rxQueue)
	local hist = hist:new()
	mg.sleepMillis(1000) -- ensure that the load task is running
	while mg.running() do
		hist:update(timestamper:measureLatency(function(buf) buf:getEthernetPacket().eth.dst:setString(ETH_DST) end))
	end
	hist:print()
	hist:save(histfile)
end

