import os
import sys
import time
import threading
import subprocess
import webbrowser
import multiprocessing
from collections import deque

# Tkinter & System Tray
try:
    import tkinter as tk
    from tkinter import ttk, messagebox
except ImportError:
    tk = None

try:
    import pystray
    from PIL import Image, ImageDraw
except ImportError:
    pystray = None
    Image = None

# Constants
PORT = 8085
HOST = "0.0.0.0"
URL = f"http://127.0.0.1:{PORT}"

def resource_path(relative_path):
    """ Get absolute path to resource, works for dev and for PyInstaller """
    try:
        # PyInstaller creates a temp folder and stores path in _MEIPASS
        base_path = sys._MEIPASS
    except Exception:
        base_path = os.path.abspath(".")

    return os.path.join(base_path, relative_path)

def run_server_process(port=8085):
    """Logic to run uvicorn server"""
    try:
        from main import app
        import uvicorn
        print(f"Starting Server on {HOST}:{port}")
        # workers must NOT be set — uvicorn worker spawning re-launches sys.executable
        # which in a frozen .app re-runs the GUI, not the server.
        uvicorn.run(app, host=HOST, port=port, log_level="info")
    except Exception as e:
        import traceback, tempfile
        log_path = os.path.join(tempfile.gettempdir(), "arctic_media_crash.log")
        with open(log_path, "w") as f:
            traceback.print_exc(file=f)
            f.write(f"\nException: {e}\n")
        print(f"Server crashed. See {log_path}")
        sys.exit(1)

class ServerManager:
    def __init__(self):
        self.proc = None
        self.lock = threading.Lock()
        self.log_buffer = deque(maxlen=1000)
        
    def _free_port(self, port):
        """Kill any process listening on the port, then wait until it's actually free."""
        import signal, socket, time
        try:
            result = subprocess.run(
                ['lsof', '-ti', f':{port}'],
                capture_output=True, text=True
            )
            pids = [p.strip() for p in result.stdout.strip().split('\n')
                    if p.strip().isdigit()]
            for pid_str in pids:
                try:
                    os.kill(int(pid_str), signal.SIGKILL)
                except ProcessLookupError:
                    pass
            if pids:
                # Wait up to 3 seconds for the OS to release the port
                for _ in range(30):
                    try:
                        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                            s.bind(('0.0.0.0', port))
                        break  # port is free
                    except OSError:
                        time.sleep(0.1)
        except Exception:
            pass

    def start(self, port=8085):
        with self.lock:
            if self.proc and self.proc.poll() is None:
                return

            self._free_port(port)

            if getattr(sys, 'frozen', False):
                # Run the EXE itself with --server argument
                cmd = [sys.executable, "--server", "--port", str(port)]
                creationflags = 0x08000000 if os.name == 'nt' else 0  # CREATE_NO_WINDOW (Windows only)
            else:
                # Dev mode
                cmd = [sys.executable, "gui_main.py", "--server", "--port", str(port)]
                creationflags = 0x08000000 if os.name == "nt" else 0

            env = os.environ.copy()
            
            self.proc = subprocess.Popen(
                cmd,
                env=env,
                creationflags=creationflags,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                encoding='utf-8',
                errors='replace'
            )
            
            # Start a thread to read stdout/stderr
            threading.Thread(target=self._read_output, daemon=True).start()

    def _read_output(self):
        try:
            for line in self.proc.stdout:
                self.log_buffer.append(line)
        except:
            pass

    def stop(self):
        with self.lock:
            if self.proc:
                self.proc.terminate()
                self.proc = None

    def is_running(self):
        return self.proc is not None and self.proc.poll() is None

