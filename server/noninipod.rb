# Nonin ipod Sp02 monitor.
# Data format #2: 75Hz reporting
#
# each 1/75 second:
#
# 0x01
# status
# pleth
# <other>
# checksum
#
# meaning of <other> varies frame to frame.
# Frame sync bit in status every 1/25 status byte
# Data sequence repeats every 25 frames


class NoninIpodReader
  SEQUENCE_LENGTH = 25
  SYNC_CHARACTER = 0x01
  # status byte bits
  FRAME_SYNC_MASK           = 1
  GREEN_PERFUSION_MASK      = 2
  RED_PERFUSION_MASK        = 4
  SENSOR_ALARM_MASK         = 8
  OUT_OF_TRACK_MASK         = 16
  BAD_PULSE_MASK            = 32
  SENSOR_DISCONNECTED_MASK  = 64
  ALWAYS_SET_MASK           = 128
  # position of "other" bytes in @other[]
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

  def initialize(client)
    raise "client must respond to handleNoninSequence" unless client.respond_to? :handleNoninSequence
    @client = client
    @totalFrames = 0
    @timestamp = 0 # timestamp at start of sequence
    clearSequence
  end

  def clearSequence
    @status = []
    @pleth = []
    @other = []
  end

  def makeBoolean(val)
    val ? (val.zero ? 0 : 1) : 0
  end

  # report indices of green and red perfusion pulse markers,
  # also 1/0 for 
  def decodeStatus
    greenp = []
    redp = []
    alarms = 0
    @status.each_with_index do |s,i|
      (greenp << i) if (s & GREEN_PERFUSION_MASK)
      (redp << i) if (s & RED_PERFUSION_MASK)
      alarms |= s
    end
    return {
      :greenp => greenp,
      :redp => redp,
      :sensorAlarm => makeBoolean(alarms & SENSOR_ALARM_MASK),
      :outOfTrack => makeBoolean(alarms & OUT_OF_TRACK_MASK),
      :badPulse => makeBoolean(alarms & BAD_PULSE_MASK),
      :sensorDisconnected = makeBoolean(alarms & SENSOR_DISCONNECTED_MASK)
    }
  end

  def reportSequence
    @client.handleNoninSequence({
      :startFrame => @totalFrames - SEQUENCE_LENGTH,
      :pleth => @pleth,
      :heartRate => @other[O_HR_MSB] << 8 + @other[O_HR_LSB],
      :sp02 => @other[O_Sp02] }.merge(decodeStatus()))
  end

  # parse a 5-byte packet (called every 1/75 second)
  # every 1/3 second, calls client back with accumulated data.
  def parse(bytes)
    raise 'fragment of frame' if bytes.size != 5
    (sync,status,pleth,other,checksum) = bytes.unpack('C5')
    # sanity check
    if (sync != SYNC_CHARACTER) || (status & ALWAYS_SET_MASK).zero? || (checksum != ((sync + status + pleth + other) & 0xFF))
      raise "bad packet: #{[sync, status, pleth, other, checksum]}"
    end
    if status & FRAME_SYNC_MASK # beginning of sequence?
      unless @totalFrames.zero?
        reportSequence
        clearSequence
      end
      @timestamp = Time.now.to_f
    end
    # every frame:
    @status << status
    @pleth << pleth
    @other << other
    @totalFrames += 1
  end

end

# test decoding and callback
if __FILE__ == $0
  require 'pp'

  def handleNoninSequence(h)
    pp h
  end

  reader = NoninIpodReader.new(self)

  DATA.each_line do |line|
    line.split(' ').map(&:hex).pack('C5')
  end
end

__END__
