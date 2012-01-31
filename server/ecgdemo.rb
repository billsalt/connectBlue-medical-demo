# connectBlue ECG Demo web server application
# $Id$
require 'rubygems'
require 'serialport'
require 'json'
require 'monitor'

require './noninipod'

# Example of interface required for OBI411Parser clients
module OBI411ParserClientMixin
  StartTime = Time.now.to_f

  # return integer milliseconds since start
  def timestamp
    ((Time.now.to_f - StartTime)*1000).round
  end

  # n: node number; c: ADC channel; v: ADC value
  def handleADCStatus(n,c,v)
    printf("%d ADC%d %d\n", timestamp, c, v)
  end

  # n: node number; v: IO value; m: IO mask
  def handleIOStatus(n,v,m)
    printf("%d IO %04x/%04x\n", timestamp, v, m)
  end

  # n: node number; seq: hash with values from Nonin
  def handleNoninSequence(n,seq)
    printf("%d %s\n", timestamp, seq.inspect)
  end
end

# Parser for byte stream from connectBlue OBI411 analog I/O module
class OBI411Parser
  START_BYTE = "\xA5".force_encoding('BINARY')
  ID_IO_STATUS = "\x01".force_encoding('BINARY')
  ID_IO_READ = "\x02".force_encoding('BINARY')
  ID_IO_WRITE = "\x03".force_encoding('BINARY')
  ID_ADC_STATUS = "\x04".force_encoding('BINARY')
  ID_ADC_READ = "\x05".force_encoding('BINARY')
  ID_DATA = "\x06".force_encoding('BINARY')

  # parseXXX routines are passed the packet contents minus the start byte
  # and must return the number of input bytes recognizable as packet contents
  # (if any; 0 if a partial) including the checksum byte. However, the checksum
  # byte processing is handled elsewhere.

  # Byte  Description
  # 0  Start field. Value 0xA5
  # 1  Packet identity field. Value 0x01
  # 2  Node id field. The node id of the sender. The node id is configured
  #    using the AT*AMIO command.  3  Value MSB. The status of IO pin 8 to 15.
  # 4  Value LSB. The status of IO pin 0 to 7.
  # 5  Valid mask MSB. Valid status for IO pin 8 to 15. 1 means that the status
  #    is valid. 0 means that the status shall be ignored.
  # 6  Valid mask LSB. Valid status for IO pin 0 to 7. 1 means that the status
  #    is valid. 0 means that the status shall be ignored.
  # 7  Checksum. The checksum is calculated as the unsigned sum of all bytes in
  #    the packet except for the checksum itself
  def parseIOStatus(bytes)
    return 0 if bytes.size < 7
    (id, nodeid, value, mask) = bytes.unpack('CCnn')
    @client.handleIOStatus(nodeid, value, mask)
    return 7
  end

  # Byte  Description
  # 0  Start field. Value 0xA5
  # 1  Packet identity field. Value 0x04
  # 2  Node id field. The node id of the sender. The node id is configured
  #    using the AT*AMIO command.
  # 3  ADC Channel id.
  # 4  ADC Value MSB.
  # 5  ADC Value LSB.
  # 6  Checksum. The checksum is calculated as the unsigned sum of all bytes
  #    in the packet except for the checksum itself.
  def parseADCStatus(bytes)
    return 0 if bytes.size < 6
    (id, nodeid, adcchannel, adcvalue) = bytes.unpack('CCCn')
    @client.handleADCStatus(nodeid, adcchannel, adcvalue)
    return 6
  end

  # Byte  Description
  # 0  Start field. Value 0xA5
  # 1  Packet identity field. Value 0x06 
  # 2  Node id field. The id of the node that has generated the packet. The id
  #    is ignored by a receiving Bluetooth IO module.
  # 3  Length field. Byte specifying the number of data bytes in the data
  #    field. Maximum length is 20 bytes.
  # 4 to (N+3)   N bytes application data. (N > 0)
  # N + 4  Checksum. The checksum is calculated as the unsigned sum of all
  #    bytes in the packet except for the checksum itself.
  def parseDataPacket(bytes)
    return 0 if bytes.size < 5
    (id, nodeid, len) = bytes.unpack('CCC')
    return 0 if bytes.size < len + 4
    @client.handleData(nodeid, bytes.slice(3,len))
    return len + 4
  end

  def initialize(client)
    @packet = ''.force_encoding('BINARY')
    # check client protocol compliance
    [:handleADCStatus, :handleIOStatus, :handleData].each do |sym|
      raise "client must respond to #{sym}" unless client.respond_to? sym
    end
    @client = client
  end

  # packet format: START_BYTE packetID nodeID data checksum
  def parse(bytes)
    # tack new bytes on to partial packet
    @packet.concat(bytes.force_encoding('BINARY'))
    # find START_BYTE
    until (startPos = @packet.index(START_BYTE)).nil?
      after = @packet.slice(startPos+1 .. -1)
      nread = case after[0]
        when ID_ADC_STATUS
          parseADCStatus(after)
        when ID_DATA
          parseDataPacket(after)
        when ID_IO_STATUS
          parseIOStatus(after)
        when nil  # no more bytes
          0
        else
          # consume up to next START_BYTE
          after.index(START_BYTE) || 0
      end
      @packet = after.slice(nread .. -1)
    end
  end
end

