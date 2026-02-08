import requests
import sys

BASE_URL = "http://localhost:8085/api/v1/settings"

def test_settings_api():
    print(f"Testing Settings API at {BASE_URL}")
    
    # 1. Update Setting
    print("\n1. Updating custom_domain...")
    payload = {"key": "custom_domain", "value": "https://api-test-domain.com"}
    try:
        response = requests.post(BASE_URL, json=payload)
        response.raise_for_status()
        print(f"Success: {response.json()}")
    except Exception as e:
        print(f"FAILED to update setting: {e}")
        sys.exit(1)

    # 2. Get Setting
    print("\n2. Fetching custom_domain...")
    try:
        response = requests.get(f"{BASE_URL}/custom_domain")
        response.raise_for_status()
        data = response.json()
        print(f"Success: {data}")
        
        if data.get("value") == "https://api-test-domain.com":
            print("VERIFICATION PASSED: Value matches.")
        else:
            print(f"VERIFICATION FAILED: Expected 'https://api-test-domain.com', got '{data.get('value')}'")
            sys.exit(1)
            
    except Exception as e:
        print(f"FAILED to get setting: {e}")
        sys.exit(1)

if __name__ == "__main__":
    test_settings_api()
