module Bluetooth
  class UnboundBTError < Exception; end

  def self.discoveredDevices
    (raise "no discovery yet for #{RUBY_PLATFORM}") if RUBY_PLATFORM !~ /linux/
    discovered = {}
    mac = nil
    IO.popen("bluez-test-discovery").each_line do |line|
      case line.chomp
      when /^\[ ([0-9A-F:]+) \]/
        mac = $1
      when /\s+Name = (.*)/
        discovered[$1] = mac
      end
    end
    return discovered
  end

  def self.findDeviceMac(devname)
    case RUBY_PLATFORM

    when /linux/
      begin
        IO.popen("bluez-test-device list").each_line do |line|
          if /^([0-9A-F:]+) #{devname}/.match(line)
            return $1
          end
        end
      rescue Errno::ENOENT
        $stderr.puts("problem finding #{devname}: #{$!.message}")
        return nil
      end
      devs = discoveredDevices
      return devs[devname]

    when /darwin/
      return Dir.glob("/dev/cu.#{devname.tr(' ', '')}-SPP").detect { |fname| File.readable?(fname) }

    else
      raise "unsupported platform #{RUBY_PLATFORM}"
    end

    return nil  # if not found
  end

  def self.findSerialDevice(devname, channel=1)
    mac = findDeviceMac(devname)
    return nil if mac.nil?
    used = {}
    case RUBY_PLATFORM
    when /linux/
      begin
        IO.popen("rfcomm -a").each_line do |line|
          case line
          when /^(\w+): (?:[0-9A-F:]+ -> )?([0-9A-F:]+) channel (\d+) (closed|clean)/
            used[$1] = $2
            return "/dev/#{$1}" if ($2 == mac) && ($3 == channel.to_s)
          end
        end
        raise UnboundBTError.new("not found")

      rescue Errno::ENOENT
        $stderr.puts("problem finding #{devname}: #{$!.message}")
        return nil

      rescue UnboundBTError => e
        ("rfcomm0" .. "rfcomm9").find do |nm|
          if !used.include?(nm)
            $stderr.puts("trying to bind #{nm}")
            used[nm] = true
            system("sudo rfcomm bind /dev/#{nm} #{mac} #{channel}")
          end
        end
        retry
      end

    when /darwin/
      return Dir.glob("/dev/cu.#{devname.tr(' ', '')}-SPP").detect { |fname| File.readable?(fname) }

    else
      raise "unsupported platform #{RUBY_PLATFORM}"
    end

    return nil  # if not found
  end

end

# test when run by itself
if __FILE__ == $0
  nm = "cB Medical Demo"
  mac = Bluetooth.findDeviceMac(nm)
  puts "#{nm} MAC = #{mac}"
  dev = Bluetooth.findSerialDevice(nm)
  puts "#{nm} dev = #{dev}"
  puts "discovered:"
  puts Bluetooth.discoveredDevices().inspect
end
