import os
import hashlib
import struct
import aiohttp
import asyncio
from typing import Optional, List

# OpenSubtitles REST API (Newer) - Requires API Key usually, but let's try to set up the structure.
# Or use the "Old" XML-RPC? The REST API is preferred.
# For now, we will use a "VIP" UserAgent or a generic one if possible, 
# but ideally the user should provide an API key in settings. 
# We'll default to a basic implementation.

OPENSUBTITLES_API_URL = "https://api.opensubtitles.com/api/v1"
API_KEY = "nsMKZmXvIaSSe8k5CFSRjZY9PSbTYNRA"

class SubtitleService:
    def __init__(self, api_key: str = API_KEY):
        self.api_key = api_key
        self.headers = {
            "Content-Type": "application/json",
            "User-Agent": "ArcticMedia v2.0", # Replace with registered UA if available
            "Accept": "application/json"
        }
        if self.api_key:
            self.headers["Api-Key"] = self.api_key

    async def compute_file_hash(self, file_path: str) -> str:
        """Compute OpenSubtitles compatible hash."""
        try:
            longlongformat = '<q'  # little-endian long long
            bytesize = struct.calcsize(longlongformat)
            
            with open(file_path, "rb") as f:
                filesize = os.path.getsize(file_path)
                hash = filesize
                
                if filesize < 65536 * 2:
                    return None
                
                for x in range(65536 // bytesize):
                    buffer = f.read(bytesize)
                    (l_value,) = struct.unpack(longlongformat, buffer)
                    hash += l_value
                    hash = hash & 0xFFFFFFFFFFFFFFFF # to remain as 64bit integer
                    
                f.seek(max(0, filesize - 65536), 0)
                for x in range(65536 // bytesize):
                    buffer = f.read(bytesize)
                    (l_value,) = struct.unpack(longlongformat, buffer)
                    hash += l_value
                    hash = hash & 0xFFFFFFFFFFFFFFFF
                    
            return "{:016x}".format(hash)
        except Exception as e:
            print(f"Hash Error: {e}")
            return None

    async def search_subtitles(self, file_path: str, language: str = "en", query: str = None) -> List[dict]:
        """Search for subtitles using hash (best) or query."""
        if not self.api_key:
            print("No OpenSubtitles API Key configured.")
            return []

        hash = await self.compute_file_hash(file_path)
        
        # Strategy:
        # 1. Try Hash (Perfect Match, Sync)
        # 2. If no results, try Query (Clean/File Name)
        
        async with aiohttp.ClientSession() as session:
            # 1. Hash Search
            if hash:
                params = {"languages": language, "moviehash": hash}
                try:
                    async with session.get(f"{OPENSUBTITLES_API_URL}/subtitles", headers=self.headers, params=params) as resp:
                        if resp.status == 200:
                            data = await resp.json()
                            if data.get("total_count", 0) > 0:
                                return data["data"]
                except Exception as e:
                    print(f"OS Hash Search Error: {e}")
            
            # 2. Query Fallback (if provided)
            if query:
                print(f"  [Subs] Hash failed, trying text query: {query}")
                params = {"languages": language, "query": query}
                try:
                    async with session.get(f"{OPENSUBTITLES_API_URL}/subtitles", headers=self.headers, params=params) as resp:
                        if resp.status == 200:
                            data = await resp.json()
                            if data.get("total_count", 0) > 0:
                                return data["data"]
                except Exception as e:
                    print(f"OS Text Search Error: {e}")
                
        return []

    async def download_subtitle(self, file_id: int, target_path: str):
        """Download subtitle and save to target path."""
        if not self.api_key: return False
        
        payload = {"file_id": file_id}
        
        async with aiohttp.ClientSession() as session:
            try:
                # Request Download Link
                async with session.post(f"{OPENSUBTITLES_API_URL}/download", headers=self.headers, json=payload) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        link = data.get("link")
                        if link:
                            # Download content
                            async with session.get(link) as dl_resp:
                                if dl_resp.status == 200:
                                    content = await dl_resp.text()
                                    with open(target_path, "w", encoding="utf-8") as f:
                                        f.write(content)
                                    return True
            except Exception as e:
                print(f"Download Error: {e}")
        return False
        
    async def auto_download(self, file_path: str, fallback_query: str = None):
        """High-level automation: Hash -> Search -> Download Best -> Save."""
        # Check if sub already exists
        base = os.path.splitext(file_path)[0]
        if os.path.exists(base + ".srt") or os.path.exists(base + ".en.srt"):
            return # Already exists
            
        print(f"Auto-Downloading Subs for: {os.path.basename(file_path)}")
        results = await self.search_subtitles(file_path, query=fallback_query)
        
        if results:
            # Pick best (first is usually best)
            best = results[0]
            file_id = best["attributes"]["files"][0]["file_id"]
            
            # Save as Movie.en.srt
            target = base + ".en.srt"
            await self.download_subtitle(file_id, target)
            print(f"Downloaded: {target}")
            return True
            
        return False
