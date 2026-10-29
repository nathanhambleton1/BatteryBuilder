from pathlib import Path
import re
root=Path(__file__).resolve().parent
html=(root/'undertow.html').read_text()
html=re.sub(r'<link rel="stylesheet" href="([^"]+)">',lambda m:'<style>'+ (root/m[1]).read_text()+'</style>',html)
html=re.sub(r'<script src="([^"]+)"></script>',lambda m:'<script>'+ (root/m[1]).read_text().replace('</script','<\\/script')+'</script>',html)
(root/'undertow-offline.html').write_text(html)
