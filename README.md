# BE6502-Fast-SD-Card-Interface
A couple of shift registers from the PS/2 keyboard interface and unused gates from the Worlds Worst Video Card interface are wired up to allow very fast SD card data transfers on a Ben Eater 6502 breadboard computer.

Repurposing a Ben Eater 6502 PS/2 keyboard interface for fast SD card transfer.


Greetings fellow 8 Bit Music Lovers!
I hope you enjoy this Merrie little bit of Melodic 8 Bit Ben Eater Bugs Bunny!
It’s A Corny Concerto, a Public Domain Fantasia parody cartoon from 1943, and includes, along with Bugs Bunny, Elmer Fudd, Porky Pig, and a young Daffy Duck. https://en.wikipedia.org/wiki/A_Corny_Concerto



I made this after thinking about how I can do better audio for my Ben Eater Bad Apple! Demo for the 6502 and Worlds Worst Video Card. https://www.youtube.com/watch?v=0glEfLZCwmc
One of the constraints I have put on myself is only using ‘Official Ben Eater’ chips/hardware, other than a simple SD card adapter and allowing a few passives like diodes and resistors.
While it is great that Ben now has added a SID chip (and modern replacements) to the system in recent videos, I am saving a deep dive into the SID for making original music for my 32k ROM based ‘Demo Scene’ style Demo I am also working on.


For my Bad Apple! Demo Version 2.0 I want to use the PCM audio out of the VIA serial port I was experimenting with recently, https://hackaday.io/project/204469-abusing-a-6522-via-serial-port-for-pcm-audio while also keeping the 30 FPS video I already have working from my earlier Demo with VIA PB7 Square wave audio.
However the math just was not mathing! I was reading too slowly from the SD card. Even with a very fast ‘bit-bang’ routine it was taking over 40 CPU cycles per byte to shift in the data. There just was not enough cycles/SD card transfer speed to do both the video and PCM audio, even at a very low 1,990 bytes/15,920 1 bit samples a second and still keep the 30fps video.


Then a great suggestion from a very smart person lead me to realize that I could rewire the existing PS/2 Keyboard hardware Ben uses and also wire in a couple left over AND gates from Ben’s VGA interface to allow much faster reads from the SD card. What I ended up doing was using one 74HC595 from the keyboard hardware and connected it to one of the VIA 8 bit parallel ports. This was easy. The tricky part was figuring out how to use other 74HC595 as a ‘Pulse Generator’.
VIA Port A is setup to pulse the VIA CA2 pin each time it is read. This is inverted using the 74HC14 from the keyboard hardware and fed into an unused 74CHT08 AND gate from the VGA hardware along with the system clock. This is then fed to the clock input of the ‘Pulse Generator’ 74HC595. This is setup so that the serial input is tied high, and the QA/bit 0 output feeds back to the AND gate CA2 is connected to, keeping the Pulse generator input clock going.
QA/bit 0 is also connected to another unused AND gate along with the system clock. The output of this is cleaned up with resistors and a couple more Schmitt inverter gates from the keyboard hardware and sent along to the SD card clock and the other 74HC595 shift register. This is what clocks in the bits. Cleaning up this signal was key and took the most experimentation.


Since these are ‘latching’ as opposed to ‘transparent’ shift registers the register clock RCLK on both is simply tied to the system clock, forcing them to act more or less like ‘transparent’ shift registers, eliminating the need to have latching circuitry or having to deal with timing of the latching at 5Mhz. My $60 USB oscilloscope was used to the absolute limit to debug this circuitry as it was!


To stop it after exactly 8 bits have been transferred the output of QH/Bit 7 of the pulse generator is sent back through an inverter to the clear pin, SRCLR. This sets the output bits back to low and stops both the clock of the pulse generator itself and the clock output to the SD card/output shift register.
Testing shows that 2 clock cycles are needed after each shift operation at 5Mhz for everything to reset and settle. Meaning that after each 4 cycle LDA VIA_PORTA, you only need to wait 6 cycles before you can read again for a total of 10 cycles per byte.


