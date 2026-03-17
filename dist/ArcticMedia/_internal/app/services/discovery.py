import asyncio
import socket
import struct
import re
import aiohttp
import xml.etree.ElementTree as ET

SSDP_ADDR = "239.255.255.250"
SSDP_PORT = 1900
SSDP_MX = 2
SSDP_ST = "roku:ecp"

SSDP_DISCOVER = (
    "M-SEARCH * HTTP/1.1\r\n"
    f"Host: {SSDP_ADDR}:{SSDP_PORT}\r\n"
    f"Man: \"ssdp:discover\"\r\n"
    f"ST: {SSDP_ST}\r\n"
    f"MX: {SSDP_MX}\r\n\r\n"
)

async def _fetch_device_info(location_url: str, ip: str) -> dict | None:
    """Fetch 'friendlyName' from Roku's XML device-info."""
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(location_url, timeout=3) as resp:
                if resp.status == 200:
                    text = await resp.text()
                    root = ET.fromstring(text)
                    # XML namespace might be present: <friendlyName> or <{...}friendlyName>
                    friendly_name_el = root.find(".//friendlyName")
                    if friendly_name_el is None:
                        # try with any namespace
                        friendly_name_el = root.find(".//*[local-name()='friendlyName']")
                    
                    name = friendly_name_el.text if friendly_name_el is not None else "Unknown Roku"
                    return {"ip": ip, "name": name, "location": location_url}
    except Exception as e:
        print(f"Error fetching Roku info from {location_url}: {e}")
    return None

class SSDPProtocol(asyncio.DatagramProtocol):
    def __init__(self, message, on_response):
        self.message = message
        self.on_response = on_response
        self.transport = None

    def connection_made(self, transport):
        self.transport = transport
        self.transport.sendto(self.message.encode(), (SSDP_ADDR, SSDP_PORT))

    def datagram_received(self, data, addr):
        self.on_response(data.decode(errors='ignore'), addr)

async def discover_rokus(timeout: int = 3) -> list[dict]:
    """
    Broadcasts SSDP search and returns a list of dictionaries with 'ip' and 'name'.
    """
    loop = asyncio.get_running_loop()
    responses = []
    
    def on_response(data: str, addr: tuple):
        # The addr is (ip, port)
        ip = addr[0]
        # Look for the LOCATION header which contains the URL for device info
        loc_match = re.search(r'(?i)^location:\s*(http://[^\s]+)', data, re.MULTILINE)
        if loc_match:
            location = loc_match.group(1)
            # Avoid duplicates
            if not any(r['location'] == location for r in responses):
                responses.append({"ip": ip, "location": location})

    # Create UDP socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setblocking(False)

    transport, protocol = await loop.create_datagram_endpoint(
        lambda: SSDPProtocol(SSDP_DISCOVER, on_response),
        sock=sock
    )

    # Wait for responses
    await asyncio.sleep(timeout)
    transport.close()

    # Now fetch friendly names from the specific locations
    devices = []
    tasks = []
    for r in responses:
        tasks.append(_fetch_device_info(r['location'], r['ip']))
        
    results = await asyncio.gather(*tasks)
    for res in results:
        if res:
            devices.append(res)
            
    return devices
