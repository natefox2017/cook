"""Bounded, unauthenticated public-source probe. Not a production fetcher/SSRF boundary."""
import datetime, hashlib, json, re, subprocess, tempfile
from html import unescape
from pathlib import Path
SAMPLES = [
 ('xiachufang', 'https://m.xiachufang.com/recipe/1000357/'),
 ('meishichina', 'https://m.meishichina.com/blog/165984/'),
 ('bilibili', 'https://www.bilibili.com/video/BV1zW411i7Wx/'),
 ('douyin', 'https://www.douyin.com/video/7676101794792282102'),
 ('youtube', 'https://www.youtube.com/watch?v=k_YkQSTvjLk'),
 ('web_jsonld', 'https://www.bbcgoodfood.com/recipes/easy-pancakes'),
]
def recipes(value):
    if isinstance(value, dict):
        t = value.get('@type', [])
        if t == 'Recipe' or isinstance(t, list) and 'Recipe' in t: yield value
        for child in value.values(): yield from recipes(child)
    elif isinstance(value, list):
        for child in value: yield from recipes(child)
def run():
    observations = []
    for platform, url in SAMPLES:
        with tempfile.TemporaryDirectory() as temp:
            body = Path(temp) / 'body'
            result = subprocess.run(['curl', '-L', '--max-redirs', '5', '--max-time', '25', '--max-filesize', '5242880', '-sS', '-A', 'CookSourceProbe/1.0', '-o', str(body), '-w', '%{http_code}\n%{url_effective}\n%{content_type}', url], capture_output=True, text=True)
            raw = body.read_bytes() if body.exists() else b''
            html = raw.decode('utf-8', errors='replace')
            fields = result.stdout.splitlines()
            ld = []
            for script in re.findall(r'<script\b[^>]*type=[\"\']application/ld\+json[\"\'][^>]*>(.*?)</script>', html, re.S | re.I):
                try: ld.extend(recipes(json.loads(script)))
                except ValueError: pass
            title = re.search(r'<title[^>]*>(.*?)</title>', html, re.S | re.I)
            # Counts only. No complete article/media is redistributed.
            observations.append(dict(platform=platform, original_url=url, observed_at=datetime.datetime.now(datetime.timezone.utc).isoformat(), transport_exit=result.returncode, http_status=fields[0] if fields else None, final_url=fields[1] if len(fields)>1 else None, content_type=fields[2] if len(fields)>2 else None, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(), page_title=unescape(title.group(1)).strip() if title else None, recipe_jsonld=[dict(name=r.get('name'), ingredient_count=len(r.get('recipeIngredient', [])), instruction_representation=type(r.get('recipeInstructions')).__name__, instruction_item_count=len(r.get('recipeInstructions', [])) if isinstance(r.get('recipeInstructions'), list) else None, instruction_text_chars=len(r.get('recipeInstructions', '')) if isinstance(r.get('recipeInstructions'), str) else None, author_present=bool(r.get('author')), ingredient_strings_valid=all(isinstance(v,str) and v.strip() for v in r.get('recipeIngredient', [])), instructions_nonempty=bool(r.get('recipeInstructions'))) for r in ld], ingredient_markup_count=len(re.findall(r'itemprop=[\"\']recipeIngredient',html,re.I)), instruction_markup_count=len(re.findall(r'itemprop=[\"\']recipeInstructions',html,re.I)), has_recipe_title='番茄炒蛋' in html, has_steps_marker='步骤' in html, error=result.stderr.strip()[:300]))
    output = Path(__file__).with_name('observations.json')
    output.write_text(json.dumps({'method':'macOS curl; no cookies/login/JS/media/AI; one GET per sample; raw responses discarded', 'observations':observations}, ensure_ascii=False, indent=2)+'\n')
    print(output.read_text())
if __name__ == '__main__': run()