For instance, I have an unrolled ROM based routine that can transfer bytes to the screen buffer at just 12 cycles per byte by doing this:
 LDA VIA_PORTA  ; 4 cycles 3 bytes
 STA (Screen),Y ; 6 cycles 2 bytes
 INY            ; 2 cycles 1 byte


This setup works with my system clocked at 5mhz, and it should work at slower clock speeds as well.
There are also some resistors and diodes used to allow VIA_PORTB to be connected to the SD card. This allows for the slow speed initialization required by SD cards and to send commands or data to the card. Once initialized all reads are done by simply reading a full byte on VIA_PORTA.


To demo this fast SD hardware I have unrolled routines that write 6,400 bytes to the screen. One obstacle to doing this quickly is that SD cards in READ_MULTIBLOCK mode always send out CRC bytes each 512 byte block and then also need a variable amount of ‘pre-charge’ clock pulses. Somewhere around 10 bytes total on the cards I am using. (It varies by a couple bytes from block to block at 5Mhz.)
Keeping track of this for each byte would cut the transfer rate in half at a minimum.
6,400 is not divisible by 512 evenly, so it did not seem easy to unroll at first.
However I realized that 6,400 + 256 IS evenly divisible by 512.
So I created some unrolled routines and always read 256 bytes after each frame and use that for the audio.


This allows hard-coded routines to toss the CRC/pre-charge bytes after each 512 bytes read.
Since I don’t need to do anything with these CRC bytes I can use the full speed of this hardware by cycle counting:

;  LDA (VIA_PORTA_Ind) ; 5 cycles byte 1
;  LDA (DummyZP)       ; 5 cycles delay for Pulse Generator circuit to shift out pulse x8 and reset.

Taking only 10 CPU cycles for each byte. 8 to shift the byte and 2 to reset the Pulse Generator.


All these optimizations together allow 20 FPS Vsync locked full color video and a 4,734 bytes per second audio rate. I just ‘waste’ a few bytes each frame in the audio packet to match the ~235 bytes per frame VIA serial output rate. Wasting ~21 bytes per frame is much faster than counting bytes and much easier to unroll! I only use a single 256 byte buffer and reset the playback pointer after transferring 2 new audio bytes each frame. Because of timing this causes a small amount of degradation in the audio quality as there is a ‘partial’ byte every few frames. I plan on using a larger buffer in the future to enhance the audio playback, but this small buffer allows me to have a very efficient IRQ playback routine, saving many cycles by using the X register only for audio playback, allowing 4.6KBs audio. I did add a 10uf ‘low pass filter’ capacitor to ground on the audio output I was already using from my earlier PCM tests at the kind suggestion of a youtube comment by @itdepends604 https://www.youtube.com/watch?v=y4aGgKcEdV0, and this did improve the audio by filtering out some of the higher end ‘static’. It still sounds very ‘AM radio’, but it is much improved from my earlier tests.



In the end this all works out to a transfer rate of over 130KB a second from the SD card to the screen and audio buffer for this demo!

Pretty fast for a 6502!


I also took this opportunity to take a few resistors of 1k, 2.2k and 3,3k (x2) and change the VGA color output from RRGGBB 64 color output to RRRGGGBB for full 256 color output. I think this cartoon at 256 colors really shows off what can be done with the 100x64 output of Ben’s Worlds Worst Video Card!

As for how I created the video and audio data, I used VLC to output the audio from the MP4 video and processed it in Audacity to get the correct bitrate, I then used the same process as the PCM hackaday project linked earlier to create a 1 bit PCM audio file.
For the video side of things, I used handbreak CLI to create a MP4 video of the exact framerate I needed. I found out that my 60Hz VGA output is actually more like 60.31Hz, so I needed a framerate of 20.103fps. 3 Python scripts I hacked together were then used to create a video file, 1 to extract the frames from the MP4 as 800x600 PNG image files, a second to then create a stream of 128x64, 256 color images that I used for initial testing, and a third script to take the two files and output 100x64 image data interleaved with 256 byte audio data packets containing around 235 bytes at the PCM audio bitrate.

I still have some experimentation on Audio processing and output I want to do as well as another intro to create before I do the new Bad Apple! Demo, but I thought you all might want to see the progress I have made, and may find the SD interface interesting.


That’s All Folks!

 
