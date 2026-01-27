input_filename = "Corny_256_20_103_FPS.bin"
input_filename2 = "ACornyConcerto_37872_2.bin" #ACornyConcerto37872_dither.bin"
output_filename = "Corny_256_20_103_FPS_100_FixedAudio4734New_4_NoAudioDither.bin"

read_bytes = 100
skip_bytes = 28
sync_interval = 6400
Framerate = 20.103346
AudioSampleRate = 4734
avg_f2_bytes = AudioSampleRate / Framerate # ~236.7
buffer_size = 256


buffer = bytearray(buffer_size)
# Take Video file, reformat, and also include a fixed 256 bytes at end of each frame, putting the PCM audio data in this space.

try:
    with open(input_filename, 'rb') as f1, \
            open(input_filename2, 'rb') as f2, \
            open(output_filename, 'wb') as outfile:

        total_f1_written = 0
        f2_debt = 0.0

        while True:
            #  100 bytes/pixels from video
            data = f1.read(read_bytes)
            if not data:
                break

            outfile.write(data)
            total_f1_written += len(data)

            # 6400 bytes = 100x64 screen
            if total_f1_written >= sync_interval:
                f2_debt += avg_f2_bytes
                bytes_to_read = int(f2_debt)

                chunk = f2.read(bytes_to_read)
                if not chunk:
                    break

                # Grab audio for frame. Will be around 235 bytes
                write_len = min(len(chunk), buffer_size)
                buffer[0:write_len] = chunk[:write_len]

                # Dump to beginning of buffer, decoder will reset to start
                outfile.write(buffer)

                # remainder
                f2_debt -= bytes_to_read
                total_f1_written -= sync_interval

            # Video file is formatted as full 128x64. IE includes 28 off-screen bytes.
            # Skip these.
            f1.seek(skip_bytes, 1)

    print(f"Done '{output_filename}'")

except FileNotFoundError as e:
    print(f"Error: {e}")
except Exception as e:
    print(f"Another Error: {e}")