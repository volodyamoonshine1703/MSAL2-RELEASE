import urllib.request, urllib.parse, re
name = 'Синюков Владимир Николаевич'
url = 'https://myprepod.ru/search/?q=' + urllib.parse.quote(name)
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    html = urllib.request.urlopen(req).read().decode('utf-8')
    match = re.search(r'href="(/prepod/\d+/)"', html)
    if match:
        prepod_url = 'https://myprepod.ru' + match.group(1)
        print('Found prepod URL:', prepod_url)
        p_html = urllib.request.urlopen(urllib.request.Request(prepod_url, headers={'User-Agent': 'Mozilla/5.0'})).read().decode('utf-8')
        score = re.search(r'class="wrapper-points"[^>]*>\s*<span[^>]*>\s*([\d\.]+)\s*</span>', p_html)
        if score:
            print('Score:', score.group(1))
        else:
            print('Score not found in wrapper-points')
            # Fallback regex
            all_scores = re.findall(r'([\d\.]+)', p_html)
            print('Some numbers:', all_scores[:10])
    else:
        print('Not found in search')
except Exception as e:
    print('Error:', e)
