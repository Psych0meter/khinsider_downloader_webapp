import os
import re
import json
import logging
import traceback
import sys
import requests
from urllib.parse import unquote
from bs4 import BeautifulSoup
from flask import Flask, render_template, request, Response, stream_with_context

# --- LOGGING CONFIGURATION ---
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

DOWNLOAD_DIR = "/downloads"
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"

# --- UPDATED SANITIZATION ---
def clean_album_title(title):
    """Specific logic to strip KHInsider suffixes."""
    title = re.sub(r'_?MP3_Soundtracks_for_FREE.*$', '', title, flags=re.IGNORECASE)
    title = re.sub(r'\s+MP3\s+Soundtracks\s+for\s+FREE.*$', '', title, flags=re.IGNORECASE)
    return title.strip()

def sanitize_filename(name, is_album=False):
    """Decodes URL characters, removes illegal FS chars, and replaces spaces."""
    name = unquote(name)
    if is_album:
        name = clean_album_title(name)
    name = re.sub(r'[\\/*?:"<>|]', "", name)
    name = name.replace(" ", "_")
    name = re.sub(r'__+', '_', name).strip('_')
    return name

# --- ROUTES ---

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/search', methods=['POST'])
def search():
    query = request.json.get('query', '')
    logger.info(f"Searching for: {query}")
    search_url = f"https://downloads.khinsider.com/search?search={query.replace(' ', '+')}"
    
    try:
        res = requests.get(search_url, headers={"User-Agent": USER_AGENT})
        soup = BeautifulSoup(res.text, 'html.parser')
        results = []
        for row in soup.select('.albumList tr'):
            cols = row.find_all('td')
            if len(cols) > 1:
                link = cols[1].find('a')
                if link:
                    results.append({
                        'album': link.text.strip(), 
                        'url': f"https://downloads.khinsider.com{link['href']}"
                    })
        return {"results": results}
    except Exception as e:
        logger.error(f"Search failed: {str(e)}")
        return {"error": str(e)}, 500

@app.route('/download', methods=['POST'])
def download():
    data = request.json
    album_url = data.get('url')
    preferred_ext = data.get('format', '.flac')

    def generate():
        headers = {"User-Agent": USER_AGENT}
        try:
            if not os.access(DOWNLOAD_DIR, os.W_OK):
                yield f"data: {json.dumps({'line': 'Error: Permission denied on /downloads'})}\n\n"
                return

            yield f"data: {json.dumps({'line': 'Analyzing album tracks...'})}\n\n"
            
            res = requests.get(album_url, headers=headers)
            soup = BeautifulSoup(res.text, 'html.parser')
            
            raw_title = soup.find("title").text.replace(" - Download", "").strip()
            album_title = sanitize_filename(raw_title, is_album=True)
            
            song_links = []
            for a in soup.find_all('a', href=True):
                if '/game-soundtracks/album/' in a['href'] and a['href'].endswith(('.mp3', '.flac', '.m4a')):
                    song_links.append(f"https://downloads.khinsider.com{a['href']}")
            
            song_links = sorted(list(set(song_links)))
            album_path = os.path.join(DOWNLOAD_DIR, album_title)
            os.makedirs(album_path, exist_ok=True)

            total = len(song_links)
            for idx, page_url in enumerate(song_links, 1):
                page_res = requests.get(page_url, headers=headers)
                page_soup = BeautifulSoup(page_res.text, 'html.parser')
                audio_links = [a['href'] for a in page_soup.find_all('a', href=True) if a['href'].endswith(('.mp3', '.flac', '.m4a'))]
                
                if not audio_links: continue

                target_url = next((l for l in audio_links if l.endswith(preferred_ext)), audio_links[0])
                file_name = sanitize_filename(os.path.basename(target_url))
                file_path = os.path.join(album_path, file_name)

                track_num = str(idx).zfill(len(str(total)))
                yield f"data: {json.dumps({'line': f'Track {track_num}/{total}: {file_name}', 'progress': int((idx/total)*100)})}\n\n"
                
                with requests.get(target_url, headers=headers, stream=True) as r:
                    r.raise_for_status()
                    with open(file_path, 'wb') as f:
                        for chunk in r.iter_content(chunk_size=65536):
                            f.write(chunk)

            yield f"data: {json.dumps({'line': '=== FINISHED ===', 'progress': 100})}\n\n"

        except Exception as e:
            logger.error(traceback.format_exc())
            yield f"data: {json.dumps({'line': f'Error: {str(e)}'})}\n\n"

    # CRITICAL: Headers to prevent Docker/Proxy buffering
    return Response(
        stream_with_context(generate()), 
        mimetype='text/event-stream',
        headers={
            'Cache-Control': 'no-cache',
            'X-Accel-Buffering': 'no',
            'Connection': 'keep-alive',
            'Transfer-Encoding': 'chunked'
        }
    )

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)