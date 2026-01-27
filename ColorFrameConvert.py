import cv2
from PIL import Image




def save_frames_as_png(video_path, output_folder, resolution=(640, 480)):

    cap = cv2.VideoCapture(video_path)
    frame_count = 0

    while cap.isOpened():
        ret, frame = cap.read()

        if not ret:
            break


        frame = cv2.resize(frame, resolution)


        output_path = f"{output_folder}/{frame_count:04d}.png"
        cv2.imwrite(output_path, frame)

        #--------------

        #---------------


        frame_count += 1

    cap.release()
    print("Frames saved successfully!")

if __name__ == "__main__":
    #video_path = "RickRoll.mp4"  # Replace with your video file path
    video_path = "ACornyConcerto_20_10333_FPS.mp4" #"RickRoll 2FPS 1.mp4"  # Replace with your video file path
    output_folder = "C:/cygwin64/home/josh/bad-apple/ColorTest/FrameOutput"  # Replace with the desired output folder
    #resolution = (128, 64)     # Replace with your desired resolution
    resolution = (800, 600)  # Replace with your desired resolution
    save_frames_as_png(video_path, output_folder, resolution)
