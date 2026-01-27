from PIL import Image
import struct


filePath = "C:/cygwin64/home/NormalLuser/bad-apple/ColorTest/FrameOutput/"
merged = "C:/cygwin64/home/NormalLuser/bad-apple/ColorTest/FrameOutput/Corny_256_20_103_FPS.bin"



dither = False #True
showPreview = False #True

# Palette code based off of https://stackoverflow.com/a/29438149/2303432

# # Generate palette
# palette = []
#
# for r in [0, 85, 170, 255]:
#   for g in [0, 85, 170, 255]:
#     for b in [0, 85, 170, 255]:
#       palette.append(r)
#       palette.append(g)
#       palette.append(b)

# RRRGGGBB.... Actually, I wired it BBGGGRRR... Easier to change code!! :)
palette = []
for b in range(4):  # Top 2 bits (Blue)
    for g in range(8):  # Middle 3 bits (Green)
        for r in range(8):  # Bottom 3 bits (Red)
            palette.append(int(r * 255 / 7))
            palette.append(int(g * 255 / 7))
            palette.append(int(b * 255 / 3))


palimage = Image.new("P", (64, 64))
palimage.putpalette(palette) # * 4)



MyFrame = 0 #526 # 0700

while MyFrame < 9609:
  #4554: #5314:
  MyNumber = str(MyFrame).rjust(4, '0')
  file = filePath + MyNumber + ".png"

  # Load image
  image = Image.open(file)

  # Resize image
  horiz = image.width > image.height
  ratio = float(image.width) / float(image.height)
  #newSize = (int(ratio * 75) if horiz else 100, int((1 / ratio) * 100) if not horiz else 75)
  #newSize = (int(ratio * 64) if horiz else 128, int((1 / ratio) * 128) if not horiz else 64)
  #RickRoll:
 # newSize = (int(ratio * 64) if horiz else 100, int((1 / ratio) * 100) if not horiz else 64)
  #Doom:
  newSize = (142,84)

  resized = image.resize(newSize)

  #topLeft = (int((resized.width - 100) / 2) if horiz else 0, int((resized.height - 75) / 2) if not horiz else 0)
  #topLeft = (int((resized.width - 128) / 2) if horiz else 0, int((resized.height - 64) / 2) if not horiz else 0)
  #Rickroll:
  #topLeft = (int((resized.width - 100) / 2) if horiz else 0, int((resized.height - 64) / 2) if not horiz else 0)
  #Doom:
  #topLeft = ( 21,  10)
  #CornyToon
  topLeft = (18, 10)
  #crop = (topLeft[0], topLeft[1], topLeft[0] + 100, topLeft[1] + 75)
  #crop = (topLeft[0], topLeft[1], topLeft[0] + 128, topLeft[1] + 64)
  crop = (topLeft[0], topLeft[1], topLeft[0] + 100, topLeft[1] + 64)
  cropped = resized.crop(crop)

  # Quantize image (convert to color palette)
  quant = cropped.im.convert("P", 1 if dither else 0, palimage.im)
  pixels = image._new(quant).load()

  # If enabled, show a preview of the final image
  if showPreview:
    image._new(quant).show()

  # Write binary file for EEPROM
  #out_file = open(file.replace('png', 'bin').replace('jpg', 'bin'), "wb")
  out_file = open(merged, "ab")

  #for y in range(256):
  for y in range(64):
    for x in range(128):
      try:
        out_file.write(struct.pack("B", pixels[x, y]))
      except IndexError:
        out_file.write(struct.pack("B", 0))
  MyFrame +=1

