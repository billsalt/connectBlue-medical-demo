# Nonin ipod SpO2 monitor.
# $Rev$
# Data format #2: 75Hz reporting
#
# each 1/75 second:
#
# 0x01 status pleth <other> checksum
#
# Meaning of <other> varies frame to frame within 25-frame sequence.
# Frame sync bit in status every 1/25 status byte
# Data sequence repeats every 25 frames

class NoninIpodReader
protected
  SYNC_CHARACTER = 0x01
  # status byte bits
  FRAME_SYNC_MASK           = 1
  GREEN_PERFUSION_MASK      = 2
  RED_PERFUSION_MASK        = 4
  ALWAYS_SET_MASK           = 128
  # position of "other" bytes in @other[]
  # rest of bytes in @other are undefined
  O_HR_MSB     =  0
  O_HR_LSB     =  1	
  O_SpO2       =  2	
  O_REV        =  3	
  O_SpO2_D     =  8	
  O_SpO2_Slew  =  9	
  O_SpO2_B_B   = 10	
  O_E_HR_MSB   = 13	
  O_E_HR_LSB   = 14	
  O_E_SpO2     = 15	
  O_E_SpO2_D   = 16	
  O_HR_D_MSB   = 19	
  O_HR_D_LSB   = 20	
  O_E_HR_D_MSB = 21	
  O_E_HR_D_LSB = 22	

  def clearSequence
    @status = []
    @pleth = []
    @other = []
  end

  # convert nil or number into 0 or 1
  def makeBoolNum(val)
    val ? (val.zero? ? 0 : 1) : 0
  end

  # Called for each 1/3 second sequence.
  # Returns hash with indices of valid green and red perfusion pulse markers,
  # also composite alarm status
  def decodeStatus
    greenp = []
    redp = []
    alarms = 0
    @status.each_with_index do |s,i|
      alarmsNow = (s & REJECT_DATA_MASK)
      alarms |= alarmsNow
      if alarmsNow.zero?
        (greenp << i) if (s & GREEN_PERFUSION_MASK).nonzero?
        (redp << i) if (s & RED_PERFUSION_MASK).nonzero?
      end
    end
    return { :alarms => alarms, :greenp => greenp, :redp => redp }
  end

  # Report 25-frame (1/3 second) sequence to client.
  # Omit invalid data.
  def reportSequence
    frames = @pleth.size
    raise "Missing sync packet! #{frames} frames" if frames != SEQUENCE_LENGTH
    seq = { :time => @timestamp, :frames => frames, :startFrame => @totalFrames - frames }.merge(decodeStatus())
    if seq[:alarms].zero?
      seq[:pleth] = @pleth
      seq[:SpO2] = @other[O_SpO2]
    end
    hr = (@other[O_HR_MSB] * 256) + @other[O_HR_LSB]
    (seq[:heartRate] = hr) unless (hr & 512).nonzero?
    @client.handleNoninSequence(seq)
  end

  # parse a 5-byte packet (called every 1/75 second)
  # every 1/3 second, calls client back with accumulated data.
  def parseFrame(sync,status,pleth,other,checksum)
    # sanity check
    if (sync != SYNC_CHARACTER) || (status & ALWAYS_SET_MASK).zero? || (checksum != ((sync + status + pleth + other) & 0xFF))
      raise "bad packet: #{[sync, status, pleth, other, checksum]}"
    end
    if (status & FRAME_SYNC_MASK).nonzero? # beginning of sequence?
      if @totalFrames.nonzero?
        reportSequence
        clearSequence
      end
      @timestamp = Time.now.to_f
    else
      return if @totalFrames.zero?
    end
    # every frame:
    @status << status
    @pleth << pleth
    @other << other
    @totalFrames += 1
  end

public
  # status byte bits
  SENSOR_ALARM_MASK         = 8
  OUT_OF_TRACK_MASK         = 16
  BAD_PULSE_MASK            = 32
  SENSOR_DISCONNECTED_MASK  = 64
  SEQUENCE_LENGTH = 25
  # which status bits will cause us to reject the other data
  REJECT_DATA_MASK = SENSOR_ALARM_MASK + OUT_OF_TRACK_MASK + BAD_PULSE_MASK + SENSOR_DISCONNECTED_MASK

  def initialize(client)
    raise "client must respond to handleNoninSequence" unless client.respond_to? :handleNoninSequence
    @client = client
    @totalFrames = 0
    @timestamp = 0  # timestamp at start of sequence
    clearSequence
  end

  # parse binary string containing an integral number of packets
  def parse(_bytes)
    _bytes.bytes.each_slice(5) { |b| parseFrame(*b) }
  end
end

# test decoding and callback
if __FILE__ == $0
  def self.handleNoninSequence(h)
    p h
  end

  reader = NoninIpodReader.new(self)

  ARGF.each_line do |line|
    reader.parse(line.split(' ').map(&:hex).pack('C*'))
  end
end

