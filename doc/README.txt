Sinatra 1.3.2:
gem install sinatra

Thin 1.3.1:
gem install thin

Flot 0.7:
http://code.google.com/p/flot/
http://code.google.com/p/flot/downloads/detail?name=flot-0.7.tar.gz

JQuery 1.7.1:
http://code.jquery.com/jquery-1.7.1.min.js

json 1.6.5
gem install json

serialport
serialport-1.0.4

#######
# Mac OS/X
#######

Bluetooth menu, set up device...
ruby ./ecgdemo.rb /dev/cu.cbMedicalDemo-SPP
(or /dev/cu.cbMedicalDemo-SPP-1)

#######
# Linux:
#######

$ bluez-test-device list
00:07:61:BE:78:7B Logitech diNovo Keyboard
00:18:16:05:EB:18 RF-MAB2
00:07:61:BE:F4:C1 Logitech MX1000 mouse
00:12:F3:0F:3B:4E cB Medical Demo

$ rfcomm -a
rfcomm0: 00:12:F3:0F:3B:4E channel 1 clean 

$ sudo rfcomm bind /dev/rfcomm0 00:12:F3:0F:3B:4E 1

$ ruby ./ecgdemo.rb /dev/rfcomm0

rfcomm0: 00:12:F3:0F:3B:4E channel 1 connected [tty-attached]
