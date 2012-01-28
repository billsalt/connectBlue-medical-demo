# connectBlue ECG Demo web server application
require 'rubygems'
require 'serialport'
require 'json'
require 'monitor'

require './noninipod'

# interface required for OBI411Parser clients
module OBI411ParserClientMixin
  # n: node number; c: ADC channel; v: ADC value
  def handleADCStatus(n,c,v); end
  # n: node number; v: IO value; m: IO mask
  def handleIOStatus(n,v,m); end
  # n: node number; d: data bytes
  def handleData(n,d); end
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

  # Startbyte = 0xA5   Packet id = 0x01  Node id   Value MSB   Value LSB   Mask MSB  Mask LSB  Checksum
  # Byte  Description
  # 0  Start field. Value 0xA5
  # 1  Packet identity field. Value 0x01
  # 2  Node id field. The node id of the sender. The node id is configured using the AT*AMIO command.
  # 3  Value MSB. The status of IO pin 8 to 15.
  # 4  Value LSB. The status of IO pin 0 to 7.
  # 5  Valid mask MSB. Valid status for IO pin 8 to 15. 1 means that the status is valid. 0 means that the status shall be ignored.
  # 6  Valid mask LSB. Valid status for IO pin 0 to 7. 1 means that the status is valid. 0 means that the status shall be ignored.
  # 7  Checksum. The checksum is calculated as the unsigned sum of all bytes in the packet except for the checksum itself
  def parseIOStatus(bytes)
    return 0 if bytes.size < 7
    (id, nodeid, value, mask) = bytes.unpack('CCnn')
    @client.handleIOStatus(nodeid, value, mask)
    return 7
  end

#   Startbyte = 0xA5   Packet id = 0x04  Node Id   ADC Channel id  Value MSB   Value LSB   Checksum
#   Byte  Description
#   0  Start field. Value 0xA5
#   1  Packet identity field. Value 0x04
#   2  Node id field. The node id of the sender. The node id is configured using the AT*AMIO command.
#   3  ADC Channel id.
#   4  ADC Value MSB.
#   5  ADC Value LSB.
#   6  Checksum. The checksum is calculated as the unsigned sum of all bytes in the packet except for the checksum itself.
  def parseADCStatus(bytes)
    return 0 if bytes.size < 6
    (id, nodeid, adcchannel, adcvalue) = bytes.unpack('CCCn')
    @client.handleADCStatus(nodeid, adcchannel, adcvalue)
    return 6
  end

  # Startbyte = 0xA5   Packet id = 0x06  Length field  N bytes application data  Checksum
  # Byte  Description
  # 0  Start field. Value 0xA5
  # 1  Packet identity field. Value 0x06 
  # 2  Node id field. The id of the node that has generated the packet. The id is ignored by a receiving Bluetooth IO module.
  # 3  Length field. Byte specifying the number of data bytes in the data field. Maximum length is 20 bytes.
  # 4 to (N+3)   N bytes application data. (N > 0)
  # N + 4  Checksum. The checksum is calculated as the unsigned sum of all bytes in the packet except for the checksum itself.
  def parseDataPacket(bytes)
    return 0 if bytes.size < 5
    (id, nodeid, len) = bytes.unpack('CCC')
    return 0 if bytes.size < len + 4
    @client.handleData(nodeid, bytes.slice(3,len))
    return len + 4
  end

  def initialize(client)
    @packet = ''.force_encoding('BINARY')
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

# model: parses serial stream, saves up to MAX_SAMPLES in array, reports
# samples and other data
class ECGDemo
  include MonitorMixin

  def handleADCStatus(n,c,v)
    # TODO
    printf("%d ADC%d %d\n", @timestamp, c, v)
  end

  def handleIOStatus(n,v,m)
    # TODO
    printf("%d IO %04x/%04x\n", @timestamp, v, m)
  end

  def handleData(n,d)
    @noninparser.parse(@timestamp, d)
  end

  # NOTE no handling of multiple nodes
  def handleNoninSequence(seq)
    # TODO
    p seq
  end

  def timestamp
    ((Time.now.to_f - @startTime)*1000).round
  end

  # active thread
  def run(pollDelay = 0.001)
    Thread.new do
      while true do
        sleep(pollDelay) if pollDelay
        (rh, wh, eh) = IO::select([@port], nil, [@port])
        if e = eh[0]
          puts "ECGDemo::run exception on serial port #{e.inspect}"
          break
        end
        if r = rh[0]
          bytes = r.sysread(1000)
          @timestamp = timestamp()
          @parser.parse(bytes)
        end
      end
      @port.close
    end
  end

public
  MAX_SAMPLES = 2000
  def initialize(portname)
    @parser = OBI411Parser.new(self)
    @noninparser = NoninIpodParser.new(self)
    @ecgdata = Array.new(MAX_SAMPLES)
    @ecgdata[0] = 0
    @lastSample = 0
    @portname = portname
    @thread = nil
    @timestamp = nil
    @startTime = Time.now.to_f
  end

  def open
    @port = SerialPort.new(@portname, 230400, 8, 1, SerialPort::NONE)
    @thread = run(nil)
  end

  def addECGSample(val)
    @ecgdata.push(val)

    while @ecgdata.size > MAX_SAMPLES
      @ecgdata.shift
      @lastSample += 1
    end
  end

  def samplesSince(lastSample)
    firstSample = @lastSample - @ecgdata.size + 1
    from = [ lastSample - firstSample, 0 ].max
    @ecgdata.slice(from .. -1)
  end
end

if __FILE__ == $0
  reader = ECGDemo.new("/dev/cu.cBMedicalDemo-SPP")
  th = reader.open
  th.join
end
