from PIL import Image
import os
import sys
import subprocess

def convert_windows():
    """Convert to Windows .ico format"""
    try:
        img = Image.open("icons/ios-app-icon-1024.png")
        img.save("icons/app.ico", format="ICO", sizes=[(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)])
        print("✅ Successfully created icons/app.ico")
    except Exception as e:
        print(f"❌ Error converting to .ico: {e}")

def convert_macos():
    """Convert to macOS .icns format"""
    try:
        # Create an iconset directory
        iconset_dir = "icons/app.iconset"
        os.makedirs(iconset_dir, exist_ok=True)
        
        # Open source image
        img = Image.open("icons/ios-app-icon-1024.png")
        
        # macOS requires specific sizes for .icns
        sizes = [
            (16, "16x16"),
            (32, "16x16@2x"),
            (32, "32x32"),
            (64, "32x32@2x"),
            (128, "128x128"),
            (256, "128x128@2x"),
            (256, "256x256"),
            (512, "256x256@2x"),
            (512, "512x512"),
            (1024, "512x512@2x")
        ]
        
        # Generate all required sizes
        for size, name in sizes:
            resized = img.resize((size, size), Image.Resampling.LANCZOS)
            resized.save(f"{iconset_dir}/icon_{name}.png")
        
        print(f"✅ Generated icon files in {iconset_dir}")
        
        # Convert iconset to icns using macOS iconutil
        try:
            subprocess.run(
                ["iconutil", "-c", "icns", iconset_dir, "-o", "icons/app.icns"],
                check=True
            )
            print("✅ Successfully created icons/app.icns")
            
            # Clean up iconset directory
            import shutil
            shutil.rmtree(iconset_dir)
            print("✅ Cleaned up temporary iconset directory")
        except subprocess.CalledProcessError as e:
            print(f"❌ Error creating .icns: {e}")
            print(f"ℹ️  Icon files are available in {iconset_dir}")
        except FileNotFoundError:
            print("❌ iconutil not found (only available on macOS)")
            print(f"ℹ️  Icon files are available in {iconset_dir}")
            
    except Exception as e:
        print(f"❌ Error converting to .icns: {e}")

def convert():
    """Convert icon for current platform"""
    platform = sys.platform
    
    if platform == "darwin":  # macOS
        print("🍎 Detected macOS - creating .icns file")
        convert_macos()
    elif platform == "win32":  # Windows
        print("🪟 Detected Windows - creating .ico file")
        convert_windows()
    else:  # Linux or other
        print(f"🐧 Detected {platform} - creating both formats")
        convert_windows()
        convert_macos()

if __name__ == "__main__":
    convert()
