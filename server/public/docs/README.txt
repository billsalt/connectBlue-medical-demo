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

$ sdptool browse

Inquiring ...
Browsing 00:12:F3:0F:3B:4E ...
Service Name: SPP
Service RecHandle: 0x10001
Service Class ID List:
  "Serial Port" (0x1101)
Protocol Descriptor List:
  "L2CAP" (0x0100)
  "RFCOMM" (0x0003)
    Channel: 1

Service Name: SPP
Service RecHandle: 0x10002
Service Class ID List:
  UUID 128: 00000000-deca-fade-deca-deafdecacaff
Protocol Descriptor List:
  "L2CAP" (0x0100)
 "RFCOMM" (0x0003)
    Channel: 5


or sdptool search 0x1101

sudo rfcomm bind /dev/rfcomm0 00:12:F3:0F:3B:4E 1

ruby ./ecgdemo.rb /dev/rfcomm0
