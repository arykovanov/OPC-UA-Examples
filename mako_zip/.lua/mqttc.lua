
--MQTT Client. Copyright Real Time Logic.

local fmt,schar,sbyte,ssub=string.format,string.char,string.byte,string.sub
local h2n,n2h=ba.socket.h2n,ba.socket.n2h

local MQTT_CONNECT     = 0x01 << 4
local MQTT_CONACK      = 0x02 << 4
local MQTT_PUBLISH     = 0x03 << 4
--local MQTT_PUBACK      = 0x04 << 4
--local MQTT_PUBREC      = 0x05 << 4
--local MQTT_PUBREL      = 0x06 << 4
--local MQTT_PUBCOMP     = 0x07 << 4
local MQTT_SUBSCRIBE   = 0x08 << 4
local MQTT_SUBACK      = 0x09 << 4
local MQTT_UNSUBSCRIBE = 0x0a << 4
local MQTT_UNSUBACK    = 0x0b << 4
local MQTT_PINGREQ     = 0x0c << 4
local MQTT_PINGRESP    = 0x0d << 4
local MQTT_DISCONNECT  = 0x0e << 4


local function fmtArgErr(argno,func,exp,got)
   return fmt("bad argument #%d to '%s' (%s expected, got %s)",
              argno,func,exp,type(got))
end

local function typechk(name,typename,val,level)
   if type(val) == typename then return end
   error(fmt("%s: expected %s, got %s",name,typename,type(val)), level or 3)
end