class App:
    def __init__(self):
        if not tk:
            raise RuntimeError("Tkinter not found")
            
        self.manager = ServerManager()
        self.root = tk.Tk()
        self.root.title("Arctic Media Server")
        self.root.geometry("450x300")
        
        # Icon
        try:
            icon_path = resource_path("icons/app.ico")
            self.root.iconbitmap(icon_path)
        except:
            pass

        self.style_ui()
        self.build_ui()
        
        self.root.protocol("WM_DELETE_WINDOW", self.on_minimize)
        
        # Tray
        self.tray_icon = None
        self.setup_tray()
        
        # Log window ref
        self.log_window_ref = None

    def style_ui(self):
        # Dark Themeish
        bg_color = "#1e1e1e"
        fg_color = "#ffffff"
        
        self.root.configure(bg=bg_color)
        
        style = ttk.Style()
        style.theme_use('clam')
        
        style.configure("TFrame", background=bg_color)
        style.configure("TLabel", background=bg_color, foreground=fg_color, font=("Segoe UI", 10))
        style.configure("TButton", background="#333333", foreground=fg_color, borderwidth=1, focuscolor="none")
        style.map("TButton", background=[('active', '#444444')])

    def build_ui(self):
        main_frame = ttk.Frame(self.root, padding=20)
        main_frame.pack(fill="both", expand=True)
        
        # Header
        ttk.Label(main_frame, text="Arctic Media Server", font=("Segoe UI", 14, "bold")).pack(pady=(0, 20))
        
        # Status
        self.status_var = tk.StringVar(value="Status: Stopped")
        self.status_label = ttk.Label(main_frame, textvariable=self.status_var)
        self.status_label.pack(pady=(0, 20))
        
        # Port Selection
        port_frame = ttk.Frame(main_frame)
        port_frame.pack(fill="x", pady=5)
        ttk.Label(port_frame, text="Port:").pack(side="left", padx=(0, 5))
        self.port_var = tk.StringVar(value=str(PORT))
        ttk.Entry(port_frame, textvariable=self.port_var, width=10).pack(side="left")
        
        # Buttons
        btn_frame = ttk.Frame(main_frame)
        btn_frame.pack(fill="x", pady=10)
        
        ttk.Button(btn_frame, text="Start Server", command=self.start_server).pack(side="left", expand=True, fill="x", padx=5)
        ttk.Button(btn_frame, text="Stop Server", command=self.stop_server).pack(side="left", expand=True, fill="x", padx=5)
        
        ttk.Button(main_frame, text="Open Web Dashboard", command=self.open_dashboard).pack(fill="x", pady=5)
        ttk.Button(main_frame, text="Show Logs", command=self.show_logs).pack(fill="x", pady=5)

        # Update loop
        self.update_status()

    def update_status(self):
        if self.manager.is_running():
            self.status_var.set("Status: Running")
            self.status_label.configure(foreground="#4caf50") # Green
        else:
            self.status_var.set("Status: Stopped")
            self.status_label.configure(foreground="#f44336") # Red
            
        self.root.after(1000, self.update_status)

    def start_server(self):
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
            messagebox.showerror("Error", f"Failed to start server: {e}")
        
    def stop_server(self):
        self.manager.stop()
        
    def open_dashboard(self):
        try:
            p = int(self.port_var.get())
            u = f"http://127.0.0.1:{p}"
            webbrowser.open(u)
        except:
            webbrowser.open(URL)
        
    def show_logs(self):
        if self.log_window_ref and self.log_window_ref.winfo_exists():
            self.log_window_ref.lift()
            return
            
        top = tk.Toplevel(self.root)
        top.title("Server Logs")
        top.geometry("800x500")
        top.configure(bg="#1e1e1e")
        try:
            top.iconbitmap(resource_path("icons/app.ico"))
        except: pass
        
        self.log_window_ref = top

        # Toolbar with controls
        toolbar = tk.Frame(top, bg="#1e1e1e")
        toolbar.pack(fill="x", padx=4, pady=(4, 0))

        paused_var = tk.BooleanVar(value=False)

        def toggle_pause():
            if paused_var.get():
                paused_var.set(False)
                pause_btn.config(text="⏸ Pause")
            else:
                paused_var.set(True)
                pause_btn.config(text="▶ Resume")

        def clear_logs():
            text_area.config(state="normal")
            text_area.delete(1.0, tk.END)
            text_area.config(state="disabled")
            seen_count[0] = len(self.manager.log_buffer)

        pause_btn = tk.Button(toolbar, text="⏸ Pause", command=toggle_pause,
                              bg="#333333", fg="white", relief="flat", padx=8)
        pause_btn.pack(side="left", padx=(0, 4))

        tk.Button(toolbar, text="🗑 Clear", command=clear_logs,
                  bg="#333333", fg="white", relief="flat", padx=8).pack(side="left")

        text_area = tk.Text(top, bg="#000000", fg="#00ff00", font=("Consolas", 9),
                            state="disabled", wrap="none")
        
        # Scrollbars
        vsb = tk.Scrollbar(top, orient="vertical", command=text_area.yview)
        hsb = tk.Scrollbar(top, orient="horizontal", command=text_area.xview)
        text_area.configure(yscrollcommand=vsb.set, xscrollcommand=hsb.set)

        hsb.pack(side="bottom", fill="x")
        vsb.pack(side="right", fill="y")
        text_area.pack(fill="both", expand=True)

        # Track how many lines from log_buffer we've already written
        seen_count = [0]

        def update_logs():
            if not top.winfo_exists():
                return

            if not paused_var.get():
                buf = list(self.manager.log_buffer)
                new_lines = buf[seen_count[0]:]

                if new_lines:
                    # Only scroll to bottom if user was already there
                    at_bottom = text_area.yview()[1] >= 0.99

                    text_area.config(state="normal")
                    text_area.insert(tk.END, "".join(new_lines))
                    text_area.config(state="disabled")
                    seen_count[0] = len(buf)

                    if at_bottom:
                        text_area.see(tk.END)

            top.after(1000, update_logs)

        update_logs()

    def on_minimize(self):
        self.root.withdraw()
        if self.tray_icon:
            self.tray_icon.notify("Server is running in background", "Arctic Media")

    def quit_app(self, icon=None, item=None):
        self.manager.stop()
        if self.tray_icon:
            self.tray_icon.stop()
        self.root.quit()
        sys.exit(0)

    def show_window(self, icon=None, item=None):
        self.root.deiconify()
        self.root.lift()

    def setup_tray(self):
        if not pystray: return
        
        try:
            image = Image.open(resource_path("icons/app.ico"))
        except Exception:
            # Fallback if icon missing: Create a simple colored box
            image = Image.new('RGB', (64, 64), color=(73, 109, 137))
        
        menu = pystray.Menu(
            pystray.MenuItem("Open", self.show_window),
            pystray.MenuItem("Start", self.start_server),
            pystray.MenuItem("Stop", self.stop_server),
            pystray.MenuItem("Exit", self.quit_app)
        )
        
        self.tray_icon = pystray.Icon("ArcticMedia", image, "Arctic Media Server", menu)
        threading.Thread(target=self.tray_icon.run, daemon=True).start()

    def run(self):
        self.start_server() # Auto-start
        self.root.mainloop()

if __name__ == "__main__":
    multiprocessing.freeze_support()
    
    # CHECK FOR SERVER MODE ARGUMENT
    if "--server" in sys.argv:
        port = 8085
        if "--port" in sys.argv:
            try:
                idx = sys.argv.index("--port")
                port = int(sys.argv[idx+1])
            except:
                pass
        run_server_process(port)
    else:
        app = App()
        app.run()
