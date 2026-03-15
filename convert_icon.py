from PIL import Image
import os

def convert():
    try:
        img = Image.open("icons/ios-app-icon-1024.png")
        img.save("icons/app.ico", format="ICO", sizes=[(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)])
        print("Successfully created icons/app.ico")
    except Exception as e:
        print(f"Error converting icon: {e}")

if __name__ == "__main__":
    convert()