-- Create an MQTT string: 16 bit length + string
local function mqttstr(str)
   return h2n(2,#str)..str
end

--Encode MQTT message length
local function enclen(len)
   local rsp={}
   repeat
      local digit = len % 0x80
      len = len // 0x80
      table.insert(rsp, schar(len > 0 and (digit | 0x80) or digit))
   until len == 0
   return table.concat(rsp)
end

local function encPacketId(self,callback)
   local id = self.packetId
   self.packetIdT[id] = callback -- callback may be nil
   self.packetId = id + 1
   if self.packetId >= 0xFFFF then self.packetId=1 end
   return h2n(2, id)
end

-- Wait for data
local function rec(self)
   return self.sock:read()
end


-- Wait for next MQTT packet
-- returns cpt,payload or nil,err. cpt: Control Packet Type e.g. CONNACK
local function mqttRec(self)
   local data
   if self.recOverflowData then
      data = self.recOverflowData
      self.recOverflowData =nil
   else
      data=""
   end
   local mult,len,ix = 1,0,1
   repeat
      ix = ix + 1
      while #data < ix do
         local msg,err = rec(self)
         if not msg then return nil,err end
         data = data..msg
      end
      local digit = sbyte(data,ix)
      len = len + (digit & 0x7F) * mult
      if len > 0xFFFF then return nil, "overflow" end
      mult = mult * 0x80
   until digit < 0x80
   local msg = ssub(data, ix+1)
   while #msg < len do
      local frag,err = rec(self)
      if not frag then return nil,err end
      msg = msg..frag
   end
   local cpt = sbyte(data,1) & 0xF0
   if len == #msg then return cpt,msg end
   assert(#msg > len)
   self.recOverflowData = ssub(msg, len+1)
   return cpt,ssub(msg,1,len)
end

local function sendPing(self)
   if self.pingResp then
      self.error="pingresp"
      self.sock:close()
   else
      self.pingResp=true
      self.sock:write(schar(MQTT_PINGREQ)..schar(0))
   end
end

-- Manage received Control Packets (cp)

local function cpPublish(self, msg)
   local tlen = n2h(2,msg)
   self.onpub(ssub(msg, 3, tlen+2), ssub(msg, tlen+3))
   return true
end

local function cpSuback(self, msg)
   local id = n2h(2,msg)
   local func = self.packetIdT[id]
   if func then
      self.packetIdT[id]=nil
      func(sbyte(msg,3))
   end
   return true
end

local function cpUnsuback(self, msg)
   local id = n2h(2,msg)
   local func = self.packetIdT[id]
   if func then
      self.packetIdT[id]=nil
      func()
   end
   return true
end

local function cpPingresp(self, msg)
   self.pingResp=nil
   return true
end

local cpT={
   [MQTT_PUBLISH]=cpPublish,
   [MQTT_SUBACK]=cpSuback,
   [MQTT_UNSUBACK]=cpUnsuback,
   [MQTT_PINGRESP]=cpPingresp,
}


local C={} -- MQTT Client
C.__index=C

function C:publish(topic,msg)
   msg = mqttstr(topic)..msg
   return self.sock:write(schar(MQTT_PUBLISH)..enclen(#msg)..msg)
end


local function subOrUnsub(self,topic,callback,sub)
   local cpt=schar((sub and MQTT_SUBSCRIBE or MQTT_UNSUBSCRIBE) | 0x02)
   local data = encPacketId(self,callback)..mqttstr(topic)
   if sub then
      data = data..schar(0) -- QoS 0
   end
   return self.sock:write(cpt..enclen(#data)..data)
end

function C:subscribe(topic,callback)
   return subOrUnsub(self,topic,callback,true)
end

function C:unsubscribe(topic,callback)
   return subOrUnsub(self,topic,callback,false)
end

function C:disconnect()
   self.error="disconnect"
   local ok,err = self.sock:write(schar(MQTT_DISCONNECT)..schar(0))
   self.sock:close()
   return ok,err
end

function C:run()
   local cpt,msg
   while true do
      cpt,msg=mqttRec(self)
      if not cpt then break end
      local func = cpT[cpt]
      if not func then return nil,"unknowncp",cpt end
      cpt,msg = func(self, msg) -- cpt,msg are ok,err
      if not cpt then break end
   end
   self.timer:cancel()
   if not self.error then self.error = msg end -- msg=err
   return nil,self.error
end

local function connect(addr, onpub, opt)
   local self={}
   opt = opt or {}
   if type(addr) == "string" then
      local sock,err=ba.socket.connect(
         addr, opt.port or (opt.shark and 8883 or 1883), opt)
      if not sock then return nil,err end
      -- Only accept trusted SSL cert if credential(s) will be sent to server
      if opt.shark and (opt.uname or opt.passwd) then
         local trusted,status = sock:trusted(addr)
         if not trusted then return nil, status end
      end
      self.sock=sock
   elseif type(addr) == "userdata" and type(addr.trusted) == "function" then
      self.sock=addr
   else
      error(fmtArgErr(1,"connect","string",addr),2)
   end
   if type(onpub) ~= "function" then
      error(fmtArgErr(2,"connect","function",onpub),2)
   end
   self.pingtmo = opt.keepalive and
      (opt.keepalive > 60 and opt.keepalive or 60) or 10*60
   self.id = opt.id or self.sock:sockname()..ba.rnds(10)
   -- Create MQTT header for version 3.1.1 (4)
   local data = schar(0)..schar(4).."MQTT"..schar(4)
   local flags = (opt.uname and 0x80 or 0) |
                 (opt.passwd and 0x40 or 0) |
                 (opt.will and 0x04 or 0) |
                 0x02 -- bit 1 clean session
   data = data..schar(flags)..h2n(2,self.pingtmo)..mqttstr(self.id)
   if opt.will then
      local w=opt.will
      typechk("opt.will", "table",w)
      typechk("opt.will.topic", "string",w.topic)
      typechk("opt.will.message", "string",w.message)
      data = data..mqttstr(w.topic)..mqttstr(w.message)
   end
   if opt.uname then
      typechk("opt.uname", "string",opt.uname)
      data = data..mqttstr(opt.uname)
   end
   if opt.passwd then
      typechk("opt.passwd", "string",opt.passwd)
      data = data..mqttstr(opt.passwd)
   end
   self.sock:write(schar(MQTT_CONNECT)..enclen(#data)..data)
   local cpt,msg=mqttRec(self)
   if not cpt then return nil,msg end -- msg=err
   if cpt ~= MQTT_CONACK then return nil,"invalidresp" end
   local rcp = sbyte(msg,2)
   if rcp ~= 0 then return nil, rcp end
   self.packetId,self.packetIdT=1,{}
   self.onpub=onpub
   self.timer = ba.timer(function() sendPing(self) return true end)
   self.timer:set((self.pingtmo - 20) * 1000)
   return setmetatable(self,C)
end



return {connect=connect}
