
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
    uvicorn.run("main:app", host="0.0.0.0", port=8085, reload=True)