class ECGDemoReader
  # n: node number; c: ADC channel; v: ADC value
  def handleADCStatus(n,c,v)
    @client.handleADCStatus(n,c,v)
  end

  # n: node number; v: IO value; m: IO mask
  def handleIOStatus(n,v,m)
    @client.handleIOStatus(n,v,m)
  end

  # n: node number; d: data from Nonin
  def handleData(n,d)
    @noninparser.parse(n,d)
  end

  # def handleNoninSequence(n,seq)
  # end

  # return probable port name
  def self.likelyPortName
    case RUBY_PLATFORM
    when /linux/
      IO.popen("rfcomm -a") do |f|
        f.lines.each do |l|
          if /^(\w+): 00:12:.*/.match(l)
            return "/dev/#{$1}"
          end
        end
      end
    when /darwin/
      return "/dev/cu.cBMedicalDemo-SPP"
    else
      raise "unsupported platform #{RUBY_PLATFORM}"
    end
    nil
  end

  # active thread
  def run(pollDelay = 0.001)
    Thread.new do
      until @threadStopped do
        sleep(pollDelay) if pollDelay
        (rh, wh, eh) = IO::select([@port], nil, [@port])
        if e = eh[0]
          puts "ECGDemo::run exception on serial port #{e.inspect}"
          break
        end
        if r = rh[0]
          bytes = r.sysread(1000)
          @obiparser.parse(bytes)
        end
      end
      @port.close
    end
  end

  def initialize(client, portname)
    @client = client
    @obiparser = OBI411Parser.new(self)
    @noninparser = NoninIpodParser.new(client)
    @portname = portname
    @thread = nil
    @threadStopped = false
    @startTime = Time.now.to_f
  end

  def open
    @port = SerialPort.new(@portname, 230400, 8, 1, SerialPort::NONE)
    @thread = run(nil)
  end

  def close
    @threadStopped = true
    @thread.join
    @thread = @port = nil
  end

end

# model: parses serial stream, saves up to MAX_SAMPLES in array, reports
# samples and other data
# NOTE no handling of multiple nodes
class ECGDemoServer
  include OBI411ParserClientMixin

  # 2.85Vadc = 0xFFFF = 6.75Vbatt
  # round to nearest 10 mV
  def scaleBatteryVoltage(v)
    ((v * 675) / 65536.0).round / 100.0
  end

  # n: node number; c: ADC channel; v: ADC value
  # Channel 0 is EKG signal
  # Channel 1 is battery V
  def handleADCStatus(n,c,v)
    if c == 0
      addECGSample(v)
    elsif c == 1
      @batteryVoltage = scaleBatteryVoltage(v)
    else
      raise "unknown ADC channel #{c}"
    end
  end

  # n: node number; v: IO value; m: IO mask
  def handleIOStatus(n,v,m)
    # TODO
  end

  # n: node number; seq: hash with values from Nonin
  # keys:
  # :alarms (bitmask)
  # :greenp (array)
  # :redp (array)
  # :heartRate
  # :SpO2 (only if alarms == 0)
  # :pleth (array[25]) (only if alarms == 0)
  def handleNoninSequence(n,seq)
    @alarms = seq[:alarms]
    @spO2 = seq[:SpO2] || @spO2
    @heartRate = seq[:heartRate] || @heartRate
  end

  MAX_SAMPLES = 2000

  def initialize(portname = ECGDemoReader.likelyPortName)
    @reader = ECGDemoReader.new(self, portname)
    @mon = Monitor.new
    @cond = @mon.new_cond

    @lastSample = 0
    @batteryVoltage = 0.0
    @ecgdata = Array.new
    @ecgdata[0] = [0,0]
    @spO2 = 0
    @heartRate = 0
  end

  def addECGSample(val)
    @mon.synchronize do
      ts = timestamp
      @ecgdata.push([ts, val])
      @lastSample = ts
      @ecgdata.shift while @ecgdata.size > MAX_SAMPLES
      @cond.broadcast
    end
  end

  # waits until some samples ready
  # lastSample is msec timestamp value
  def samplesSince(lastSample)
    @mon.synchronize do
      @cond.wait_while { @lastSample <= lastSample }
      first = @ecgdata.find_index { |s| s[0] > lastSample }
      @ecgdata.slice(first .. -1).map { |a| [a[0] - lastSample, a[1]] }
    end
  end

  def start
    @reader.open
  end

  def stop
    @reader.close
  end

  # Keys:
  # 'alarms' = <int>  bitmask
  # 'spO2' = <int> percent
  # 'hr' = <int> heart rate, BPM
  # 'battV' = <float> battery voltage
  # 'ref' = <int> lastSample
  # 'ecg' = [[t,v],[t,v] ... ]
  #    where t = timestamps in msec since lastSample
  #      and v = 16-bit unsigned value 
  def jsonSince(lastSample)
    # block until new data available
    s = samplesSince(lastSample)
    j = { :alarms => @alarms,
      :spO2 => @spO2,
      :hr => @heartRate,
      :battV => @batteryVoltage,
      :ref => lastSample,
      :ecg => s }.to_json
    return [j, s[-1][0] + lastSample]
  end

end

# test reading
if __FILE__ == $0
  if ARGV.size == 1 && %r{^/dev}.match(ARGV[0])
    $portname = ARGV[0]
  else
    $portname = ECGDemoReader.likelyPortName
    $stderr.puts("using port #{$portname}")
  end

  class OBI411ParserTest
    include OBI411ParserClientMixin
    def initialize(portname)
      @reader = ECGDemoReader.new(self, portname)
    end
    def open
      @reader.open
    end
    def close
      @reader.close
    end
    def self.test(portname)
      begin
        reader = self.new(portname)
        th = reader.open
        th.join
      rescue Interrupt
        reader.close
      end
    end
  end

#  OBI411ParserTest.test($portname)

begin
  s = ECGDemoServer.new($portname)
  s.start
  t = 0
  while true
    (j,t) = s.jsonSince(t)
    puts t
    puts j
    sleep 2
  end

rescue Interrupt
  s.close
end

end
