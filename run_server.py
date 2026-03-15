
import uvicorn
import os
import sys

# Add the current directory to sys.path to ensure modules can be imported
sys.path.append(os.getcwd())

if __name__ == "__main__":
    print("Starting Arctic Media Server...")
    print("Binding to 0.0.0.0:8085")
    print("Ensure your custom domain points to this machine's IP address.")
    
    # Run Uvicorn
    # reload=True for development (restart on code changes)
    # Auto-open browser
    import webbrowser
    from threading import Timer
    import sys
    import multiprocessing

    # Prevent infinite spawning on Windows when frozen
    multiprocessing.freeze_support()
    
    # Check if running as script (dev) or frozen exe (prod)
    if getattr(sys, 'frozen', False):
        # FROZEN (EXE)
        # Disable reload, set loop policy if needed
        reload = False
        
        # Open browser only in the main process (though freeze_support helps, good to be safe)
        def open_browser():
            webbrowser.open("http://localhost:8085")
        Timer(1.5, open_browser).start()
    else:
        # DEV (SCRIPT)
        reload = True
        # In dev, reload handles restart, so we might not want to open browser every time
        # But for 'run_server.py' usage, it's fine.
        def open_browser():
            webbrowser.open("http://localhost:8085")
        Timer(1.5, open_browser).start()

    # Determine workers - separate from reload
    # uvicorn.run with reload=True and workers=1 (default) uses subprocesses
    # uvicorn.run with reload=False runs in-process or uses workers if specified.
    # For PyInstaller, we MUST use workers=1 and reload=False to avoid subprocess hell without careful handling.
    
    print(f"Starting Server (Frozen={getattr(sys, 'frozen', False)})...")
    
    # IMPORT APP DIRECTLY to avoid "Could not import module 'main'" in frozen exe
    from main import app
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8085, workers=1)
