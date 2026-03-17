stil#!/usr/bin/env python3
"""
Fix the port validation bug in gui_main.py
"""

import sys

print("🔧 Fixing port validation in gui_main.py...")

# Read the file
with open('gui_main.py', 'r') as f:
    content = f.read()

# The old buggy code (the currently "fixed" version that still doesn't work)
old_code = """    def start_server(self):
        try:
            port_str = self.port_var.get().strip()
            if not port_str:
                port_str = str(PORT)
            p = int(port_str)
            if p < 1 or p > 65535:
                raise ValueError("Port out of range")
            self.manager.start(port=p)
        except ValueError as e:
            messagebox.showerror("Error", f"Port must be a number between 1-65535. Got: '{self.port_var.get()}'")
        except Exception as e:
            messagebox.showerror("Error", f"Failed to start server: {e}")"""

# The new fixed code
new_code = """    def start_server(self):
        try:
            port_str = str(self.port_var.get()).strip().strip("'").strip('"')
            if not port_str:
                port_str = str(PORT)
            p = int(port_str)
            if p < 1 or p > 65535:
                raise ValueError("Port out of range")
            self.manager.start(port=p)
        except ValueError as e:
            messagebox.showerror("Error", f"Port must be a number between 1-65535. Got: '{self.port_var.get()}' (type: {type(self.port_var.get()).__name__})")
        except Exception as e:
            messagebox.showerror("Error", f"Failed to start server: {e}")"""

# Check if old code exists
if old_code in content:
    # Replace it
    content = content.replace(old_code, new_code)
    
    # Write back
    with open('gui_main.py', 'w') as f:
        f.write(content)
    
    print("✅ Successfully fixed gui_main.py!")
    print("")
    print("Now run the app again:")
    print("  python gui_main.py")
    print("")
    print("Or rebuild the .app:")
    print("  ./build_macos.sh")
else:
    print("❌ Could not find the code to replace.")
    print("The file might already be fixed or have a different format.")
    sys.exit(1)
